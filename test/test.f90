program test

    use, intrinsic :: iso_fortran_env, only: &
        wp => REAL64, &
        ip => INT32, &
        stdout => OUTPUT_UNIT, &
        compiler_version, &
        compiler_options

    use type_GaussianSphericalHarmonic, only: &
        GaussianSphericalHarmonic

    ! Explicit typing only
    implicit none

    call test_shallow_water_equations()

contains


    subroutine test_shallow_water_equations()
        !
        !  Purpose:
        !
        ! Test program for GaussianSphericalHarmonic
        !
        !  Non-linear steady-state geostropic flow in a shallow water model.
        !
        !  errors should be O(10E-5) or less in single-precision, O(10E-7) or less
        !  in real (wp).
        !
        !
        !     the nonlinear shallow-water equations on the sphere are
        !     solved using a spectral method based on the spherical harmonics.
        !     the method is described in the paper:
        !
        ! [1] p. n. swarztrauber, spectral transform methods for solving
        !     the shallow-water equations on the sphere, p.n. swarztrauber,
        !     monthly weather review, vol. 124, no. 4, april 1996, pp. 730-744.
        !
        !     this program implements test case 3 (steady nonlinear rotated flow)
        !     in the paper:
        !
        ! [2] d.l. williamson, j.b. drake, j.j. hack, r. jakob, and
        !     p.n. swarztrauber, j. comp. phys., a standard test set
        !     for numerical approximations to the shallow-water
        !     equations in spherical geometry, j. comp. phys.,
        !     vol. 102, no. 1, sept. 1992, pp. 211-224.
        !
        ! definitions:
        !
        !
        !     nlat          number of latitudes
        !     nlon          number of distinct longitudes
        !     ntrunc        max wave number
        !     omega         rotation rate of earth in radians per second
        !     aa            radius of earth in meters
        !     pzero         mean height of geopotential
        !     uzero         maximum velocity
        !     alpha         tilt angle of the rotated grid
        !     ncycle        cycle number
        !     time          model time in seconds
        !     dt            time step
        !     lambda        longitude
        !     theta         colatitude
        !
        !   the second dimension of the following two dimensional arrays
        !   corresponds to the latitude index with values j=1, ..., nlat
        !   going from north to south.
        !   the second dimension is longitude with values i=1, ..., nlon
        !   where i=1 corresponds to zero longitude and j=nlon corresponds
        !   to 2pi minus 2pi/nlon.
        !
        !     u(i, j)       east longitudinal velocity component at t=time
        !     v(i, j)       latitudinal velocity component at t=time
        !     p(i, j)       +pzero = geopotential at t=time
        !
        !     divg(i, j)    divergence (d/dtheta (cos(theta) v)
        !                                          + du/dlambda)/cos(theta)
        !     vrtg(i, j)    vorticity  (d/dtheta (cos(theta) u)
        !                                          - dv/dlambda)/cos(theta)
        !
        !     uxact(i, j)   the "exact" longitudinal velocity component
        !     vxact(i, j)   the "exact" latitudinal  velocity component
        !     pxact(i, j)   the "exact" geopotential
        !
        !--------------------------------------------------------------------------------
        ! Dictionary
        !--------------------------------------------------------------------------------
        integer (ip), parameter :: NLON=128
        integer (ip), parameter :: NLAT=NLON/2 + 1
        integer (ip), parameter :: NTRUNC=42
        integer (ip), parameter :: NL = 90
        integer (ip), parameter :: NMDIM = (NTRUNC+1)*(NTRUNC+2)/2
        integer (ip)            :: MAXIMUM_NUMBER_OF_TIME_ITERATIONS
        integer (ip)            :: MPRINT
        integer (ip)            :: i, j !! Counters
        integer (ip)            :: cycle_number
        integer (ip)            :: nsav1
        integer (ip)            :: nsav2
        integer (ip)            :: n_old
        integer (ip)            :: n_now
        integer (ip)            :: n_new
        real (wp)            :: phlt(361)
        real (wp), dimension(NLON, NLAT) :: uxact
        real (wp), dimension(NLON, NLAT) :: vxact
        real (wp), dimension(NLON, NLAT) :: pxact
        real (wp), dimension(NLON, NLAT) :: u
        real (wp), dimension(NLON, NLAT) :: v
        real (wp), dimension(NLON, NLAT) :: p
        real (wp), dimension(NLON, NLAT) :: f
        real (wp), dimension(NLON, NLAT) :: coslat
        real (wp), dimension(NLON, NLAT) :: ug
        real (wp), dimension(NLON, NLAT) :: vg
        real (wp), dimension(NLON, NLAT) :: pg
        real (wp), dimension(NLON, NLAT) :: vrtg
        real (wp), dimension(NLON, NLAT) :: divg
        real (wp), dimension(NLON, NLAT) :: scrg1
        real (wp), dimension(NLON, NLAT) :: scrg2
        complex (wp), dimension(NMDIM) :: vrtnm
        complex (wp), dimension(NMDIM) ::divnm
        complex (wp), dimension(NMDIM) ::pnm
        complex (wp), dimension(NMDIM) ::scrnm
        complex (wp), dimension(NMDIM, 3) :: dvrtdtnm
        complex (wp), dimension(NMDIM, 3) ::ddivdtnm
        complex (wp), dimension(NMDIM, 3) ::dpdtnm
        complex (wp), dimension(NTRUNC+1, NLAT) :: scrm1
        complex (wp), dimension(NTRUNC+1, NLAT) ::scrm2
        real (wp), parameter :: RADIUS_OF_EARTH_IN_METERS = 6.37122e+6_wp
        real (wp), parameter :: PI = acos( -1.0_wp )
        real (wp), parameter :: HALF_PI = 0.5_wp * PI
        real (wp), parameter :: RADIAN_UNIT = PI/180.0_wp
        real (wp), parameter :: ROTATION_RATE_OF_EARTH = 7.292e-5_wp
        real (wp), parameter :: DT = 600.0_wp
        real (wp), parameter :: TILT_ANGLE = 60.0_wp
        real (wp), parameter :: ALPHA = RADIAN_UNIT * TILT_ANGLE
        real (wp), parameter :: LONGITUDINAL_MESH = (2.0_wp * PI)/NLON
        real (wp), parameter :: LATITUDINAL_MESH = PI/(NL-1)
        real (wp), parameter :: U_ZERO = 40.0_wp
        real (wp), parameter :: P_ZERO = 2.94e+4_wp
        real (wp), parameter :: F_ZERO = 2.0_wp * ROTATION_RATE_OF_EARTH
        real (wp) :: time
        real (wp) :: lambda_hat
        real (wp) :: u_hat
        real (wp) :: theta_hat
        real (wp) :: evmax
        real (wp) :: epmax
        real (wp) :: dvmax
        real (wp) :: dpmax
        real (wp) :: model_time_in_hours
        real (wp) :: dvgm
        real (wp) :: v2max
        real (wp) :: p2max
        real (wp) :: vmax
        real (wp)                         :: pmax
        character (len=:), allocatable    :: write_format
        type (GaussianSphericalHarmonic)  :: sphere
        !--------------------------------------------------------------------------------

        write( stdout, '(A)' ) ''
        write( stdout, '(A)') ' *** Test program for TYPE(GaussianSphericalHarmonic) ***'
        write( stdout, '(A)') ''
        write( stdout, '(A)') 'Non-linear steady-state geostropic flow in a shallow water model'
        write( stdout, '(A)') ''
        write( stdout, '(A, I11)') 'Triangular trunction number  = ', NTRUNC
        write( stdout, '(A, I11)') 'Number of gaussian latitudes = ', NLAT
        write( stdout, '(A)') ''

        ! Set constants
        MAXIMUM_NUMBER_OF_TIME_ITERATIONS = nint( 864.0e+2_wp * 5.0_wp/DT, kind=ip)
        MPRINT = MAXIMUM_NUMBER_OF_TIME_ITERATIONS/10

        !     compute the derivative of the unrotated geopotential
        !     p as a function of latitude


        do i = 1, NL - 2
            associate( theta => real(i, kind=wp) * LATITUDINAL_MESH )
                u_hat = &
                    compute_initial_unrotated_longitudinal_velocity( U_ZERO, HALF_PI - theta )

                phlt(i) = &
                    cos(theta) * u_hat * ( u_hat/sin(theta) &
                    + RADIUS_OF_EARTH_IN_METERS * F_ZERO )/(NL - 1)
            end associate
        end do

        !     compute sine transform of the derivative of the geopotential
        !     for the purpose of computing the geopotential by integration
        !     see equation (3.9) in reference [1] above

        call compute_sine_transform(phlt(1:NL-2))

        !     compute the cosine coefficients of the unrotated geopotential
        !     by the formal integration of the sine series representation

        do i = 1, NL - 2
            phlt(i) = -phlt(i)/i
        end do

        !     phlt(i) contains the coefficients in the cosine series
        !     representation of the unrotated geopotential that are used
        !     below to compute the geopotential on the rotated grid.
        !
        !     compute the initial values of  east longitudinal
        !     and latitudinal velocities u and v as well as the
        !     geopotential p and coriolis f on the rotated grid.
        !


        !  initialize sphere derived data type.

        call sphere%create( &
            NLON, NLAT, NTRUNC, RADIUS_OF_EARTH_IN_METERS)

        do j = 1, NLON
            associate( &
                gaulats => sphere%gaussian_latitudes, &
                lambda  => real(j - 1, kind=wp) * LONGITUDINAL_MESH &
                )
                associate( &
                    cos_a => cos(ALPHA), &
                    sin_a => sin(ALPHA), &
                    cos_l => cos(lambda), &
                    sin_l => sin(lambda) &
                    )
                    do i = 1, NLAT

                        !     lambda is longitude, theta is colatitude, and pi/2-theta is
                        !     latitude on the rotated grid. lhat and that are longitude
                        !     and colatitude on the unrotated grid. see text starting at
                        !     equation (3.10)
                        !
                        associate( theta => HALF_PI-asin(gaulats(i)) )
                            associate( &
                                cos_t => cos(theta), &
                                sin_t => sin(theta) &
                                )
                                associate( &
                                    sint   => cos_a*cos_t+sin_a*sin_t*cos_l, &
                                    cthclh => cos_a*sin_t*cos_l-sin_a*cos_t, &
                                    cthslh => sin_t*sin_l &
                                    )
                                    lambda_hat = atanxy(cthclh, cthslh)
                                    associate( &
                                        cos_lh => cos(lambda_hat), &
                                        sin_lh => sin(lambda_hat) &
                                        )
                                        associate( cost => cos_lh*cthclh+sin_lh*cthslh )
                                            theta_hat = atanxy(sint, cost)
                                            u_hat = compute_initial_unrotated_longitudinal_velocity(U_ZERO, HALF_PI-theta_hat)
                                            pxact(j, i) = compute_cosine_transform(theta_hat, phlt)
                                            uxact(j, i) = u_hat*(cos_a*sin_l*sin_lh+cos_l*cos_lh)
                                            vxact(j, i) = u_hat*(cos_a*cos_l*sin_lh*cos_t-cos_lh*sin_l*cos_t+sin_a*sin_lh*sin_t)
                                            f(j, i) = F_ZERO * sint
                                            coslat(j, i) = sqrt(1.0_wp - gaulats(i)**2)
                                        end associate
                                    end associate
                                end associate
                            end associate
                        end associate
                    end do
                end associate
            end associate
        end do

        vmax = 0.0_wp
        pmax = 0.0_wp
        v2max = 0.0_wp
        p2max = 0.0_wp
        do j = 1, NLAT
            do i = 1, NLON
                v2max = v2max + uxact(i, j)**2 + vxact(i, j)**2
                p2max = p2max + pxact(i, j)**2
                vmax = max(abs(uxact(i, j)), abs(vxact(i, j)), vmax)
                pmax = max(abs(pxact(i, j)), pmax)
            end do
        end do
        !
        !     initialize first time step
        !
        u = uxact
        v = vxact
        p = pxact
        ug = u*coslat
        vg = v*coslat
        pg = p

        !  compute spectral coeffs of initial vrt, div, p.

        call sphere%get_vorticity_and_divergence_from_velocities( vrtnm, divnm, ug, vg)
        call sphere%perform_spherical_harmonic_transform( p, pnm, 1)


        !==> time step loop.

        n_new = 1
        n_now = 2
        n_old = 3

        do cycle_number = 0, MAXIMUM_NUMBER_OF_TIME_ITERATIONS

            time = real(cycle_number, kind=wp)*DT

            !==> Inverse transform to get vort and phig on grid.

            call sphere%perform_spherical_harmonic_transform( pg, pnm, -1)
            call sphere%perform_spherical_harmonic_transform( vrtg, vrtnm, -1)

            !==> compute u and v on grid from spectral coeffs. of vort and div.

            call sphere%get_velocities_from_vorticity_and_divergence( vrtnm, divnm, ug, vg)

            !==> compute error statistics.

            if (mod(cycle_number, MPRINT ) == 0) then

                call sphere%perform_spherical_harmonic_transform( divg, divnm, -1)

                u = ug/coslat
                v = vg/coslat
                p = pg
                model_time_in_hours = time/3600.0_wp

                allocate( &
                    write_format, &
                    source = '(A, i10, A, f10.2/, A, f10.0, A, i10/, A, i10, '&
                    //'A, i10/, A, 1pe15.6, A, 1pe15.6, /A, 1pe15.6, A, 1pe15.6)' &
                    )
                write( stdout, '(A)' ) ''
                write( stdout, '(A)' ) ' steady nonlinear rotated flow:'
                write( stdout, fmt = write_format ) &
                    ' cycle number              ', cycle_number, &
                    ' model time in  hours      ', model_time_in_hours, &
                    ' time step in seconds      ', DT, &
                    ' number of latitudes       ', NLAT,    &
                    ' number of longitudes      ', NLON,    &
                    ' max wave number           ', NTRUNC,    &
                    ' rotation rate        ', ROTATION_RATE_OF_EARTH,   &
                    ' mean height          ', P_ZERO,     &
                    ' maximum velocity     ', U_ZERO,      &
                    ' tilt angle           ', TILT_ANGLE

                deallocate( write_format )

                dvgm = 0.0_wp
                dvmax = 0.0_wp
                dpmax = 0.0_wp
                evmax = 0.0_wp
                epmax = 0.0_wp

                do j=1, NLAT
                    do i=1, NLON
                        dvgm = &
                            max(dvgm, abs(divg(i, j)))
                        dvmax = &
                            dvmax+(u(i, j)-uxact(i, j))**2+(v(i, j)-vxact(i, j))**2
                        dpmax = &
                            dpmax+(p(i, j)-pxact(i, j))**2
                        evmax = &
                            max(evmax, abs(v(i, j)-vxact(i, j)), abs(u(i, j)-uxact(i, j)))
                        epmax = &
                            max(epmax, abs(p(i, j)-pxact(i, j)))
                    end do
                end do

                dvmax = sqrt(dvmax/v2max)
                dpmax = sqrt(dpmax/p2max)
                evmax = evmax/vmax
                epmax = epmax/pmax

                allocate( &
                    write_format, &
                    source = '(2(A, 1pe15.6)/, A, 1pe15.6)' &
                    )

                write( stdout, fmt = write_format ) &
                    ' max error in velocity', evmax, &
                    ' max error in geopot. ', epmax, &
                    ' l2 error in velocity ', dvmax, &
                    ' l2 error in geopot.  ', dpmax, &
                    ' maximum divergence   ', dvgm

                deallocate( write_format )

            end if

            !==> Compute right-hand sides of prognostic eqns.

            scrg1 = ug * ( vrtg + f )
            scrg2 = vg * ( vrtg + f )

            call sphere%perform_multiple_real_fft( scrg1, scrm1, 1)
            call sphere%perform_multiple_real_fft( scrg2, scrm2, 1)

            call sphere%get_complex_spherical_harmonic_coefficients(scrm1, scrm2, dvrtdtnm(:, n_new), -1, 1)
            call sphere%get_complex_spherical_harmonic_coefficients(scrm2, scrm1, ddivdtnm(:, n_new), 1, -1)

            scrg1 = ug * ( pg + P_ZERO )
            scrg2 = vg * ( pg + P_ZERO )

            call sphere%get_complex_spherical_harmonic_coefficients( &
                scrm1, scrm2, dpdtnm(:, n_new), -1, 1)

            scrg1 = pg + 0.5_wp * ( ( ug**2 + vg**2 ) / coslat**2 )

            call sphere%perform_spherical_harmonic_transform( scrg1, scrnm, 1)

            associate( lap => sphere%laplacian )
                ddivdtnm(:, n_new) = ddivdtnm(:, n_new) - lap * scrnm
            end associate

            !==> update vrt and div with third-order adams-bashforth.

            !==> forward euler, then 2nd-order adams-bashforth time steps to start.

            select case (cycle_number)
                case (0)
                    dvrtdtnm(:, n_now) = dvrtdtnm(:, n_new)
                    dvrtdtnm(:, n_old) = dvrtdtnm(:, n_new)
                    ddivdtnm(:, n_now) = ddivdtnm(:, n_new)
                    ddivdtnm(:, n_old) = ddivdtnm(:, n_new)
                    dpdtnm(:, n_now) = dpdtnm(:, n_new)
                    dpdtnm(:, n_old) = dpdtnm(:, n_new)
                case (1)
                    dvrtdtnm(:, n_old) = dvrtdtnm(:, n_new)
                    ddivdtnm(:, n_old) = ddivdtnm(:, n_new)
                    dpdtnm(:, n_old) = dpdtnm(:, n_new)
            end select

            vrtnm = &
                vrtnm + DT * (&
                (23.0_wp/12.0_wp) * dvrtdtnm(:, n_new) &
                - (16.0_wp/12.0_wp) * dvrtdtnm(:, n_now) &
                + (5.0_wp/12.0_wp) * dvrtdtnm(:, n_old) )

            divnm = &
                divnm + DT *( &
                (23.0_wp/12.0_wp) * ddivdtnm(:, n_new) &
                - (16.0_wp/12.0_wp) * ddivdtnm(:, n_now) &
                + (5.0_wp/12.0_wp) * ddivdtnm(:, n_old) )

            pnm = &
                pnm + DT * (&
                (23.0_wp/12.0_wp) * dpdtnm(:, n_new) &
                - (16.0_wp/12.0_wp) * dpdtnm(:, n_now) &
                + (5.0_wp/12.0_wp) * dpdtnm(:, n_old) )

            !==> switch indices

            nsav1 = n_new
            nsav2 = n_now
            n_new = n_old
            n_now = nsav1
            n_old = nsav2

        !==> end time step loop
        end do

        !==>  Release memory
        call sphere%destroy()

        ! Print compiler info
        write( stdout, '(A)' ) ''
        write( stdout, '(4A)' ) 'This file was compiled by ', &
            compiler_version(), ' using the options ', &
            compiler_options()
        write( stdout, '(A)' ) ''

    end subroutine test_shallow_water_equations


    pure function compute_initial_unrotated_longitudinal_velocity( &
        amp, thetad ) result (return_value)
        !
        !     computes the initial unrotated longitudinal velocity
        !     see section 3.3.
        !--------------------------------------------------------------------------------
        ! Dictionary: calling arguments
        !--------------------------------------------------------------------------------
        real (wp), intent (in) :: amp
        real (wp), intent (in) :: thetad
        real (wp)              :: return_value
        !--------------------------------------------------------------------------------
        ! Dictionary: local variables
        !--------------------------------------------------------------------------------
        real (wp), parameter :: ZERO = nearest(1.0_wp, 1.0_wp)-nearest(1.0_wp, -1.0_wp)
        real (wp), parameter :: PI = acos( -1.0_wp )
        real (wp)            :: x
        !--------------------------------------------------------------------------------

        associate( &
            thetab => -PI/6.0_wp, &
            thetae => PI/2.0_wp, &
            xe => 3.0e-1_wp &
            )

            x =xe*(thetad-thetab)/(thetae-thetab)

            return_value = 0.0_wp

            if(x <= ZERO .or. x >= xe) return

            associate( arg => (-1.0_wp/x) - (1.0_wp/(xe-x)) + (4.0_wp/xe) )
                return_value = amp * exp( arg )
            end associate
        end associate

    end function compute_initial_unrotated_longitudinal_velocity


    pure function atanxy( x, y ) result (return_value)
        !--------------------------------------------------------------------------------
        ! Dictionary: calling arguments
        !--------------------------------------------------------------------------------
        real (wp), intent (in) :: x
        real (wp), intent (in) :: y
        real (wp)              :: return_value
        !--------------------------------------------------------------------------------
        real (wp), parameter :: ZERO = nearest(1.0_wp, 1.0_wp)-nearest(1.0_wp, -1.0_wp)
        !--------------------------------------------------------------------------------

        ! Initialize return value
        return_value = 0.0_wp

        if ( x == ZERO .and. y == ZERO ) return

        return_value = atan2( y, x )

    end function atanxy


    subroutine compute_sine_transform( x )
        !--------------------------------------------------------------------------------
        ! Dictionary: calling arguments
        !--------------------------------------------------------------------------------
        real (wp), intent (in out) :: x(:)
        !--------------------------------------------------------------------------------
        ! Dictionary: local variables
        !--------------------------------------------------------------------------------
        integer (ip)           :: i, j !! Counters
        real (wp), allocatable ::  w(:)
        !--------------------------------------------------------------------------------

        associate( n => size(x) )
            ! Allocate memory
            allocate( w(n) )
            ! Associate various quantities
            associate( arg => acos(-1.0_wp)/(n+1) )
                do j = 1, n
                    w(j) = 0.0_wp
                    do i = 1, n
                        associate( sin_arg => real(i*j, kind=wp)*arg )
                            w(j) = w(j)+x(i)*sin(sin_arg)
                        end associate
                    end do
                end do
            end associate
        end associate

        x = 2.0_wp * w

        ! Release memory
        deallocate(w)

    end subroutine compute_sine_transform


    pure function compute_cosine_transform(theta, cf) result (return_value)
        !--------------------------------------------------------------------------------
        ! Dictionary: calling arguments
        !--------------------------------------------------------------------------------
        real (wp), intent(in) :: theta
        real (wp), intent(in) :: cf(:)
        real (wp)             :: return_value
        !--------------------------------------------------------------------------------
        ! Dictionary: local variables
        !--------------------------------------------------------------------------------
        integer (ip)          :: i !! Counter
        !--------------------------------------------------------------------------------

        return_value = 0.0_wp

        associate( n => size(cf) )
            do i=1, n
                return_value = return_value + cf(i)*cos(i*theta)
            end do
        end associate

    end function compute_cosine_transform


end program test
