!     +---------------------------------------------------------------+
!     |  Data structure definitions for simulation data
!     +---------------------------------------------------------------+

module strat_simdata
   use strat_kinds
   use strat_grid
   use strat_consts
   use utilities
   implicit none
   private

   ! All Input files
   type, public :: InputConfig
      character(len=:), allocatable          :: MorphName
      character(len=:), allocatable          :: InitName
      character(len=:), allocatable          :: ForcingName
      character(len=:), allocatable          :: AbsorpName
      character(len=:), allocatable          :: GridName
      character(len=:), allocatable          :: QinpName
      character(len=:), allocatable          :: QoutName
      character(len=:), allocatable          :: TinpName
      character(len=:), allocatable          :: SinpName
      real(RK), dimension(:), allocatable    :: read_grid_array_from_json
      real(RK) :: read_grid_value_from_json
      integer :: grid_input_type
   end type

   ! Definition of a variable to log
   type, public :: LogVariable
      character(len=:), allocatable :: name
      real(RK), dimension(:), pointer :: values
      real(RK), pointer :: values_surf 
      logical :: volume_grid, face_grid
   end type

   ! Logging configuration
   type, public :: OutputConfig
      character(len=:), allocatable :: PathOut
      character(len=:), allocatable :: zoutName
      character(len=:), allocatable :: toutName
      character(len=:), allocatable :: output_depth_reference
      real(RK), dimension(:), allocatable :: zout, zout_read
      real(RK), dimension(:), allocatable :: tout
      real(RK), dimension(:), allocatable :: n_timesteps_between_tout
      real(RK), dimension(:), allocatable :: adjusted_timestep
      logical :: write_to_file
      class(LogVariable), dimension(:), allocatable :: output_vars

      integer :: output_time_type, output_depth_type, thinning_interval
      real(RK) :: depth_interval, thinning_interval_read ! thinning_interval_read is a real to make sure that also values
      ! like 72.0 can be read (which are interpreted as a double)
   end type

   ! Simulation configuration
   type, public :: SimConfig
      integer :: timestep
      integer :: start_year
      real(RK) :: start_datum
      real(RK) :: end_datum
      integer :: disp_simulation
   end type

   ! Model configuration (read from file)
   type, public :: ModelConfig
      integer :: max_length_input_data
      logical :: couple_aed2
      integer :: turbulence_model
      logical :: split_a_seiche
      integer :: stability_func
      integer :: flux_condition
      integer :: forcing_mode
      logical :: user_defined_water_albedo
      logical :: use_filtered_wind
      integer :: seiche_normalization
      integer :: wind_drag_model
      integer :: inflow_placement
      integer :: pressure_gradients
      logical :: salinity_transport
      integer :: ice_model
      integer :: snow_model
   end type

   ! Model params (read from file)
   type, public :: ModelParam
      real(RK) :: Lat
      real(RK) :: p_air
      real(RK) :: a_seiche
      real(RK) :: a_seiche_w
      real(RK) :: strat_sumr
      real(RK) :: q_NN
      real(RK) :: f_wind
      real(RK) :: C10_constant
      real(RK) :: CD
      real(RK) :: fgeo
      real(RK) :: k_min
      real(RK) :: p_sw
      real(RK) :: p_lw
      real(RK) :: p_windf
      real(RK) :: beta_sol
      real(RK) :: wat_albedo
      real(RK) :: p_albedo
      real(RK) :: freez_temp
      real(RK) :: snow_temp
   end type

   ! Model state (this is actually the simulation data!!!)
   type, public :: ModelState
      ! Iteration variables
      integer :: i, j, output_counter, model_step_counter
      real(RK) :: datum, dt
      logical :: first_timestep = .true.

      ! Variables located on z_cent grid
      ! Note that for these variables the value at 0 z.b. U(0) is not used
      real(RK), dimension(:), allocatable :: U, V ! Water velocities [m/s]
      real(RK), dimension(:), allocatable :: T, S ! Temperature [°C], Salinity [‰]
      real(RK), dimension(:), allocatable :: dS ! Source/sink for salinity
      real(RK), dimension(:, :), allocatable :: Q_inp ! Horizontal inflow [m^3/s]
      real(RK), dimension(:), allocatable :: rho ! Water density [kg/m^3]

      ! Variables located on z_upp grid
      real(RK), dimension(:), allocatable :: k, ko ! Turbulent kinetic energy (TKE) [J/kg]
      real(RK), dimension(:), allocatable :: avh
      real(RK), dimension(:), allocatable :: eps ! TKE dissipation rate [W/kg]
      real(RK), dimension(:), allocatable :: num, nuh ! Turbulent viscosity (momentum) and diffusivity (temperature)
      real(RK), dimension(:), allocatable :: P, B ! Shear stress production [W/kg], buoyancy production [W/kg]
      real(RK), dimension(:), allocatable :: NN ! Brunt-Väisälä frequency [s-2]
      real(RK), dimension(:), allocatable :: cmue1, cmue2 ! Model constants
      real(RK), dimension(:), allocatable :: P_Seiche ! Production of TKE [W/kg] and seiche energy [J]
      real(RK) :: E_Seiche
      real(RK) :: gamma ! Proportionality constant for loss of seiche energy

      real(RK), dimension(:), allocatable :: absorb ! Absorption coeff [m-1]
      real(RK) :: u10, v10, uv10, Wf ! Wind speeds, wind factor
      real(RK) :: u_taub, drag, u_taus ! Drag
      real(RK) :: tx, ty ! Shear stress
      real(RK) :: C10 ! Wind drag coefficient
      real(RK) :: SST, heat, heat_snow, heat_ice, heat_snowice! Sea surface temperature and heat flux
      real(RK) :: T_atm ! Air temp at surface
      real(RK), dimension(:), allocatable :: rad ! Solar radiation (in water)
      real(RK), dimension(:), allocatable :: Q_vert ! Vertical exchange between boxes
      real(RK), dimension(9,12) :: albedo_data  ! Experimental monthly albedo data for determination of current water albedo
      real(RK) :: albedo_water   ! Current water albedo
      integer :: lat_number ! Latitude band (used for determination of albedo)

      ! Snow and Ice
      real(RK), allocatable :: snow_h ! Snow layer height [m]
      real(RK), allocatable :: total_ice_h ! Total ice layer height [m]
      real(RK), allocatable :: black_ice_h ! Black ice layer height [m]
      real(RK), allocatable :: white_ice_h ! Snowice layer height [m]
      real(RK) :: snow_dens ! Snow density [kg m-3]
      real(RK) :: ice_temp ! Ice temperature [°C]
      real(RK) :: precip ! Precipiation in water eqvivalent hight [m]

      !For saving heatflux
      real(RK), allocatable :: ha ! Incoming long wave [W m-2]
      real(RK), allocatable :: hw ! Outgoing long wave [W m-2]
      real(RK), allocatable :: hk ! Sensible flux [W m-2]
      real(RK), allocatable :: hv ! Latent heat [W m-2]
      real(RK), allocatable :: rad0 !  Solar radiation at surface  [W m-2]

      real(RK) :: cde, cm0
      real(RK) ::  fsed
      real(RK), dimension(:), allocatable     :: fgeo_add
      logical :: has_advection
      logical, dimension(1:4) :: has_surface_input, has_deep_input
      integer :: nz_input

   contains
      procedure, pass :: init => model_state_init
      procedure, pass :: save => save_model_state
      procedure, pass :: load => load_model_state
   end type

   ! Structure that encapsulates a full program state
   type, public :: SimulationData
      type(InputConfig), public   :: input_cfg
      type(OutputConfig), public  :: output_cfg
      type(SimConfig), public     :: sim_cfg
      type(ModelConfig), public   :: model_cfg
      type(ModelParam), public    :: model_param
      type(ModelState), public    :: model
      type(StaggeredGrid), public :: grid
   contains
      procedure, pass :: init => simulation_data_init
   end type

contains
   subroutine simulation_data_init(self, state_size)
      class(SimulationData), intent(inout) :: self
      integer, intent(in) :: state_size
      ! Init model data structures
      call self%model%init(state_size)

   end subroutine

   ! Allocates all arrays of the model state in the correct size
   subroutine model_state_init(self, state_size)
      class(ModelState), intent(inout) :: self
      integer, intent(in) :: state_size

      ! Values on volume grid
      ! Important: Size is smaller than vars on upper grid.
      !            https://en.wikipedia.org/wiki/Off-by-one_error#Fencepost_error ;-)
      allocate (self%U(state_size))
      allocate (self%V(state_size))
      allocate (self%T(state_size))
      allocate (self%S(state_size))
      allocate (self%dS(state_size))
      allocate (self%Q_inp(1:4, state_size + 1))
      allocate (self%rho(state_size))
      allocate (self%avh(state_size))

      ! Values on z_upp grid
      allocate (self%k(state_size + 1))
      allocate (self%ko(state_size + 1))
      allocate (self%eps(state_size + 1))
      allocate (self%num(state_size + 1))
      allocate (self%nuh(state_size + 1))
      allocate (self%P(state_size + 1))
      allocate (self%B(state_size + 1))
      allocate (self%NN(state_size + 1))
      allocate (self%cmue1(state_size + 1))
      allocate (self%cmue2(state_size + 1))
      allocate (self%P_Seiche(state_size + 1))

      allocate (self%absorb(state_size + 1))
      allocate (self%rad(state_size + 1))
      allocate (self%Q_vert(state_size + 1))

      allocate (self%snow_h)
      allocate (self%total_ice_h)
      allocate (self%black_ice_h)
      allocate (self%white_ice_h)

      allocate (self%ha)
      allocate (self%hw)
      allocate (self%hk)
      allocate (self%hv)
      allocate (self%rad0)

      ! Init to zero
      self%U = 0.0_RK
      self%V = 0.0_RK
      self%T = 0.0_RK
      self%S = 0.0_RK
      self%dS = 0.0_RK
      self%Q_inp = 0.0_RK
      self%rho = 0.0_RK

      self%k = 0.0_RK
      self%ko = 0.0_RK
      self%eps = 0.0_RK
      self%num = 0.0_RK
      self%nuh = 0.0_RK
      self%P = 0.0_RK
      self%B = 0.0_RK
      self%NN = 0.0_RK
      self%cmue1 = 0.0_RK
      self%cmue2 = 0.0_RK
      self%P_Seiche = 0.0_RK
      self%E_Seiche = 0.0_RK

      self%absorb = 0.0_RK
      self%rad = 0.0_RK
      self%Q_vert = 0.0_RK

      self%snow_h = 0.0_RK
      self%total_ice_h = 0.0_RK
      self%black_ice_h = 0.0_RK
      self%white_ice_h = 0.0_RK
      self%ice_temp = 0.0_RK
      self%snow_dens = rho_s_0
      self%precip = 0.0_RK

      self%ha = 0.0_RK
      self%hw = 0.0_RK
      self%hk = 0.0_RK
      self%hv = 0.0_RK
      self%rad0 = 0.0_RK

   end subroutine

   ! save model state unformatted
   subroutine save_model_state(self, file_path)
      implicit none
      class(ModelState), intent(inout) :: self
      character(len=*), intent(in) :: file_path

      open(80, file=file_path, Form='unformatted', Action='Write')

      write(80) self%i, self%j, self%output_counter, self%model_step_counter
      write(80) self%datum, self%dt
      call save_array(80, self%U)
      call save_array(80, self%V)
      call save_array(80, self%dS)
      call save_matrix(80, self%Q_inp)
      call save_array(80, self%rho)
      call save_array(80, self%k)
      call save_array(80, self%ko)
      call save_array(80, self%avh)
      call save_array(80, self%eps)
      call save_array(80, self%num)
      call save_array(80, self%nuh)
      call save_array(80, self%P)
      call save_array(80, self%B)
      call save_array(80, self%NN)
      call save_array(80, self%cmue1)
      call save_array(80, self%cmue2)
      call save_array(80, self%P_Seiche)
      write(80) self%E_Seiche, self%gamma
      call save_array(80, self%absorb)
      write(80) self%u10, self%v10, self%uv10, self%Wf
      write(80) self%u_taub, self%drag, self%u_taus
      write(80) self%tx, self%ty
      write(80) self%C10
      write(80) self%SST, self%heat, self%heat_snow, self%heat_ice, self%heat_snowice
      write(80) self%T_atm
      call save_array(80, self%rad)
      call save_array(80, self%Q_vert)
      write(80) self%albedo_data
      write(80) self%albedo_water
      write(80) self%lat_number
      write(80) self%snow_h
      write(80) self%total_ice_h
      write(80) self%black_ice_h
      write(80) self%white_ice_h
      write(80) self%snow_dens
      write(80) self%ice_temp
      write(80) self%precip
      write(80) self%ha
      write(80) self%hw
      write(80) self%hk
      write(80) self%hv
      write(80) self%rad0
      write(80) self%cde, self%cm0
      write(80) self%fsed
      call save_array(80, self%fgeo_add)
      write(80) self%has_advection
      write(80) self%has_surface_input, self%has_deep_input
      write(80) self%nz_input

      close(80)
   end subroutine

   ! load model state unformatted
   subroutine load_model_state(self, file_path)
      implicit none
      class(ModelState), intent(inout) :: self
      character(len=*), intent(in) :: file_path

      open(81, file=file_path, Form='unformatted', Action='Read')

      read(81) self%i, self%j, self%output_counter, self%model_step_counter
      read(81) self%datum, self%dt
      self%U = read_array(81)
      self%V = read_array(81)
      self%dS = read_array(81)
      self%Q_inp = read_matrix(81)
      self%rho = read_array(81)
      self%k = read_array(81)
      self%ko = read_array(81)
      self%avh = read_array(81)
      self%eps = read_array(81)
      self%num = read_array(81)
      self%nuh = read_array(81)
      self%P = read_array(81)
      self%B = read_array(81)
      self%NN = read_array(81)
      self%cmue1 = read_array(81)
      self%cmue2 = read_array(81)
      self%P_Seiche = read_array(81)
      read(81) self%E_Seiche, self%gamma
      self%absorb = read_array(81)
      read(81) self%u10, self%v10, self%uv10, self%Wf
      read(81) self%u_taub, self%drag, self%u_taus
      read(81) self%tx, self%ty
      read(81) self%C10
      read(81) self%SST, self%heat, self%heat_snow, self%heat_ice, self%heat_snowice
      read(81) self%T_atm
      self%rad = read_array(81)
      self%Q_vert = read_array(81)
      read(81) self%albedo_data
      read(81) self%albedo_water
      read(81) self%lat_number
      read(81) self%snow_h
      read(81) self%total_ice_h
      read(81) self%black_ice_h
      read(81) self%white_ice_h
      read(81) self%snow_dens
      read(81) self%ice_temp
      read(81) self%precip
      read(81) self%ha
      read(81) self%hw
      read(81) self%hk
      read(81) self%hv
      read(81) self%rad0
      read(81) self%cde, self%cm0
      read(81) self%fsed
      self%fgeo_add = read_array(81)
      read(81) self%has_advection
      read(81) self%has_surface_input, self%has_deep_input
      read(81) self%nz_input


      close(81)
   end subroutine

end module strat_simdata
