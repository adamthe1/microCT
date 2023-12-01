$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!  Fracture callus analysis
$!  The callus is contoured externally (ipl_gobj0, "_T.GOBJ) and 
$!  internally at the original peristeum using an excluding (CW) contour (ipl_gobj1, "_C.GOBJ)
$!  These 2 GOBJs define the MASK for the callus only.
$!
$!  After segmentation with gauss filter and thresholding, 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	mask_gobj    :=  'DEV''DIR''FILENAME'_CALL.GOBJ
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	call_file    :=  'DEV''DIR''FILENAME'_CAL_SEG.AIM
$	sega_file    :=  'DEV''DIR''FILENAME'_ALL_SEG.AIM
$ ON ERROR THEN EXIT
$ IPL_BATCH

/db_scanco_activate true

! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

!
! write VOI to disk (as AIM)
!

/write
  -name                      org
  -filename                  "ipl_aim

!
!   Segmentation
!

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org seg
  -sigma       "ipl_sigma0
  -support     "ipl_support0
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       127

/copy seg seg_org
/gobj
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/write  seg    "sega_file
  -compress  bin

/gobj_to_aim
  -gobj_filename             "ipl_gobj0
  -output                    gobj
  -peel_iter                 0

/bounding_box_cut
  -input                     gobj
  -output                    mask
  -z_only                    false
  -border                    1 1 0

! If you made 1 GOBJ with both contours, delete (or comment out) the commands between the lines:
!------------------------------------------
/gobj_join "ipl_gobj0 "ipl_gobj1 "mask_gobj

/gobj mask
  -gobj_filename            "MASK_GOBJ
  -peel_iter                0
!------------------------------------------
/write  mask "mask_file
  -compress  bin

/copy seg_org callus
/gobj
  -input_output              callus 
  -gobj_filename             "mask_file
  -peel_iter                 0

/write callus "call_file
  -compress  bin

/transparent_concat        
  -input_solid               callus
  -input_transp              seg
  -output                    segaim

/ren segaim seg
/write  seg		    "ipl_segaim
  -compress  bin
..
$ exit
! Keep the callus in its mask (mask_file) for analyses:
/ren   callus  seg
/db_clear_eval seg

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/vox_scanco_param
  -input                     seg

! Mean1: apparent density in the callus only (outside the original cortex)
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "mask_file
  -peel_iter                 0
  -region_number 	     0

! Mean2: tissue (matrix) density of segmented volume in the callus
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "call_file
  -peel_iter                 2
  -region_number 	     1

! Mean3: apparent density in the original bone + callus (incl. BM)
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number 	     2

! Mean4: tissue (matrix) density of segmented volume (cortex+callus)
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "sega_file
  -peel_iter                 2
  -region_number 	     3
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "call_file

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/tri seg tri
  -gobj_filename             "mask_file
  -peel_iter                 -1
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
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "call_file

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "call_file

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "mask_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out    "ipl_fname0

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                1
  -min_number_pixels         6

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "call_file

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             mask_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write  out    "ipl_fname2
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "call_file

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             "mask_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4
..
$ EXIT
