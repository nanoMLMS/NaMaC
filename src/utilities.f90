module utilities
    implicit none
    private
    public:: read_xyz, distance2, distance, coordination_calc, write_xyz_coordination, gcn_calc, write_xyz_gcn, block_error
 
    
contains

    !> @brief Reads an xyz file, reads the coordinates and saves them to an array
    !!
    !!This code will read from a standard xyz file, doesn't support extended xyz files
    !!
    !!@param[in]    fname   the name of the input xyz file
    !!@param[out]   coordinates an array 3xN_atoms of coordintes
    subroutine read_xyz(fname, coordinates)
        implicit none
        integer :: io, N_atoms, i
        character(len=20), intent(in) :: fname
        character(len=2) :: element
        real :: x_t, y_t, z_t
        real, allocatable :: coordinates(:,:)
        open(newunit=io, file=fname, status="old", action="read")
        read(io, *) N_atoms
        read(io, *) 
        allocate(coordinates(3, N_atoms))
        
        do i = 1, N_atoms
            read(io, *) element, x_t, y_t, z_t
            coordinates(1, i) = x_t
            coordinates(2, i) = y_t
            coordinates(3, i) = z_t
        end do
        close(io)
    end subroutine
    
    !> @brief Utility function that computes the squared distance between two points
    !!
    !! This subrouitine requires the coordinates of two points and it will compute the squared distance
    !! between them. used mostly when the actual distance is not required to be known to save time
    !! one the calculation of the squared root
    !!
    !!@param[in]    pointA  The coordinates of one of the points
    !!@param[in]    pointB  The coordinates of the other point
    !!@param[out]   distance2   The square of the distance between the two points
    subroutine distance2(pointA, pointB, dist2)
        implicit none
        real, intent(in)    ::  pointA(3), pointB(3)
        real, intent(out)   ::  dist2
        real                ::  dist_vec(3)
        
        dist_vec = pointB - pointA     
        dist2 = dist_vec(1) * dist_vec(1) + dist_vec(2) * dist_vec(2) + dist_vec(3) * dist_vec(3)  
    end subroutine distance2
    
    subroutine distance2_pbc(pointA, pointB, Lx, Ly, dist2_pbc)
        !$ACC ROUTINE
        implicit none
        real, intent(in)    ::  pointA(3), pointB(3)
        real, intent(in)    ::  Lx, Ly
        real, intent(out)   ::  dist2_pbc
        real                ::  dist_vec(3)

        dist_vec = pointB - pointA
        if (abs(dist_vec(1)) .gt. Lx / 2) then
            dist_vec(1) = Lx - abs(dist_vec(1))
        elseif (abs(dist_vec(2)) .gt. Ly / 2) then
            dist_vec(2) = Ly - abs(dist_vec(2))
        endif
        dist2_pbc = dist_vec(1) * dist_vec(1) + dist_vec(2) * dist_vec(2) + dist_vec(3) * dist_vec(3)  
        
    end subroutine distance2_pbc


    !> @brief Utility function that computes the distance between two points
    !!
    !! This subroutine computes the distance between two points. If the actual distance is not essential
    !! and if it has to be computed for a large number of pairs of atoms use the distance2 subroutine
    !! as the calculation of the square root is quite expensive
    !!
    !!@param[in]    pointA  The coordinates of one of the points
    !!@param[in]    pointB  The coordinates of the other point
    !!@param[out]   distance    The distance between the two points
    subroutine distance(pointA, pointB, dist)
        !$ACC ROUTINE
        implicit none
        real, intent(in)    ::  pointA(3), pointB(3)
        real, intent(out)   ::  dist
        real                ::  d2

        call distance2(pointA, pointB, d2)
        dist = sqrt(d2)
    end subroutine distance
    
    subroutine distance_pbc(pointA, pointB, Lx, Ly, dist)
        !$ACC ROUTINE
        implicit none
        real, intent(in)    ::  pointA(3), pointB(3)
        real, intent(in)    ::  Lx, Ly
        real, intent(out)   ::  dist
        real                ::  d2

        call distance2_pbc(pointA, pointB, Lx, Ly, d2)
        dist = sqrt(d2)
    end subroutine distance_pbc
    
    !> @brief Computes for each atom its coordination number
    !!
    !! For each atom in the system the coordination number is computed as
    !! the number of other atoms within a certain cutoff distance, if desired
    !! (as set by the pbc variable) it compute the distance using periodic boundary
    !! conditions. Also returns a list of neighbours for each atom as a list of 
    !! indeces pointing to the atoms neighboring the atom
    !!
    !!@param[in]    coordinates 3xN_atoms array of the cooridnates of the atoms
    !!@param[in]    cutoff  real number determining the cutoff for the neighbors 
    !!@param[out]   coordination    array containing for each atom its coordination number
    !!@param[out]   neigh_list  array containing for each atom the indeces of its neighbors
    subroutine coordination_calc(coordinates, cutoff, pbc, coordination, neigh_list)
        implicit none
        integer :: N_atoms, i, j
        real, intent(in) :: coordinates(:, :)
        real, intent(in) :: cutoff
        integer,intent(in)  ::  pbc
        integer, intent(out), allocatable :: coordination(:), neigh_list(:,:)
        real :: dist
        real :: distance_v(3)
        integer :: neighbors, co2
        real :: Lx, Ly
        if ( pbc.eq.1) then
            Lx = maxval(coordinates(1, :)) - minval(coordinates(1,:))
            Ly = maxval(coordinates(2, :)) - minval(coordinates(2,:))
        endif
        N_atoms = size(coordinates, 2)
        allocate(coordination(N_atoms), neigh_list(12,N_atoms))
        !$ACC KERNELS
        !$ACC LOOP INDEPENDENT
        do i = 1, N_atoms
            neighbors = 0
            do j = 1, N_atoms
                if (i .ne. j) then
                    distance_v(:) = coordinates(:, i) - coordinates(:, j)
                    if (pbc.eq.1.and.abs(distance_v(1)) .gt. Lx / 2) then
                        distance_v(1) = Lx - abs(distance_v(1))
                    elseif (pbc.eq.1.and.abs(distance_v(2)) .gt. Ly / 2) then
                        distance_v(2) = Ly - abs(distance_v(2))
                    endif
                    if (pbc.eq.1) then
                        call distance_pbc(coordinates(:,i), coordinates(:,j), Lx, Ly, dist)
                    else
                        call distance(coordinates(:,i), coordinates(:,j), dist)
                    endif
                    if (dist .lt. cutoff) then
                        neighbors = neighbors + 1
                        neigh_list(neighbors, i) = j
                    endif
                endif
            enddo
            coordination(i) = neighbors
        enddo
        !$ACC END KERNELS
    end subroutine coordination_calc     

    subroutine write_xyz_coordination(fname, coordinates, coordination)
        implicit none
        character(len=50), intent(in)   ::  fname
        real, intent(in)                ::  coordinates(:,:)
        integer, intent(in)             ::  coordination(:)
        integer                         ::  N_atoms, i

        N_atoms = size(coordination)

        open(10, file = fname, status = "replace", action = "write", form="formatted")
        
        write(10, *) N_atoms
        write(10, *) "# extended xyz with coordination number"

        do i = 1, N_atoms
            write(10, '(A2, 3f15.3, I3)') "Au", coordinates(:, i), coordination(i) 
        enddo
        close(10)
    end subroutine write_xyz_coordination

    !> @brief Computes the generalized coordination number expressed as $GCN = \sum_{j \in neigh} CN_j/CN_{max}$
    !!
    !!@param[in]    coordination    Array containing for each atoms its coordination number
    !!@param[in]    neigh_list      Array contianing for each atom the list of its neighbor's indeces
    !!@param[in]    cn_max          Maximum number of neighbors, 12 for fcc
    !!@param[out]   gcn             Array containing for each atom ts generalized coordination number
    subroutine gcn_calc(coordination, neigh_list, cn_max ,gcn)
        implicit none
        integer, intent(in) ::  neigh_list(:,:), coordination(:)
        real, intent(in)    ::  cn_max
        real, intent(out), allocatable   ::  gcn(:)
        integer             ::  N_atoms, i

        N_atoms = size(coordination)
        allocate(gcn(N_atoms))
        do i = 1, N_atoms
            gcn(i) = sum(coordination(neigh_list(:,i))) / cn_max
        enddo

    end subroutine gcn_calc

    
    subroutine write_xyz_gcn(fname, coordinates, gcn)
        implicit none
        character(len=50), intent(in)   ::  fname
        real, intent(in)                ::  coordinates(:,:), gcn(:)
        integer                         ::  N_atoms, i

        N_atoms = size(gcn)

        open(10, file = fname, status = "replace", action = "write", form="formatted")
        
        write(10, *) N_atoms
        write(10, *) "# extended xyz with coordination number"

        do i = 1, N_atoms
            write(10, '(A2, 4f15.3)') "Au", coordinates(:, i), gcn(i) 
        enddo
        close(10)
    end subroutine write_xyz_gcn
    
    subroutine block_error(av1, av2, n, error)
        implicit none
        real, intent(in)    ::  av1
        real, intent(in)    ::  av2
        integer, intent(in) ::  n
        real, intent(out)   ::  error

        if (n.eq.1) then
            error = 0.0
        else
            error = sqrt( (av2 - av1 * av1) / real(n) )
        endif
    end subroutine block_error
end module utilities
