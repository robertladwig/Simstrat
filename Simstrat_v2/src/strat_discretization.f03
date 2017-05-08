module strat_discretization
  use strat_kinds
  use strat_simdata
  use strat_grid

  implicit none
  private

  type, abstract, public :: Discretization
    class(StaggeredGrid),pointer :: grid
  contains
    procedure , pass(self), public :: init => generic_init
    procedure(generic_create_LES), deferred, pass(self), public ::create_LES
  end type

  type, extends(Discretization), public :: EulerIDiscretization
  contains
    procedure, pass, public :: create_LES => euleri_create_LES
  end type

  contains
    subroutine generic_init(self, grid)
      class(Discretization), intent(inout) :: self
      type(StaggeredGrid), target :: grid

      self%grid => grid
    end subroutine

    subroutine generic_create_LES(self, var,nu,  sources, boundaries,  lower_diag,main_diag, upper_diag,  rhs, dt)
      class(Discretization), intent(inout) :: self
      real(RK), dimension(:), intent(inout) :: var,  sources, boundaries,  lower_diag, upper_diag, main_diag, rhs,nu
      real(RK), intent(inout) :: dt

    end subroutine


    subroutine euleri_create_LES(self, var, nu, sources, boundaries,  lower_diag, main_diag, upper_diag,  rhs, dt)
      class(EulerIDiscretization), intent(inout) :: self
      real(RK), dimension(:), intent(inout) :: var,  sources, boundaries, lower_diag, upper_diag, main_diag, rhs, nu
      real(RK), intent(inout) :: dt
      integer :: n
      n = size(main_diag)

      ! Build diagonals
      upper_diag(1) = 0.0_RK
      upper_diag(2:n) = dt*nu(1:n-1)*self%grid%AreaFactor_1(2:n)
      lower_diag(1:n-1) = dt*nu(1:n-1)*self%grid%AreaFactor_2(1:n-1)
      lower_diag(n) = 0.0_RK
      main_diag(1:n) = 1.0_RK - upper_diag(1:n) - lower_diag(1:n) + boundaries(1:n)*dt

      ! Calculate RHS
      ! A*phi^{n+1} = phi^{n}+dt*S^{n}
      rhs(1:n) = var(1:n) + dt * sources(1:n)
    end subroutine


end module strat_discretization
