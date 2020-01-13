!<  +---------------------------------------------------------------+
!     Simstrat model for simulation of
!     vertical transport in lakes and reservoirs
!<  +---------------------------------------------------------------+

program simstrat_main
   use strat_kinds
   use strat_inputfile, only: SimstratSimulationFactory
   use strat_outputfile
   use strat_simdata, only: SimulationData
   use strat_forcing
   use utilities
   use strat_stability, only: StabilityModule
   use strat_windshear
   use strat_statevar
   use strat_temp
   use strat_solver
   use strat_discretization
   use strat_keps
   use strat_turbulence
   use strat_ice
   use strat_transport
   use strat_absorption
   use strat_advection
   use strat_lateral
   use forbear
   use, intrinsic :: ieee_arithmetic

   implicit none

   ! Instantiate all modules
   ! note that some are pointers/targets for polymorphism reasons
   type(SimstratSimulationFactory) :: factory
   class(SimulationData), pointer :: simdata
   type(ThomasAlgSolver) :: solver
   type(EulerIDiscretizationMFQ) :: euler_i_disc
   type(EulerIDiscretizationKEPS) :: euler_i_disc_keps
   type(ForcingModule) :: mod_forcing
   type(StabilityModule) :: mod_stability
   type(InterpolatingLogger) :: logger
   type(TempModelVar) :: mod_temperature
   type(UVModelVar) :: mod_u, mod_v
   type(KModelVar) :: mod_k
   type(EpsModelVar) :: mod_eps
   type(TransportModVar) :: mod_s
   type(TurbulenceModule) :: mod_turbulence
   type(IceModule) :: mod_ice
   type(AbsorptionModule) :: mod_absorption
   type(AdvectionModule) :: mod_advection
   type(LateralModule), target :: mod_lateral_normal
   type(LateralRhoModule), target :: mod_lateral_rho
   class(GenericLateralModule), pointer :: mod_lateral
   ! Instantiate progress bar object
   type(bar_object):: bar

   character(len=100) :: arg
   character(len=:), allocatable :: ParName
   character(len=:), allocatable :: snapshot_file_path
   logical :: continue_from_snapshot = .false.
   integer(8) :: simulation_end_time

   ! Print some information
   write (6, *) 'Simstrat version '//version
   write (6, *) 'This software has been developed at eawag - Swiss Federal Institute of Aquatic Science and Technology'
   write (6, *) ''

   ! Get first cli argument
   call get_command_argument(1, arg)
   ParName = trim(arg)
   if (ParName == '') ParName = 'simstrat.par'

   ! Initialize model from input files
   call factory%initialize_model(ParName, simdata)

   ! Initialize Discretization
   call euler_i_disc%init(simdata%grid)
   call euler_i_disc_keps%init(simdata%grid)

   ! Initialize forcing module
   call mod_forcing%init(simdata%model_cfg, &
                         simdata%model_param, &
                         simdata%input_cfg%ForcingName, &
                         simdata%grid)

   ! Initialize albedo data used for water albedo calculation, if switch is off
   if (simdata%model_cfg%user_defined_water_albedo) then
      simdata%model%albedo_water = simdata%model_param%wat_albedo
   else
      call mod_forcing%init_albedo(simdata%model, simdata%sim_cfg)
   end if

   ! Initialize absorption module
   call mod_absorption%init(simdata%model_cfg, &
                            simdata%model_param, &
                            simdata%input_cfg%AbsorpName, &
                            simdata%grid)

   ! If there is advection (due to inflow)
   if (simdata%model%has_advection) then
      ! Initialize advection module
      call mod_advection%init(simdata%model_cfg, &
                           simdata%model_param, &
                           simdata%grid)

      ! Initialize lateral module based on configuration
      if (simdata%model_cfg%inflow_placement == 1) then
         ! Gravity based inflow
         mod_lateral => mod_lateral_rho
      else
         ! User defined inflow depths
         mod_lateral => mod_lateral_normal
      end if
      call mod_lateral%init(simdata%model_cfg, &
                           simdata%model_param, &
                           simdata%grid)
   end if

   ! Binary simulation snapshot file
   snapshot_file_path = simdata%output_cfg%PathOut//'/simulation-snapshot.dat'
   if (simdata%sim_cfg%continue_from_snapshot) then
      inquire (file=snapshot_file_path, exist=continue_from_snapshot)
      print *,"continue from snapshot",continue_from_snapshot
   end if

   ! Setup logger
   call logger%initialize(simdata%sim_cfg, simdata%output_cfg, simdata%grid, continue_from_snapshot)

   ! Calculate simulation_end_time
   if (simdata%output_cfg%thinning_interval > 0) then
      simulation_end_time = int((simdata%sim_cfg%end_datum - simdata%sim_cfg%start_datum) * SECONDS_PER_DAY + 0.5)
   else
      simulation_end_time = simdata%output_cfg%simulation_times_for_output( &
            size(simdata%output_cfg%simulation_times_for_output))
   end if

   ! Initialize simulation modules
   call mod_stability%init(simdata%grid, simdata%model_cfg, simdata%model_param)
   call mod_turbulence%init(simdata%grid, simdata%model_cfg, simdata%model_param)
   call mod_ice%init(simdata%model_cfg, simdata%model_param, simdata%grid)

   ! Set temperature state var to have nu_h as nu and T as model variable
   call mod_temperature%init(simdata%model_cfg, simdata%grid, solver, euler_i_disc, simdata%model%nuh, simdata%model%T, simdata%grid%ubnd_vol)

   ! Set U and V var to have num as nu and U reps V as model variable
   ! also, assign shear stress in model for this variable
   call mod_u%init(simdata%model_cfg, simdata%grid, solver, euler_i_disc, simdata%model%num, simdata%model%U, simdata%grid%ubnd_vol)
   call mod_u%assign_shear_stress(simdata%model%tx)

   call mod_v%init(simdata%model_cfg, simdata%grid, solver, euler_i_disc, simdata%model%num, simdata%model%V, simdata%grid%ubnd_vol)
   call mod_v%assign_shear_stress(simdata%model%ty)

   ! Set mod_s (transport module) to have nuh as nu and to manipulate S based on dS
   call mod_s%init(simdata%model_cfg, simdata%grid, solver, euler_i_disc, simdata%model%nuh, simdata%model%S, simdata%grid%ubnd_vol)
   call mod_s%assign_external_source(simdata%model%dS)

   ! Set up K and eps state vars with keps discretization and avh as nu
   call mod_k%init(simdata%model_cfg, simdata%grid, solver, euler_i_disc_keps, simdata%model%avh, simdata%model%K, simdata%grid%ubnd_fce)
   call mod_eps%init(simdata%model_cfg, simdata%grid, solver, euler_i_disc_keps, simdata%model%avh, simdata%model%eps, simdata%grid%ubnd_fce)

   call run_simulation()

   ! Close logger files after simulation
   call logger%close()

contains

   subroutine run_simulation()
      ! initialize a bar with the progress percentage counter
      call bar%initialize(filled_char_string='#', &
         prefix_string=' Simulation progress |',  &
         suffix_string='| ', add_progress_percent=.true., &
         add_date_time=.true., &
         max_value=(simdata%sim_cfg%end_datum-simdata%sim_cfg%start_datum))

      ! start the progress bar
      call bar%start

      !! run the marching time loop
      call ok("Start day: "//real_to_str(simdata%sim_cfg%start_datum, '(F7.1)'))
      if (continue_from_snapshot) then
         call load_snapshot(snapshot_file_path)
         call ok("Simulation snapshot successfully read. Snapshot day: "//real_to_str(simdata%model%datum, '(F7.1)'))
         call logger%calculate_simulation_time_for_next_output(simdata%model%simulation_time)
      else
         call logger%log(simdata)
      end if
      call ok("End day: "//real_to_str(simdata%sim_cfg%end_datum, '(F7.1)'))
      call logger%start()

      ! Run the simulation loop
      ! Run simulation until end datum or until no more results are required by the output time file
      do while (simdata%model%simulation_time < simulation_end_time)

         ! Advance to the next timestep
         simdata%model%simulation_time = simdata%model%simulation_time + simdata%sim_cfg%timestep
         simdata%model%datum = datum(simdata%sim_cfg%start_datum, simdata%model%simulation_time)

         ! ************************************
         ! ***** Compute next model state *****
         ! ************************************

         ! Update water albedo
         if (.not. simdata%model_cfg%user_defined_water_albedo) then
            call mod_forcing%update_albedo(simdata%model)
         end if

         ! Update forcing
         call mod_forcing%update(simdata%model)

         ! Update absorption
         call mod_absorption%update(simdata%model)

         ! Update physics
         call mod_stability%update(simdata%model)

         ! If there is inflow/outflow do advection part
         if (simdata%model%has_advection) then
            ! Treat inflow/outflow
            call mod_lateral%update(simdata%model)
            ! Set old lake level (before it is changed by advection module)
            simdata%grid%lake_level_old = simdata%grid%z_face(simdata%grid%ubnd_fce)
            ! Update lake advection using the inflow/outflow data
            call mod_advection%update(simdata%model)
            ! Update lake level
            simdata%grid%lake_level = simdata%grid%z_face(simdata%grid%ubnd_fce)
         end if

         ! Update Coriolis
         call mod_forcing%update_coriolis(simdata%model)

         ! Update and solve U and V - terms
         call mod_u%update(simdata%model, simdata%model_param)
         call mod_v%update(simdata%model, simdata%model_param)

         ! Update and solve T - terms
         call mod_temperature%update(simdata%model, simdata%model_param)

         ! Update and solve transportation terms (here: Salinity S only)
         call mod_S%update(simdata%model, simdata%model_param)

         ! update turbulence states
         call mod_turbulence%update(simdata%model, simdata%model_param)

         ! Solve k & eps
         call mod_k%update(simdata%model, simdata%model_param)
         call mod_eps%update(simdata%model, simdata%model_param)

         ! Update ice
         if (simdata%model_cfg%ice_model == 1) then
            call mod_ice%update(simdata%model, simdata%model_param)
         end if

         ! Call logger to write files
         call logger%log(simdata)

         ! This logical is used to do some allocation in the forcing, absorption and lateral subroutines during the first timestep
         simdata%model%first_timestep = .false.

         !update the progress bar
         call bar%update(current=(simdata%model%datum-simdata%sim_cfg%start_datum))

      end do
      call save_snapshot(snapshot_file_path)
   end subroutine

   subroutine save_snapshot(file_path)
      implicit none
      character(len=*), intent(in) :: file_path

      open(80, file=file_path, Form='unformatted', Action='Write')
      call simdata%model%save()
      call simdata%grid%save()
      call mod_absorption%save()
      call mod_lateral%save()
      call logger%save()
      close(80)
   end subroutine

   subroutine load_snapshot(file_path)
      implicit none
      character(len=*), intent(in) :: file_path

      open(81, file=file_path, Form='unformatted', Action='Read')
      call simdata%model%load()
      call simdata%grid%load()
      call mod_absorption%load()
      call mod_lateral%load()
      call logger%load()
      close(81)
   end subroutine

end program simstrat_main
