!     +---------------------------------------------------------------+
!     |  Simstrat - AED2 interface
!     +---------------------------------------------------------------+

module simstrat_aed2
   use strat_simdata
   use strat_grid
   use strat_solver
   use utilities
   use aed2_common
   use aed2_core

   implicit none
   private

   type, public :: SimstratAED2
      class(AED2Config), pointer :: aed2_cfg
      class(StaggeredGrid), pointer :: grid

      !# Arrays for state and diagnostic variables
      real(RK),pointer,dimension(:,:) :: cc !# water quality array: nlayers, nvars
      real(RK),pointer,dimension(:,:) :: cc_diag
      real(RK),pointer,dimension(:) :: cc_diag_hz
      real(RK),pointer,dimension(:) :: tss
      real(RK),pointer,dimension(:) :: sed_zones

      ! Arrays for fluxes of state variables
      real(RK),pointer,dimension(:) :: flux_atm
      real(RK),pointer,dimension(:) :: flux_ben
      real(RK),pointer,dimension(:,:) :: flux_pel
      real(RK),pointer,dimension(:,:) :: flux_zone

      !# Arrays for work, vertical movement, and cross-boundary fluxes
      real(RK),allocatable,dimension(:,:) :: ws
      real(RK),allocatable,dimension(:)   :: total
      real(RK),allocatable,dimension(:)   :: local

      !# Arrays for environmental variables not supplied externally.
      real(RK),pointer,dimension(:) :: par, pres
      real(RK),pointer,dimension(:) :: uva, uvb, nir

      ! Column pointers
      type (aed2_column_t),pointer,dimension(:) :: column, column_sed

      !# External variables
      integer  :: w_adv_ctr    ! Scheme for vertical advection (0 if not used)

      character(len=48),pointer :: names(:)
      character(len=48),allocatable :: bennames(:)

      integer,allocatable,dimension(:) :: externalid

      real(RK),allocatable,dimension(:) :: min_, max_

      integer :: n_aed2_vars, n_vars, n_vars_ben, n_vars_diag, n_vars_diag_sheet
      integer :: zone_var = 0

      logical :: there_is_inflow = .FALSE.
      logical :: plunging_inflow = .FALSE.

      ! Variables for in-/outflow
      real(RK), dimension(:, :), allocatable   :: z_Inp_AED2, Q_start_AED2, Qs_start_AED2, Q_end_AED2, Qs_end_AED2, Q_read_start_AED2, Q_read_end_AED2
      real(RK), dimension(:, :), allocatable   :: Inp_read_start_AED2, Inp_read_end_AED2, Qs_read_start_AED2, Qs_read_end_AED2, Q_inp_AED2
      real(RK), dimension(:), allocatable :: tb_start, tb_end ! Input depths, start time, end time
      integer, dimension(:), allocatable :: eof, nval, nval_deep, nval_surface

   contains
      procedure, pass(self), public :: init
      procedure, pass(self), public :: update
   end type SimstratAED2

contains
   include 'simstrat_aed2_subroutines.f90'
   include 'simstrat_aed2_physics.f90'

   ! The init function is called once in within the initialization of Simstrat. The init sets up the memory, reads
   ! the AED2 configuration file, links the external Simstrat variables and sets the initial conditions of AED2 variables.

   subroutine init(self, state, grid, model_cfg, aed2_cfg)
      implicit none

      ! Arguments
      class(SimstratAED2) :: self
      class(ModelState) :: state
      class(StaggeredGrid), target :: grid
      class(ModelConfig), target :: model_cfg
      class(AED2Config), target :: aed2_cfg

      ! Local variables
      character(len=80) :: fname
      character(len=64) :: models(64)
      namelist /aed2_models/ models
      type(aed2_variable_t),pointer :: tvar
      integer i, status, av, v, sv

      ! Add grid and aed2_cfg to SimstratAED2 object
      self%grid => grid
      self%aed2_cfg => aed2_cfg

      associate (n_aed2_vars => self%n_aed2_vars, &
                 n_vars => self%n_vars, &
                 n_vars_ben => self%n_vars_ben, &
                 n_vars_diag => self%n_vars_diag, &
                 n_vars_diag_sheet => self%n_vars_diag_sheet)

         ! AED2 config file
         fname = 'aed2.nml'

         if ( aed2_init_core('.') /= 0 ) call error("Initialisation of aed2_core failed")
         call aed2_print_version

         ! Create model tree
         write (6,*) "     Processing aed2_models config from ", trim(fname)
         open(50,file=fname,action='read',status='old',iostat=status)
         if ( status /= 0 ) then
            call error("Cannot open file " // trim(fname))
            stop
         end if

         models = ''
         read(50, nml=aed2_models, iostat=status)
         if ( status /= 0 ) then
            call error("Cannot read namelist entry aed2_models")
            stop
         end if

         do i=1,size(models)
            if (models(i)=='') exit
            call aed2_define_model(models(i), 50)
         end do

         ! Finished reading AED2 config
         close(50)
         write (6,*) "      AED2 file parsing completed."

         ! Assign number of different variables
         n_aed2_vars = aed2_core_status(n_vars, n_vars_ben, n_vars_diag, n_vars_diag_sheet)

         ! Print variable information to screen
         print "(/,5X,'AED2 : n_aed2_vars = ',I3,' ; MaxLayers         = ',I4)",n_aed2_vars,self%grid%nz_grid
         print "(  5X,'AED2 : n_vars      = ',I3,' ; n_vars_ben        = ',I3)",n_vars,n_vars_ben
         print "(  5X,'AED2 : n_vars_diag = ',I3,' ; n_vars_diag_sheet = ',I3,/)",n_vars_diag,n_vars_diag_sheet

         ! Check variable dependencies
         call check_data(self)

         ! Allocate space for the allocatables/pointers of this module
         call allocate_memory(self)

         ! Allocate memory for AED2 state and inflow matrix used by Simstrat
         state%AED2_state => self%cc
         allocate(state%AED2_inflow(self%grid%nz_grid, n_vars + n_vars_ben))
         state%n_AED2 = n_vars + n_vars_ben

         ! Define column pointer (which is the object that is handed over to AED2 at every timestep)
         ! It containes external (Simstrat) variables like T and S, but also the variables of this (SimstratAED2) module
         call define_column(self, state)
         !if (benthic_mode .GT. 1) call define_sed_column(column_sed, n_zones, flux, flux_atm, flux_ben)

         ! Assign name, min and max values of variables, print names to screen
         call assign_var_names(self)
         allocate(state%AED2_names(n_vars + n_vars_ben))
         state%AED2_names => self%names

         ! Now set initial values of AED2 variables
         v = 0 ; sv = 0;
         do av=1,self%n_aed2_vars
            if ( .not.  aed2_get_var(av, tvar) ) stop "Error getting variable info"
            if ( .not. ( tvar%extern .or. tvar%diag) ) then  !# neither global nor diagnostic variable
               if ( tvar%sheet ) then
                  sv = sv + 1
                  call AED2_InitCondition(self, self%cc(:, n_vars + sv), tvar%name, tvar%initial)
               else
                  v = v + 1
                  call AED2_InitCondition(self, self%cc(:, v), tvar%name, tvar%initial)
               end if
            end if
         end do

         ! Update in-/outflow of AED2 variables (to be used in following advection step in the main loop)
         ! Maybe we don't need to calculate this in the init, but then the advection function in the main loop
         ! Doesn't have the AED2 inflow at the first timestep (as the AED2 update happens after the advection update)
         if(state%has_advection .and. model_cfg%inflow_mode > 0) then
            ! If the inflows are not empty and advection is not turned off
            self%there_is_inflow = .TRUE.
            if (model_cfg%inflow_mode == 2) then
               ! If the inflows plunge according to density
               self%plunging_inflow = .TRUE.
               call lateral_rho_update_AED2(self, state)
            else if (model_cfg%inflow_mode == 1) then
               ! If inflow depths are given in the file
               self%plunging_inflow = .FALSE.
               call lateral_update_AED2(self, state)
            end if
         end if

         write(*,"(/,5X,'----------  AED2 config : end  ----------',/)")
      end associate
   end subroutine

   ! The update function is called in the main loop of simstrat (in simstrat.f90) at each timestep
   ! Particle mobility (sedimentation), light absorption feedback by AED2 variables, atmospheric,
   ! pelagic and benthic fluxes, advection and diffusion are computed.

   subroutine update(self, state)
      use,intrinsic :: ieee_arithmetic

      implicit none
      class(SimstratAED2) :: self
      class(ModelState) :: state

      ! Local variables
      type(aed2_variable_t),pointer :: tvar
      real(RK) :: min_C
      integer :: v, i, split, lev, r
      real(RK), dimension(self%grid%ubnd_vol) :: tmp

      ! Calculate local pressure
      self%pres(1:self%grid%ubnd_vol) = -self%grid%z_volume(1:self%grid%ubnd_vol)

      self%cc_diag = 0.
      self%cc_diag_hz = 0.

      if (self%aed2_cfg%particle_mobility) then
      !# (3) Calculate source/sink terms due to settling rising of state
      !# variables in the water column (note that settling into benthos
      !# is done in aed2_do_benthos)
         v = 0
         do i = 1,self%n_aed2_vars
            if ( aed2_get_var(i, tvar) ) then
               if ( .not. (tvar%sheet .or. tvar%diag .or. tvar%extern) ) then
               v = v + 1
               !# only for state_vars that are not sheet
                  if ( .not. ieee_is_nan(tvar%mobility) ) then
                     self%ws(:, v) = tvar%mobility
                     min_C = tvar%minimum
                     call Mobility(self, state, min_C, self%ws(:, v), self%cc(:, v))
                  end if
               end if
            end if
         end do
      end if

      call check_states(self)

      do split=1, self%aed2_cfg%split_factor

         call absorption_updateAED2(self, state)

         !# Fudge
         self%nir(:) = (self%par(:)/0.45) * 0.51
         self%uva(:) = (self%par(:)/0.45) * 0.035
         self%uvb(:) = (self%par(:)/0.45) * 0.005

         call calculate_fluxes(self, state)

         ! Update the water column layers using the biochemical reaction of AED2
         do v = 1, self%n_vars
            do lev = 1, self%grid%nz_occupied
               self%cc(lev, v) = self%cc(lev, v) + state%dt/self%aed2_cfg%split_factor*self%flux_pel(lev, v)
            end do
         end do

!       ! Now update benthic variables, depending on whether zones are simulated
!       IF ( benthic_mode .GT. 1 ) THEN
!          ! Loop through benthic state variables to update their mass
!          DO v = n_vars+1, n_vars+n_vars_ben
!             ! Loop through each sediment zone
!             DO lev = 1, n_zones
!                ! Update the main cc_sed data array with the
!                z_cc(lev, v) = z_cc(lev, v)+ dt_eff*flux_zone(lev, v)
!             ENDDO
!          ENDDO
!       ELSE
!          DO v = n_vars+1, n_vars+n_vars_ben
!             cc(1, v) = cc(1, v) + dt_eff*flux_ben(v)
!          ENDDO
!       end if

!       ! If simulating sediment zones, distribute cc-sed benthic properties back
!       !  into main cc array, mainly for plotting
!       IF ( benthic_mode .GT. 1 ) CALL copy_from_zone(cc, cc_diag, cc_diag_hz, wlev)
      end do
         ! Update in-/outflow of AED2 variables (to be used in following advection step in the main loop)
         if (self%there_is_inflow) then
            if (self%plunging_inflow) then
               call lateral_rho_update_AED2(self, state)
            else
               call lateral_update_AED2(self, state)
            end if
         end if


         ! Diffusive transport of AED2 variables
         do v=1, self%n_vars
            call diffusion_AED2(self, state, v)
         end do

   end subroutine

   subroutine calculate_fluxes(self, state)
      !-------------------------------------------------------------------------------
      ! Checks the current values of all state variables and repairs these
      !-------------------------------------------------------------------------------
      use,intrinsic :: ieee_arithmetic

      ! Arguments
      class(SimstratAED2), intent(inout) :: self
      class(ModelState), intent(in) :: state

      ! Local variables
      integer :: lev,zon,v_start,v_end,av,sv,sd
      real(RK) :: scale
      real(RK), dimension(self%grid%nz_occupied, self%n_vars)    :: flux_pel_pre
      real(RK), dimension(self%aed2_cfg%n_zones, self%n_vars) :: flux_pel_z
      logical :: splitZone
      type(aed2_variable_t),pointer :: tvar
      !-------------------------------------------------------------------------------
      ! Begin
      self%flux_pel = zero_
      self%flux_atm = zero_
      self%flux_ben = zero_

      !# Start with calculating all flux terms for rhs in mass/m3/s
      !# Includes (1) benthic flux, (2) surface exchange and (3) water column kinetics
      !# as calculated by glm


      !# (1) BENTHIC FLUXES
      if ( self%aed2_cfg%benthic_mode .gt. 1 ) then
   !          !# Multiple static sediment zones are simulated, and therfore overlying
   !          !# water conditions need to be aggregated from multiple cells/layers, and output flux
   !          !# needs disaggregating from each zone back to the overlying cells/layers

   !          do zon=1,self%aed2_cfg%n_zones
   !             !# Reinitialise flux_ben to be repopulated for this zone
   !             flux_ben = zero_
   !             flux_pel_pre = zero_

   !             !# If multiple benthic zones, we must update the benthic variable pointer for the new zone
   !             if ( self%zone_var .ge. 1 ) then
   !                column_sed(zone_var)%cell_sheet => z_sed_zones(zon)
   !        !       !MH WE NEED A COLUMN TO CC VAR MAP FOR BENTHIC GUYS
   !                !CAB Yes, a map (or 2 maps) would be better, but QnD since this all needs reworking
   !                sv = 0 ; sd = 0
   !                do av=1,self%n_aed2_vars
   !                   if ( .not.  aed2_get_var(av, tvar) ) stop "Error getting variable info"
   !                   if ( .not. tvar%extern .and. tvar%sheet ) then
   !                      if ( tvar%diag ) then
   !                         sd = sd + 1
   !                         column(av)%cell_sheet => z_diag_hz(zon, sd)
   !                      else
   !                         sv = sv + 1
   !                         column(av)%cell_sheet => z_cc(zon, self%n_vars + sv)
   !                      end if
   !                   end if
   !                end do
   !                !print*,"Calling ben for zone ",zone_var,zon,z_sed_zones(zon)
   !             end if
   !             if ( self%aed2_cfg%benthic_mode .eq. 3 ) then
   !                !# Zone is able to operated on by riparian and dry methods
   !                call aed2_calculate_riparian(column_sed, zon, z_pc_wet(zon))
   !                if (z_pc_wet(zon) .eq. 0. ) call aed2_calculate_dry(column_sed, zon)
   !             end if
   !             !# Calculate temporal derivatives due to benthic processes.
   !             !# They are stored in flux_ben (benthic vars) and flux_pel (water vars)
   !             flux_pel_pre = flux_pel

   !    !        print*,"Calling ben for zone ",zone_var,zon,z_sed_zones(zon)
   !             call aed2_calculate_benthic(column_sed, zon)

   !             !# Record benthic fluxes in the zone array
   !             flux_zon(zon, :) = flux_ben(:)

   !             !# Now we have to find out the water column flux that occured and
   !             !# disaggregate it to relevant layers
   !             flux_pel_z(zon,:) = flux_pel(zon,:)-flux_pel_pre(zon,:)
   !          end do

   !          !# Disaggregation of zone induced fluxes to overlying layers
   !          v_start = 1 ; v_end = self%n_vars
   !          zon = self%aed2_cfg%n_zones
   !          do lev=self%grid%nz_occupied,1,-1
   !            if ( zon .ne. 1 ) then
   !              splitZone = zz(lev-1) < zone_heights(zon-1)
   !            else
   !              splitZone = .FALSE.
   !            end if

   !            if (splitZone) then
   !              scale = (zone_heights(zon-1) - zz(lev-1)) / (zz(lev) - zz(lev-1))
   !              flux_pel(lev,v_start:v_end) = flux_pel_z(zon,v_start:v_end) * scale

   !              zon = zon - 1

   !              flux_pel(lev,v_start:v_end) = flux_pel(lev,v_start:v_end) + &
   !                                            flux_pel_z(zon,v_start:v_end) * (1.0 - scale)
   !            else
   !              flux_pel(lev,v_start:v_end) = flux_pel_z(zon,v_start:v_end)
   !            end if
   !          end do
   !          !# Limit flux out of bottom waters to concentration of that layer
   !          !# i.e. don't flux out more than is there & distribute
   !          !# bottom flux into pelagic over bottom box (i.e., divide by layer height).
   !          !# scaled to proportion of area that is "bottom"
   !          do lev=1,self%grid%nz_occupied
   !             if(lev>1)flux_pel(lev, :) = flux_pel(lev, :) * (self%grid%Az_vol(lev) - self%grid%Az_vol(lev - 1))/self%grid%Az_vol(lev)
   !             flux_pel(lev, :) = max(-1.0 * self%cc(lev, :), flux_pel(lev, :)/self%grid%h(lev))
   !          end do
      else
         !# Sediment zones are not simulated and therefore just operate on the bottom-most
         !# GLM layer as the "benthos". If benthic_mode=1 then benthic fluxes will also be
         !# applied on flanks of the remaining layers, but note this is not suitable for
         !# model configurations where mass balance of benthic variables is required.

         !# Calculate temporal derivatives due to exchanges at the sediment/water interface
         !if ( self%zone_var .GE. 1 ) column(self%zone_var)%cell_sheet => z_sed_zones(1)
         call aed2_calculate_benthic(self%column, 1)

         !# Limit flux out of bottom layers to concentration of that layer
         !# i.e. don't flux out more than is there
         !# & distribute bottom flux into pelagic over bottom box (i.e., divide by layer height).
         self%flux_pel(1, :) = max(-1.0 * self%cc(1, :), self%flux_pel(1, :)/self%grid%h(1))

         if ( self%aed2_cfg%benthic_mode .EQ. 1 ) then
            do lev=2,self%grid%nz_occupied
               !# Calculate temporal derivatives due to benthic fluxes.
               call aed2_calculate_benthic(self%column, lev)

               !# Limit flux out of bottom layers to concentration of that layer
               !# i.e. don't flux out more than is there
               !# & distribute bottom flux into pelagic over bottom box (i.e., divide by layer height).
               !# scaled to proportion of area that is "bottom"
               self%flux_pel(lev, :) = max(-1.0 * self%cc(lev, :), self%flux_pel(lev, :)/self%grid%h(lev))
               self%flux_pel(lev, :) = self%flux_pel(lev, :) * (self%grid%Az_vol(lev) - self%grid%Az_vol(lev - 1))/self%grid%Az_vol(lev)
            end do
         end if
      end if

      !# (2) SURFACE FLUXES
      !# Calculate temporal derivatives due to air-water exchange.
      if (.not. (state%total_ice_h > 0)) then !# no surface exchange under ice cover
         call aed2_calculate_surface(self%column, self%grid%nz_occupied)

         !# Distribute the fluxes into pelagic surface layer
         self%flux_pel(self%grid%nz_occupied, :) = self%flux_pel(self%grid%nz_occupied, :) + self%flux_atm(:)/self%grid%h(self%grid%nz_occupied)
      end if

      !# (3) WATER COLUMN KINETICS
      !# Add pelagic sink and soustatuse terms for all depth levels.
      do lev=1,self%grid%nz_occupied
         call aed2_calculate(self%column, lev)
      end do
   end subroutine calculate_fluxes


   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Copy of diffusion algorithm used for Simstrat state variables

   subroutine diffusion_AED2(self, state, var_index)
      implicit none

      ! Arguments
      class(SimstratAED2) :: self
      class(ModelState) :: state
      integer :: var_index

      ! Local variables
      real(RK), dimension(self%grid%ubnd_vol) :: boundaries, sources, lower_diag, main_diag, upper_diag, rhs

      boundaries = 0.
      sources = 0.

      call euleri_create_LES_MFQ_AED2(self, state%AED2_state(:,var_index), state%num, sources, boundaries, lower_diag, main_diag, upper_diag, rhs, state%dt)
      call solve_tridiag_thomas(lower_diag, main_diag, upper_diag, rhs, state%AED2_state(:,var_index), self%grid%ubnd_vol)

   end subroutine


   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ! Copy of disretization of Simstrat mean quantities

   subroutine euleri_create_LES_MFQ_AED2(self, var, nu, sources, boundaries, lower_diag, main_diag, upper_diag, rhs, dt)
      class(SimstratAED2), intent(inout) :: self
      real(RK), dimension(:), intent(inout) :: var, sources, boundaries, lower_diag, upper_diag, main_diag, rhs, nu
      real(RK), intent(inout) :: dt
      integer :: n

      n=self%grid%ubnd_vol

      ! Build diagonals
      upper_diag(1) = 0.0_RK
      upper_diag(2:n) = dt*nu(2:n)*self%grid%AreaFactor_1(2:n)
      lower_diag(1:n - 1) = dt*nu(2:n)*self%grid%AreaFactor_2(1:n-1)
      lower_diag(n) = 0.0_RK
      main_diag(1:n) = 1.0_RK - upper_diag(1:n) - lower_diag(1:n) + boundaries(1:n)*dt

      ! Calculate RHS
      ! A*phi^{n+1} = phi^{n}+dt*S^{n}
      rhs(1:n) = var(1:n) + dt*sources(1:n)
   end subroutine



   subroutine lateral_update_AED2(self, state)
      implicit none
      class(SimstratAED2) :: self
      class(ModelState) :: state

      ! Local Declarations
      real(RK) :: dummy

      integer :: i, j, n, status
      integer :: fnum(1:32) ! File number
      character(len=100) :: fname(1:32)
      type(aed2_variable_t),pointer :: tvar

      associate (datum => state%datum, &
                 idx => state%model_step_counter, &
                 grid => self%grid, &
                 ubnd_vol => self%grid%ubnd_vol, &
                 ubnd_fce => self%grid%ubnd_fce)

         n = self%n_vars ! Only pelagic variables of AED2
         ! FB 2016: Major revision to include surface inflow
         do i = 1, self%n_vars ! Do this for all AED2 vars
            fname(i) = trim(self%aed2_cfg%path_aed2_inflow)//trim(self%names(i))//'_inflow.dat'
            fnum(i) = i + 60  ! Should find a better way to manage unit numbers
            if (idx==0) then ! First iteration
               if (i==1) then ! First variable
                  ! Allocate arrays for first iteration of first variable
                  allocate (self%z_Inp_AED2(1:n, 1:state%nz_input)) ! Input depths
                  allocate (self%Inp_read_start_AED2(1:n, 1:state%nz_input)) ! Raw input read
                  allocate (self%Inp_read_end_AED2(1:n, 1:state%nz_input)) ! Raw input read
                  allocate (self%Q_read_start_AED2(1:n, 1:state%nz_input)) ! Integrated input
                  allocate (self%Q_read_end_AED2(1:n, 1:state%nz_input)) ! Integrated input           
                  allocate (self%Qs_read_start_AED2(1:n, 1:state%nz_input))  ! Integrated surface input
                  allocate (self%Qs_read_end_AED2(1:n, 1:state%nz_input))  ! Integrated surface input
                  allocate (self%Q_start_AED2(1:n, 1:grid%nz_grid+1)) ! Input interpolated on grid
                  allocate (self%Q_end_AED2(1:n, 1:grid%nz_grid+1)) ! Input interpolated on grid
                  allocate (self%Qs_start_AED2(1:n, 1:grid%nz_grid+1)) ! Surface input interpolated on grid
                  allocate (self%Qs_end_AED2(1:n, 1:grid%nz_grid+1)) ! Surface input interpolated on grid
                  allocate (self%Q_inp_AED2(1:n, 1:grid%nz_grid+1))
                  allocate (self%tb_start(n), self%tb_end(n), self%eof(n), self%nval(n), self%nval_deep(n), self%nval_surface(n))
               end if

               ! Default values
               self%Q_start_AED2(i,:) = 0.0_RK
               self%Q_end_AED2(i,:) = 0.0_RK
               self%Qs_start_AED2(i, :) = 0.0_RK
               self%Qs_end_AED2(i, :) = 0.0_RK

               ! Open file and start to read
               open(fnum(i), action='read', iostat=status,file=fname(i))
               if (status .ne. 0) then
                  call error('File '//fname(i)//' not found.')
                  stop
               else
                  write(6,*) 'Reading ', fname(i)
               end if

               self%eof(i) = 0
               read (fnum(i), *, end=9) ! Skip first row: description of columns

               if (state%has_surface_input_AED2) then
                ! Read number of deep and surface inflows
                read (fnum(i), *, end=9) self%nval_deep(i), self%nval_surface(i)
                ! Total number of values to read
                self%nval(i) = self%nval_deep(i) + self%nval_surface(i)
              else
                read (fnum(i), *, end=9) self%nval_deep(i)
                ! Total number of values to read
                self%nval(i) = self%nval_deep(i)
              end if

               ! Read input depths
               read (fnum(i), *, end=9) dummy, (self%z_Inp_AED2(i, j), j=1, self%nval(i))

               ! Convert input depths
               self%z_Inp_AED2(i, 1:self%nval_deep(i)) = grid%z_zero + self%z_Inp_AED2(i, 1:self%nval_deep(i))

               if (state%has_surface_input_AED2) then
                ! Convert surface input depths
                self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)) = grid%lake_level + self%z_Inp_AED2(i, self%nval_deep(i) + 1 :self%nval(i))
              end if

               ! Read first input line
               read (fnum(i), *, end=9) self%tb_start(i), (self%Inp_read_start_AED2(i, j), j=1, self%nval(i))

              if (state%has_deep_input_AED2) then
                ! Cumulative integration of input
                call Integrate(self%z_Inp_AED2(i, :), self%Inp_read_start_AED2(i, :), self%Q_read_start_AED2(i, :), self%nval_deep(i))
                ! Interpolation on face grid
                call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, :), self%Q_read_start_AED2(i, :), self%nval_deep(i), self%Q_start_AED2(i, :))
              end if

               ! If there is surface input, integrate and interpolate
               if (state%has_surface_input_AED2) then
                  call Integrate(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Inp_read_start_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_start_AED2(i, :), self%nval_surface(i))
                  call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_start_AED2(i, :), self%nval_surface(i), self%Qs_start_AED2(i, :))
               end if


               ! Read second line and treatment of deep inflow
               read (fnum(i), *, end=7) self%tb_end(i), (self%Inp_read_end_AED2(i, j), j=1, self%nval(i))

              if (state%has_deep_input_AED2) then
                call Integrate(self%z_Inp_AED2(i, :), self%Inp_read_end_AED2(i, :), self%Q_read_end_AED2(i, :), self%nval_deep(i))
                call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, :), self%Q_read_end_AED2(i, :), self%nval_deep(i), self%Q_end_AED2(i, :))
              end if
               ! If there is surface input, integrate and interpolate
               if (state%has_surface_input_AED2) then
                   call Integrate(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Inp_read_end_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_end_AED2(i, :), self%nval_surface(i))
                   call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_end_AED2(i, :), self%nval_surface(i), self%Qs_end_AED2(i, :))
                end if

               write(6,*) '[OK] ','Input file successfully read: ',fname(i)
            end if ! idx==1



            ! If lake level changes and if there is surface inflow, adjust inflow depth to keep them at the surface
            if ((.not. grid%lake_level == grid%lake_level_old) .and. (state%has_surface_input_AED2)) then

              ! Readjust surface input depths
              self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)) = self%z_Inp_AED2(i, self%nval_deep(i) + 1 :self%nval(i)) - grid%lake_level_old + grid%lake_level

              ! Adjust surface inflow to new lake level        
              call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_start_AED2(i, :), self%nval_surface(i), self%Qs_start_AED2(i, :))
              call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_end_AED2(i, :), self%nval_surface(i), self%Qs_end_AED2(i, :))               

            end if ! end if not lake_level...



            ! Temporal treatment of inflow
            if ((datum <= self%tb_start(i)) .or. (self%eof(i) == 1)) then ! if datum before first date or end of file reached
               goto 8
            else
               do while (.not. ((datum >= self%tb_start(i)) .and. (datum <= self%tb_end(i)))) ! Do until datum between dates
                  self%tb_start(i) = self%tb_end(i) ! Move one step in time
                  self%Q_start_AED2(i, :) = self%Q_end_AED2(i, :)
                  self%Qs_start_AED2(i, :) = self%Qs_end_AED2(i, :)
                  self%Qs_read_start_AED2(i, :) = self%Qs_read_end_AED2(i, :)

                  read (fnum(i), *, end=7) self%tb_end(i), (self%Inp_read_end_AED2(i, j), j=1, self%nval(i))

                  if (state%has_deep_input_AED2) then
                    call Integrate(self%z_Inp_AED2(i, :), self%Inp_read_end_AED2(i, :), self%Q_read_end_AED2(i, :), self%nval_deep(i))
                    call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, :), self%Q_read_end_AED2(i, :), self%nval_deep(i), self%Q_end_AED2(i, :))
                  end if

                  if (state%has_surface_input_AED2) then
                     call Integrate(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Inp_read_end_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_end_AED2(i, :), self%nval_surface(i))
                     call grid%interpolate_to_face_from_second(self%z_Inp_AED2(i, self%nval_deep(i) + 1:self%nval(i)), self%Qs_read_end_AED2(i, :), self%nval_surface(i), self%Qs_end_AED2(i, :))
                  end if
               end do ! end do while
            end if

            ! Linearly interpolate value at correct datum (Q_inp_AED2 is on face grid)
            do j = 1, ubnd_fce
               self%Q_inp_AED2(i,j) = (self%Q_start_AED2(i,j) + self%Qs_start_AED2(i,j)) + (datum-self%tb_start(i)) &
               * (self%Q_end_AED2(i,j) + self%Qs_end_AED2(i,j) - self%Q_start_AED2(i,j) - self%Qs_start_AED2(i,j))/(self%tb_end(i)-self%tb_start(i))
            end do
            goto 11

            ! If end of file reached, set to closest available value
 7          self%eof(i) = 1
 8          self%Q_inp_AED2(i,1:ubnd_fce) = self%Q_start_AED2(i,1:ubnd_fce) + self%Qs_start_AED2(i,1:ubnd_fce)
            goto 11

            ! If no data available
 9          write(6,*) '[WARNING] ','No data found in ',trim(fname(i)),' inflow file. Check number of depths. Values set to zero.'
            self%eof(i) = 1
            self%Q_inp_AED2(i, 1:ubnd_fce) = 0.0_RK
            self%Q_start_AED2(i, 1:ubnd_fce) = 0.0_RK
            self%Qs_start_AED2(i, 1:ubnd_fce) = 0.0_RK
            11        continue

         end do ! end do i

         ! The final AED2_inflow is located on the volume grid
         do i = 1, n
            do j = 1, ubnd_vol
               state%AED2_inflow(j, i) = self%Q_inp_AED2(i, j + 1) - self%Q_inp_AED2(i, j)
            end do
               !state%AED2_inflow(ubnd_vol + 1,ubnd_vol + 1) = 0
         end do

      end associate
   end subroutine

   subroutine lateral_rho_update_AED2(self, state)
      class(SimstratAED2) :: self
      class(ModelState) :: state

      ! Local Declarations
      real(RK) :: Inp(1:self%n_vars,1:state%nz_input)
      real(RK) :: dummy
     
      integer :: i, j, k, i1, i2, n, status
      integer :: fnum(1:32) ! File number
      character(len=48) :: fname(1:32)
      type(aed2_variable_t),pointer :: tvar

      associate (datum => state%datum, &
                 idx => state%model_step_counter, &
                 grid => self%grid, &
                 ubnd_vol => self%grid%ubnd_vol, &
                 ubnd_fce => self%grid%ubnd_fce)

         n = self%n_vars   ! Only pelagic AED2 variables
         ! FB 2016: Major revision to include surface inflow
         do i = 1, self%n_vars ! Do this for all AED2 vars
            fname(i) = trim(self%aed2_cfg%path_aed2_inflow)//trim(self%names(i))//'_inflow.dat'
            fnum(i) = i + 60  ! Should find a better way to manage unit numbers
            if (idx==0) then ! First iteration
               if (i==1) then ! First variable
                  ! Allocate arrays for first iteration of first variable
                  allocate (self%z_Inp_AED2(1:n, 1:state%nz_input)) ! Input depths
                  allocate (self%Inp_read_start_AED2(1:n, 1:state%nz_input)) ! Raw input read
                  allocate (self%Inp_read_end_AED2(1:n, 1:state%nz_input)) ! Raw input read
                  allocate (self%Q_inp_AED2(1:n, 1:grid%nz_grid+1))
                  allocate (self%tb_start(n), self%tb_end(n), self%eof(n), self%nval(n), self%nval_deep(n), self%nval_surface(n))
               end if

               ! Open file and start to read
               open(fnum(i), action='read', iostat=status,file=fname(i))
               if (status .ne. 0) then
                  call error('File '//fname(i)//' not found.')
                  stop
               else
                  write(6,*) 'Reading ', fname(i)
               end if

               self%eof(i) = 0
               read (fnum(i), *, end=9) ! Skip first row: description of columns

               read (fnum(i), *, end=9) self%nval_deep(i)
               ! Total number of values to read
               self%nval(i) = self%nval_deep(i)

               ! Read input depths
               read (fnum(i), *, end=9) dummy, (self%z_Inp_AED2(i, j), j=1, self%nval(i))

               ! Convert input depths
               self%z_Inp_AED2(i, 1:self%nval_deep(i)) = grid%z_zero + self%z_Inp_AED2(i, 1:self%nval_deep(i))

               ! Read first input line
               read (fnum(i), *, end=9) self%tb_start(i), (self%Inp_read_start_AED2(i, j), j=1, self%nval(i))

               ! Read second line and treatment of deep inflow
               read (fnum(i), *, end=7) self%tb_end(i), (self%Inp_read_end_AED2(i, j), j=1, self%nval(i))

               write(6,*) '[OK] ','Input file successfully read: ',fname(i)
            end if ! idx==1

            if ((datum<=self%tb_start(i)).or.(self%eof(i)==1)) then    ! if datum before first date or end of file reached
               goto 8
            else
               do while (.not.((datum>=self%tb_start(i)).and.(datum<=self%tb_end(i)))) ! do until datum between dates
                  self%tb_start(i) = self%tb_end(i)             ! move one step in time
                  self%Inp_read_start_AED2(i,:) = self%Inp_read_end_AED2(i,:)

                  ! Read next line
                  read(fnum(i),*,end=7) self%tb_end(i),(self%Inp_read_end_AED2(i,j),j=1,self%nval(i))
               end do

               !Linearly interpolate value at correct datum
               Inp(i,1:self%nval(i)) = self%Inp_read_start_AED2(i,1:self%nval(i)) +&
                      (datum-self%tb_start(i)) * (self%Inp_read_end_AED2(i,1:self%nval(i))-self%Inp_read_start_AED2(i,1:self%nval(i)))/(self%tb_end(i)-self%tb_start(i))
            end if
            goto 11

7           self%eof(i) = 1
8           Inp(i,:) = self%Inp_read_start_AED2(i,:) ! Set to closest available value
            goto 11

9           write(6,*) '[WARNING] ','No data found in ',trim(fname(i)),' file. Check number of depths. Values set to zero.'
            self%eof(i) = 1
            Inp(i,1:self%nval(i)) = 0.0_RK
            self%Inp_read_start_AED2(i,1) = 0.0_RK

11        continue
         end do

         ! Plunging algorithm by Adrien, not used for the first timestep as state%Q_plunging is determined later
         if (idx>1) then
            state%AED2_inflow = 0.0_RK

            do j = 1,self%nval_deep(1)
               do i=1,ubnd_vol
                  state%AED2_inflow(i,1:n) = state%AED2_inflow(i,1:n) + Inp(1:n,j)*state%Q_plunging(i,j)
               end do
            end do
         end if
      end associate
   end subroutine

end module simstrat_aed2