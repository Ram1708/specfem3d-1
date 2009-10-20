program pre_meshfem3D

  use part_decompose_mesh_SCOTCH
  implicit none
  
  include './constants_decompose_mesh_SCOTCH.h'
  include './scotchf.h'

  integer(long) :: nspec
  integer, dimension(:,:), allocatable  :: elmnts
  integer, dimension(:,:), allocatable  :: mat
  integer, dimension(:), allocatable  :: part
  
  integer :: nnodes
  double precision, dimension(:,:), allocatable  :: nodes_coords
    
  integer, dimension(:), allocatable  :: xadj
  integer, dimension(:), allocatable  :: adjncy
  integer, dimension(:), allocatable  :: nnodes_elmnts
  integer, dimension(:), allocatable  :: nodes_elmnts

  integer, dimension(:), pointer  :: glob2loc_elmnts
  integer, dimension(:), pointer  :: glob2loc_nodes_nparts
  integer, dimension(:), pointer  :: glob2loc_nodes_parts
  integer, dimension(:), pointer  :: glob2loc_nodes

  integer, dimension(:), pointer  :: tab_size_interfaces, tab_interfaces
  integer, dimension(:), allocatable  :: my_interfaces
  integer, dimension(:), allocatable  :: my_nb_interfaces
  integer  ::  ninterfaces
  integer  :: my_ninterface
  
  integer(long)  :: nsize           ! Max number of elements that contain the same node.
  integer  :: nb_edges

  integer  :: ispec, inode
  integer  :: ngnod
  integer  :: max_neighbour         ! Real maximum number of neighbours per element
  integer(long)  :: sup_neighbour   ! Majoration of the maximum number of neighbours per element

  integer  :: ipart, nnodes_loc, nspec_loc
  integer  :: num_elmnt, num_node, num_mat

  ! boundaries
  integer  :: ispec2D
  integer  :: nspec2D_xmin, nspec2D_xmax, nspec2D_ymin, nspec2D_ymax, nspec2D_bottom, nspec2D_top
  integer, dimension(:), allocatable :: ibelm_xmin, ibelm_xmax, ibelm_ymin, ibelm_ymax, ibelm_bottom, ibelm_top
  integer, dimension(:,:), allocatable :: nodes_ibelm_xmin, nodes_ibelm_xmax, nodes_ibelm_ymin
  integer, dimension(:,:), allocatable :: nodes_ibelm_ymax, nodes_ibelm_bottom, nodes_ibelm_top 
  
  character(len=256)  :: prname

  logical, dimension(:), allocatable :: mask_nodes_elmnts
  integer, dimension(:), allocatable :: used_nodes_elmnts

  double precision, dimension(SCOTCH_GRAPHDIM)  :: scotchgraph
  double precision, dimension(SCOTCH_STRATDIM)  :: scotchstrat
  character(len=256), parameter :: scotch_strategy='b{job=t,map=t,poli=S,sep=h{pass=30}}'
  integer  :: ierr
  !integer :: i
  
  !pll
  double precision , dimension(:,:), allocatable :: mat_prop
  integer :: count_def_mat,count_undef_mat,imat
  character (len=30), dimension(:,:), allocatable :: undef_mat_prop


! sets number of nodes per element
  ngnod = esize

! reads node coordinates
  open(unit=98, file='./OUTPUT_FILES/nodes_coords_file', status='old', form='formatted')
  read(98,*) nnodes
  allocate(nodes_coords(3,nnodes))
  do inode = 1, nnodes
    ! format: #id_node #x_coordinate #y_coordinate #z_coordinate
    read(98,*) num_node, nodes_coords(1,num_node), nodes_coords(2,num_node), nodes_coords(3,num_node)
    !if(num_node /= inode)  stop "ERROR : Invalid nodes_coords file."
  end do
  close(98)
  print*, 'total number of nodes: '
  print*, '  nnodes = ', nnodes 

! reads mesh elements indexing 
!(CUBIT calls this the connectivity, guess in the sense that it connects with the points index in 
! the global coordinate file "nodes_coords_file"; it doesn't tell you which point is connected with others)
  open(unit=98, file='./OUTPUT_FILES/mesh_file', status='old', form='formatted')
  read(98,*) nspec
  allocate(elmnts(esize,nspec))
  do ispec = 1, nspec
    ! format: # element_id  #id_node1 ... #id_node8

    ! note: be aware that here we can have different node ordering for a cube element;
    !          the ordering from Cubit files might not be consistent for multiple volumes, or uneven, unstructured grids
    !         
    !          guess here it assumes that spectral elements ordering is like first at the bottom of the element, anticlock-wise, i.e. 
    !             point 1 = (0,0,0), point 2 = (0,1,0), point 3 = (1,1,0), point 4 = (1,0,0)
    !          then top (positive z-direction) of element 
    !             point 5 = (0,0,1), point 6 = (0,1,1), point 7 = (1,1,1), point 8 = (1,0,1)
    read(98,*) num_elmnt, elmnts(5,num_elmnt), elmnts(1,num_elmnt),elmnts(4,num_elmnt), elmnts(8,num_elmnt), &
          elmnts(6,num_elmnt), elmnts(2,num_elmnt), elmnts(3,num_elmnt), elmnts(7,num_elmnt)

    !    read(98,*) num_elmnt, elmnts(1,num_elmnt), elmnts(2,num_elmnt),elmnts(3,num_elmnt), elmnts(4,num_elmnt), &
    !          elmnts(5,num_elmnt), elmnts(6,num_elmnt), elmnts(7,num_elmnt), elmnts(8,num_elmnt)

    if((num_elmnt > nspec) .or. (num_elmnt < 1) )  stop "ERROR : Invalid mesh file."

      
    !outputs info for each element to see ordering
    !print*,'ispec: ',ispec
    !print*,'  ',num_elmnt, elmnts(5,num_elmnt), elmnts(1,num_elmnt),elmnts(4,num_elmnt), elmnts(8,num_elmnt), &
    !      elmnts(6,num_elmnt), elmnts(2,num_elmnt), elmnts(3,num_elmnt), elmnts(7,num_elmnt)    
    !print*,'elem:',num_elmnt
    !do i=1,8
    !  print*,' i ',i,'val :',elmnts(i,num_elmnt),&
    !    nodes_coords(1,elmnts(i,num_elmnt)),nodes_coords(2,elmnts(i,num_elmnt)),nodes_coords(3,elmnts(i,num_elmnt))
    !enddo
    !print*
        
  end do
  close(98)
  print*, 'total number of spectral elements:'
  print*, '  nspec = ', nspec

! reads material associations
  open(unit=98, file='./OUTPUT_FILES/materials_file', status='old', form='formatted')
  allocate(mat(2,nspec))
  do ispec = 1, nspec
    ! format: # id_element #flag
    ! note: be aware that elements may not be sorted in materials_file
    read(98,*) num_mat,mat(1,num_mat) !mat(1,ispec)!, mat(2,ispec) 
    if((num_mat > nspec) .or. (num_mat < 1) ) stop "ERROR : Invalid mat file."
  end do
  close(98)

! TODO:
! must be changed, if  mat(1,i) < 0  1 == interface , 2 == tomography
  mat(2,:) = 1
  
! reads material definitions
  count_def_mat = 0
  count_undef_mat = 0
  open(unit=98, file='./OUTPUT_FILES/nummaterial_velocity_file', status='old', form='formatted')
  read(98,*,iostat=ierr) num_mat
  print *,'materials:'
  ! counts materials (defined/undefined)
  do while (ierr == 0)
     print*, '  num_mat = ',num_mat
     if(num_mat /= -1) then 
        count_def_mat = count_def_mat + 1        
     else
        count_undef_mat = count_undef_mat + 1
     end if
     read(98,*,iostat=ierr) num_mat
  end do
  close(98)
  print*, '  defined = ',count_def_mat, 'undefined = ',count_undef_mat
  ! check with material flags
  if( count_def_mat > 0 .and. maxval(mat(1,:)) > count_def_mat ) then
    print*,'error material definitions:'
    print*,'  materials associated in materials_file:',maxval(mat(1,:))
    print*,'  bigger than defined materials in nummaterial_velocity_file:',count_def_mat
    stop 'error materials'
  endif
  allocate(mat_prop(5,count_def_mat))
  allocate(undef_mat_prop(5,count_undef_mat))
  ! reads in defined material properties
  open(unit=98, file='./OUTPUT_FILES/nummaterial_velocity_file', status='old', form='formatted')
  do imat=1,count_def_mat
     ! format:# material_id  # rho    # vp      # vs      # Q_flag     # 0 
     read(98,*) num_mat, mat_prop(1,num_mat),mat_prop(2,num_mat),mat_prop(3,num_mat),mat_prop(4,num_mat),mat_prop(5,num_mat)
     if(num_mat < 0 .or. num_mat > count_def_mat)  stop "ERROR : Invalid nummaterial_velocity_file file."    

     !checks attenuation flag with integer range as defined in constants.h like IATTENUATION_SEDIMENTS_40, ....
     if( int(mat_prop(4,num_mat)) > 13 ) then
        stop 'wrong attenuation flag in mesh: too large, not supported yet - check with constants.h'
     endif
  end do
  ! reads in undefined material properties
  do imat=1,count_undef_mat
     read(98,'(5A30)') undef_mat_prop(1,imat),undef_mat_prop(2,imat),undef_mat_prop(3,imat),undef_mat_prop(4,imat), &
          undef_mat_prop(5,imat)
  end do
  close(98)

! reads in absorbing boundary files
  open(unit=98, file='./OUTPUT_FILES/absorbing_surface_file_xmin', status='old', form='formatted')
  read(98,*) nspec2D_xmin
  allocate(ibelm_xmin(nspec2D_xmin))
  allocate(nodes_ibelm_xmin(4,nspec2D_xmin))
  do ispec2D = 1,nspec2D_xmin 
    ! format: #id_(element containing the face) #id_node1_face .. #id_node4_face
    ! note: ordering for CUBIT seems such that the normal of the face points outward of the element the face belongs to;
    !         in other words, nodes are in increasing order such that when looking from within the element outwards, 
    !         they are ordered clockwise
    !
    !          doesn't necessarily have to start on top-rear, then bottom-rear, bottom-front, and finally top-front i.e.: 
    !          point 1 = (0,1,1), point 2 = (0,1,0), point 3 = (0,0,0), point 4 = (0,0,1)
    read(98,*) ibelm_xmin(ispec2D), nodes_ibelm_xmin(1,ispec2D), nodes_ibelm_xmin(2,ispec2D), &
          nodes_ibelm_xmin(3,ispec2D), nodes_ibelm_xmin(4,ispec2D)

    !outputs info for each element for check of ordering          
    !print*,'ispec2d:',ispec2d
    !print*,'  xmin:', ibelm_xmin(ispec2D), nodes_ibelm_xmin(1,ispec2D), nodes_ibelm_xmin(2,ispec2D), &
    !      nodes_ibelm_xmin(3,ispec2D), nodes_ibelm_xmin(4,ispec2D)     
    !do i=1,4
    !  print*,'i',i,'val:',ibelm_xmin(ispec2d),nodes_coords(1,nodes_ibelm_xmin(i,ispec2D)), &
    !      nodes_coords(2,nodes_ibelm_xmin(i,ispec2D)),nodes_coords(3,nodes_ibelm_xmin(i,ispec2D))
    !enddo
    !print*
  end do
  close(98)
  print*, 'absorbing boundaries:'
  print*, '  nspec2D_xmin = ', nspec2D_xmin 

! reads in absorbing boundary files
  open(unit=98, file='./OUTPUT_FILES/absorbing_surface_file_xmax', status='old', form='formatted')
  read(98,*) nspec2D_xmax
  allocate(ibelm_xmax(nspec2D_xmax))
  allocate(nodes_ibelm_xmax(4,nspec2D_xmax))
  do ispec2D = 1,nspec2D_xmax
    ! format: #id_(element containing the face) #id_node1_face .. #id_node4_face
    read(98,*) ibelm_xmax(ispec2D), nodes_ibelm_xmax(1,ispec2D), nodes_ibelm_xmax(2,ispec2D), &
          nodes_ibelm_xmax(3,ispec2D), nodes_ibelm_xmax(4,ispec2D)
  end do
  close(98)
  print*, '  nspec2D_xmax = ', nspec2D_xmax

! reads in absorbing boundary files
  open(unit=98, file='./OUTPUT_FILES/absorbing_surface_file_ymin', status='old', form='formatted')
  read(98,*) nspec2D_ymin
  allocate(ibelm_ymin(nspec2D_ymin))
  allocate(nodes_ibelm_ymin(4,nspec2D_ymin))
  do ispec2D = 1,nspec2D_ymin 
    ! format: #id_(element containing the face) #id_node1_face .. #id_node4_face   
    read(98,*) ibelm_ymin(ispec2D), nodes_ibelm_ymin(1,ispec2D), nodes_ibelm_ymin(2,ispec2D),  &
          nodes_ibelm_ymin(3,ispec2D), nodes_ibelm_ymin(4,ispec2D)
  end do
  close(98)
  print*, '  nspec2D_ymin = ', nspec2D_ymin 

! reads in absorbing boundary files
  open(unit=98, file='./OUTPUT_FILES/absorbing_surface_file_ymax', status='old', form='formatted')
  read(98,*) nspec2D_ymax
  allocate(ibelm_ymax(nspec2D_ymax))
  allocate(nodes_ibelm_ymax(4,nspec2D_ymax))
  do ispec2D = 1,nspec2D_ymax 
    ! format: #id_(element containing the face) #id_node1_face .. #id_node4_face  
    read(98,*) ibelm_ymax(ispec2D), nodes_ibelm_ymax(1,ispec2D), nodes_ibelm_ymax(2,ispec2D),  &
          nodes_ibelm_ymax(3,ispec2D), nodes_ibelm_ymax(4,ispec2D)
  end do
  close(98)
  print*, '  nspec2D_ymax = ', nspec2D_ymax

! reads in absorbing boundary files
  open(unit=98, file='./OUTPUT_FILES/absorbing_surface_file_bottom', status='old', form='formatted')
  read(98,*) nspec2D_bottom
  allocate(ibelm_bottom(nspec2D_bottom))
  allocate(nodes_ibelm_bottom(4,nspec2D_bottom))
  do ispec2D = 1,nspec2D_bottom 
    ! format: #id_(element containing the face) #id_node1_face .. #id_node4_face   
    read(98,*) ibelm_bottom(ispec2D), nodes_ibelm_bottom(1,ispec2D), nodes_ibelm_bottom(2,ispec2D), &
          nodes_ibelm_bottom(3,ispec2D), nodes_ibelm_bottom(4,ispec2D)
  end do
  close(98)
  print*, '  nspec2D_bottom = ', nspec2D_bottom 

! reads in free_surface boundary files
  open(unit=98, file='./OUTPUT_FILES/free_surface_file', status='old', form='formatted')
  read(98,*) nspec2D_top
  allocate(ibelm_top(nspec2D_top))
  allocate(nodes_ibelm_top(4,nspec2D_top))
  do ispec2D = 1,nspec2D_top 
    ! format: #id_(element containing the face) #id_node1_face .. #id_node4_face
    read(98,*) ibelm_top(ispec2D), nodes_ibelm_top(1,ispec2D), nodes_ibelm_top(2,ispec2D), &
           nodes_ibelm_top(3,ispec2D), nodes_ibelm_top(4,ispec2D)
  end do
  close(98)
  print*, '  nspec2D_top = ', nspec2D_top

! checks valence of nodes
  allocate(mask_nodes_elmnts(nnodes))
  allocate(used_nodes_elmnts(nnodes))
  mask_nodes_elmnts(:) = .false.
  used_nodes_elmnts(:) = 0
  do ispec = 1, nspec
    do inode = 1, ESIZE
      mask_nodes_elmnts(elmnts(inode,ispec)) = .true.
      used_nodes_elmnts(elmnts(inode,ispec)) = used_nodes_elmnts(elmnts(inode,ispec)) + 1
    enddo
  enddo
  print *, 'nodes valence: '
  print *, '  min = ',minval(used_nodes_elmnts(:)),'max = ', maxval(used_nodes_elmnts(:))
  do inode = 1, nnodes
    if (.not. mask_nodes_elmnts(inode)) then
      stop 'ERROR : nodes not used.'
    endif
  enddo
  nsize = maxval(used_nodes_elmnts(:))
  sup_neighbour = ngnod * nsize - (ngnod + (ngnod/2 - 1)*nfaces)
  print*, '  nsize = ',nsize, 'sup_neighbour = ', sup_neighbour

  elmnts(:,:) = elmnts(:,:) - 1

  allocate(xadj(1:nspec+1))
  allocate(adjncy(1:sup_neighbour*nspec))
  allocate(nnodes_elmnts(1:nnodes))
  allocate(nodes_elmnts(1:nsize*nnodes))
  
  call mesh2dual_ncommonnodes(nspec, nnodes, nsize, sup_neighbour, elmnts, xadj, adjncy, nnodes_elmnts, &
       nodes_elmnts, max_neighbour, 1)
  print*, 'mesh2dual: '
  print*, '  max_neighbour = ',max_neighbour

  nb_edges = xadj(nspec+1)

! allocates & initializes partioning of elements
  allocate(part(1:nspec))
  part(:) = -1


! SCOTCH partitioning
    call scotchfstratinit (scotchstrat(1), ierr)
     if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot initialize strat'
    endif

    call scotchfstratgraphmap (scotchstrat(1), trim(scotch_strategy), ierr)
     if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot build strat'
    endif

    call scotchfgraphinit (scotchgraph (1), ierr)
    if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot initialize graph'
    endif

    call scotchfgraphbuild (scotchgraph (1), 0, nspec, xadj (1), xadj (1), &
         xadj (1), xadj (1), nb_edges, adjncy (1), adjncy (1), ierr)
    if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot build graph'
    endif

    call scotchfgraphcheck (scotchgraph (1), ierr)
    if (ierr /= 0) then
       stop 'ERROR : MAIN : Invalid check'
    endif

    call scotchfgraphpart (scotchgraph (1), nparts, scotchstrat(1),part(1),ierr)
    if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot part graph'
    endif

    call scotchfgraphexit (scotchgraph (1), ierr)
    if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot destroy graph'
    endif

    call scotchfstratexit (scotchstrat(1), ierr)
    if (ierr /= 0) then
       stop 'ERROR : MAIN : Cannot destroy strat'
    endif
 
! local number of each element for each partition
  call Construct_glob2loc_elmnts(nspec, part, glob2loc_elmnts)

! local number of each node for each partition
  call Construct_glob2loc_nodes(nspec, nnodes,nsize, nnodes_elmnts, nodes_elmnts, part, &
       glob2loc_nodes_nparts, glob2loc_nodes_parts, glob2loc_nodes)

  call Construct_interfaces(nspec, sup_neighbour, part, elmnts, xadj, adjncy, tab_interfaces, &
             tab_size_interfaces, ninterfaces, count_def_mat, mat_prop(3,:), mat(1,:))

  allocate(my_interfaces(0:ninterfaces-1))
  allocate(my_nb_interfaces(0:ninterfaces-1))

  do ipart = 0, nparts-1

     write(prname, "(i6.6,'_Database')") ipart
     open(unit=15,file='./OUTPUT_FILES/proc'//prname,status='unknown', action='write', form='formatted')
 
     call write_glob2loc_nodes_database(15, ipart, nnodes_loc, nodes_coords, glob2loc_nodes_nparts, glob2loc_nodes_parts, &
          glob2loc_nodes, nnodes, 1)
     call write_partition_database(15, ipart, nspec_loc, nspec, elmnts, glob2loc_elmnts, glob2loc_nodes_nparts, &
          glob2loc_nodes_parts, glob2loc_nodes, part, mat, ngnod, 1)

     write(15,*) nnodes_loc
     call write_glob2loc_nodes_database(15, ipart, nnodes_loc, nodes_coords, glob2loc_nodes_nparts, glob2loc_nodes_parts, &
          glob2loc_nodes, nnodes, 2)

     call write_material_properties_database(15,count_def_mat,count_undef_mat, mat_prop, undef_mat_prop) 

     write(15,*) nspec_loc
     call write_partition_database(15, ipart, nspec_loc, nspec, elmnts, glob2loc_elmnts, glob2loc_nodes_nparts, &
          glob2loc_nodes_parts, glob2loc_nodes, part, mat, ngnod, 2)

     call write_boundaries_database(15, ipart, nspec, nspec2D_xmin, nspec2D_xmax, nspec2D_ymin, &
          nspec2D_ymax, nspec2D_bottom, nspec2D_top, ibelm_xmin, ibelm_xmax, ibelm_ymin, &
          ibelm_ymax, ibelm_bottom, ibelm_top, nodes_ibelm_xmin, nodes_ibelm_xmax, nodes_ibelm_ymin, &
          nodes_ibelm_ymax, nodes_ibelm_bottom, nodes_ibelm_top, & 
          glob2loc_elmnts, glob2loc_nodes_nparts, glob2loc_nodes_parts, glob2loc_nodes, part)

     call Write_interfaces_database(15, tab_interfaces, tab_size_interfaces, ipart, ninterfaces, &
          my_ninterface, my_interfaces, my_nb_interfaces, glob2loc_elmnts, glob2loc_nodes_nparts, glob2loc_nodes_parts, &
          glob2loc_nodes, 1)
     write(15,*) my_ninterface, maxval(my_nb_interfaces)
     call Write_interfaces_database(15, tab_interfaces, tab_size_interfaces, ipart, ninterfaces, &
          my_ninterface, my_interfaces, my_nb_interfaces, glob2loc_elmnts, glob2loc_nodes_nparts, glob2loc_nodes_parts, &
          glob2loc_nodes, 2)
     
      
     close(15)
     
  end do
  print*, 'partitions: '
  print*, '  num = ',nparts
  print*
  print*, 'files in directory: OUTPUT_FILES/'
  print*, 'finished successfully'
  print*
  
end program pre_meshfem3D

