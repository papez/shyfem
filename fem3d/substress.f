!
! $Id: substress.f,v 1.1 2018/11/18 15:35:13 georg Exp $
!
! bottom shear stress subroutines
!
! revision log :
!
! 30.11.2018	ggu,ccf	moved from subwaves.f, subn35.f, subssed.f
! 30.11.2018	ccf	create module mod_bstress
!
!*****************************************************************

!==================================================================
        module mod_bstress
!==================================================================

        implicit none

        integer, private, save  :: nkn_stres = 0
        real, allocatable, save :: taubot(:)     !bottom shear stress [N/m2]

        integer, save  		:: ibstress  = 0 !parameter for stress module
        double precision, save  :: da_str(4) = 0 !for output

!==================================================================
        contains
!==================================================================

        subroutine mod_bstress_init(nkn)

        integer  :: nkn

        if( nkn == nkn_stres ) return

        if( nkn > 0 ) then
          if( nkn == 0 ) then
            write(6,*) 'nkn: ',nkn
            stop 'error stop mod_bstress_init: incompatible parameters'
          end if
        end if

        if( nkn_stres > 0 ) then
          deallocate(taubot)
        end if

        nkn_stres = nkn

        if( nkn == 0 ) return

        allocate(taubot(nkn))

        taubot = 0.

        end subroutine mod_bstress_init

!==================================================================
        end module mod_bstress
!==================================================================

        subroutine init_bstress

! initialize output file 

        use mod_bstress

        implicit none

        real 		:: getpar             !get parameter function
        logical 	:: has_output_d
        integer 	:: id,nvar
	integer		:: isedi

        ibstress = nint(getpar('ibstrs'))
        isedi    = nint(getpar('isedi'))

        if ( isedi > 0 ) ibstress = 0	!stress already written in .sed file

        if( ibstress <= 0 ) return

        nvar = 1
        call init_output_d('itmout','idtout',da_str)
        if( has_output_d(da_str) ) then
          call shyfem_init_scalar_file('bstress',nvar,.true.,id)
          da_str(4) = id
        end if

        end subroutine init_bstress

!**************************************************************

        subroutine bstress

! compute bottom stress and write to file 

        use mod_bstress

        implicit none

        logical 	  :: next_output_d
        integer 	  :: id,nvar
        double precision  :: dtime

        if( ibstress <= 0 ) return

        call bottom_stress(taubot)

        if( next_output_d(da_str) ) then
          id = nint(da_str(4))
          call get_act_dtime(dtime)
          call shy_write_scalar_record(id,dtime,893,1,taubot)
        end if

        end subroutine bstress

!**************************************************************

        subroutine bottom_stress(taubot)

! computes bottom stress at nodes (current + waves)

        use basin

        implicit none

        real, intent(out) 		:: taubot(nkn)

        real, allocatable		:: taucur(:)
        real, allocatable		:: tauwav(:)
        integer 			:: k
        real 				:: tc,tw,tm

        allocate(taucur(nkn))
        allocate(tauwav(nkn))

        call current_bottom_stress(taucur)
        call wave_bottom_stress(tauwav)

        do k=1,nkn
          tc = taucur(k)
          tw = tauwav(k)
          if( tc+tw == 0. ) then
            tm = 0.
          else
            tm = tc * ( 1. + 1.2 * ( tw/(tc+tw) )**3.2 )
            tm = max(tm,tw)
          end if
          taubot(k) = tm
        end do

        end

!***********************************************************

        subroutine current_bottom_stress(taucur)

! computes bottom stress at nodes due to currents

        use basin
        use levels
        use evgeom
        use mod_diff_visc_fric
        use mod_ts

        implicit none

        include 'pkonst.h'

        real, intent(out)	:: taucur(nkn)

        integer 		:: ie,k,ii,lmax
        real 			:: area,rho,bnstress
        real, allocatable	:: aux(:)

	allocate(aux(nkn))

        call bottom_friction    !bottom stress on elements (bnstressv)

        taucur = 0.
        aux = 0.

        do ie=1,nel
          lmax = ilhv(ie)
          area = ev(10,ie)
          bnstress = bnstressv(ie)
          do ii=1,3
            k = nen3v(ii,ie)
            rho = rowass + rhov(lmax,k)
            taucur(k) = taucur(k) + rho * bnstress * area
            aux(k) = aux(k) + area
          end do
        end do

        where( aux > 0. ) taucur = taucur / aux

        end

!*********************************************************************

	subroutine wave_bottom_stress(tauwav)

! computes bottom stress from waves (on nodes)

	use basin
	use mod_parwaves
	use mod_waves
        use mod_depth
        use mod_hydro, only : znv

	implicit none

	real, intent(out)	:: tauwav(nkn)

	integer			:: k
	real 			:: h,p,depth

        tauwav = 0.
	if( iwave == 0 ) return

	do k = 1,nkn
	  h = waveh(k)
	  p = wavep(k)
	  depth = hkv(k) + znv(k)
	  call compute_wave_bottom_stress(h,p,depth,z0,tauwav(k))
	end do

	end subroutine wave_bottom_stress

!*****************************************************************

	subroutine compute_wave_bottom_stress(h,p,depth,z0,tauw)

	implicit none

	real h,p	!wave height and period
	real depth	!depth of water column
	real z0		!bottom roughness
	real tauw	!stress at bottom (return)

	include 'pkonst.h'

	real omega,zeta,a,eta,fw,uw
	real, parameter :: pi = 3.14159

	tauw = 0.
	if( p == 0. ) return

        omega = 2.*pi/p
        zeta = omega * omega * depth / grav
        if( zeta .lt. 1. ) then
          eta = sqrt(zeta) * ( 1. + 0.2 * zeta )
        else
          eta = zeta * ( 1. + 0.2 * exp(2.-2.*zeta) )
        end if

	if( eta > 80. ) eta = 80.		!GGUZ0

        uw = pi * h / ( p * sinh(eta) )
        a = uw * p / (2.*pi)
        if( a .gt. 1.e-5 ) then			!GGUZ0
          fw = 1.39 * (z0/a)**0.52
        else
          fw = 0.
        end if

        tauw = 0.5 * rowass * fw * uw * uw

	end subroutine compute_wave_bottom_stress

c******************************************************************