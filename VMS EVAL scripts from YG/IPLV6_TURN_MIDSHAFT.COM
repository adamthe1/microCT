$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH
  
!
!   Segmentation
!

/db_scanco_activate true

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz        

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

/gobj
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/write  seg    "ipl_segaim
  -compress  bin

/db_clear_eval seg

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/vox_scanco_param
  -input                     seg

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number             1

..
$ ON ERROR THEN CONTINUE
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
  -gobj_filename             none
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

/moment2d_of_inertia
  -input                     seg
  -fileout_or_screentab      "ipl_fname0
  -turnangle_cw              0.000000

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                4
  -min_number_pixels         6

..
$ EXIT
$
$!
$! REMOVE EXIT ABOVE, IF YOU SCAN MORE THAN E.G. 50 SLICES, AND YOU WANT TO
$! CALCULATE ALSO DIRECT MEASURES
$!
$!
$!
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

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
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4

/write out ""ipl_fname3
..
$ EXIT
