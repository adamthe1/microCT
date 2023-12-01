$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$! 
$!        
$! Define mid-diaphyseal ring height at ~1 mm (last parameter in VOI in #slice)
$! Define thres for cortical bone (lower0 "1") and lower for mask (lower1 "2").
$! ipl_lower2 "3" is #dilat_ero to fill cortical voids!!!
$! DT spacing analyzes voids morphometry (DT object is for solid ring)
$! - also produces moment  of inertia (MOI) file. 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	seg_f_file     :=  'DEV''DIR''FILENAME'_FULL_SEG.AIM
$	seg_c_file     :=  'DEV''DIR''FILENAME'_CORT_SEG.AIM      ! Should be same as "ipl_segaim
$	seg_r_file     :=  'DEV''DIR''FILENAME'_RING_SEG.AIM      ! After voids deletion
$	seg_t_file     :=  'DEV''DIR''FILENAME'_TRAB_SEG.AIM      !!! not used currently (03-2012)
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$!for testing:
$	seg_d_file     :=  'DEV''DIR''FILENAME'_dil_SEG.AIM      ! After voids deletion
$	seg_cl_file    :=  'DEV''DIR''FILENAME'_cl_SEG.AIM      !!! not used currently (03-2012)
$	seg_e_file     :=  'DEV''DIR''FILENAME'_ero_seg.AIM
$!
$!	down_scale    =  ipl_support2
$	dilation_nr   =  3
$	erosion_nr    =  2
$!	border	      =  dilation_nr * 2 + 1
$!	surf_peel     =  down_scale
$! 	ring_height   =  ipl_upper2  
$	sh sym dilation_nr
$	sh sym erosion_nr
$!
$ ON ERROR THEN EXIT
$ GOTO SEG 
$!
$ SEG:
$ IPL_BATCH
  
!
!   Segmentation
!

/db_scanco_activate true

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix  "ipl_voiy  "ipl_voiz 
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz      

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                           
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_lp                                                    
  -input                     org
  -output                    gau
  -sigma                     "ipl_sigma0
  -support                   "ipl_support0

/threshold  gau  seg
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0	

/gobj seg "ipl_gobj0
  -peel_iter   0

/cl seg 

/write seg "ipl_segaim

		!----------------------------------------|
		!  Masking of bone and filling out pores |
		!----------------------------------------|
!/read seg "seg_c_file

/dilation
  -input                     seg
  -output                    dil
  -dilate_distance           "dilation_nr

/invert dil
/cl dil
/invert dil

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/concat ero seg full_seg
  -common_region_only false
  -add_not_overlay    false

/write full_seg "ipl_segaim

/gobj_to_aim "ipl_gobj0 mask
/write mask "out_mask
..
$ END_MASKING:
$ ANALYSIS:
$ IPL_BATCH

!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "ipl_segaim  
/db_clear_eval seg
/db_scanco_activate true

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/vox_scanco_param
  -input                     seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 2

!/read org  "ipl_aim

! apparent density
!/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -region_number             0

! tissue (matrix) density of segmented volume
!/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number             1

..
$! EXIT
$ ON ERROR THEN CONTINUE
$ PURGE 'IPL_AIM'
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

!
!
! tri now WITHOUT surface suppression, i.e. gobj NONE !!!!
!
!

/tri seg tri
  -gobj_filename             "ipl_gobj0
  -peel_iter                 2
  -ip_sigma                  0.000000
  -ip_support                0
  -ip_threshold              50
  -nr_ave_iter               2
  -t_dir_radius              2
  -epsilon                   1.200000
  -size_image                512 512
  -scale_image               0.700000
  -edges                     false
  -nr_views                  0

..
$ EXIT
$!
$!
$! REMOVE EXIT ABOVE, IF YOU SCAN MORE THAN E.G. 50 SLICES, AND YOU WANT TO
$! CALCULATE ALSO DIRECT MEASURES
$!
$! CONSIDER REMOVING VOIDS IN CORTICAL RING BEFORE DT
$!
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

!---------------------------------------------------|
!  Remove voids in cortical bone before DT analysis |
!---------------------------------------------------|

/read seg "ipl_segaim

/dilation  seg seg_dil
  -dilate_distance           "ipl_lower2
  -continuous_at_boundary    0 0 0

/erosion  seg_dil  seg
  -erode_distance            "ipl_lower2
  -use_previous_margin       true      

/write seg "seg_r_file

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname2

/write out "ipl_fname1

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "seg_r_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4

/write out "ipl_fname3
..
$ EXIT
