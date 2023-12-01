$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!
$!
$!  IPL Batch Scanco
$
$  sigma_gauss    := 0.8
$  support_gauss  := 1
$  threshold_seg  := 210
$  peel_iter_gobj := 0
$!
$!
$!
$  upper_thresh   := 1000
$! to segment bone: use threshold_seg. upper = 1000
$! to segment background: set threshold_seg to -1000 and upper to desired value
$
$
$!  Segmentation with gauss filter and thresholding.
$!  The segmented volume is saved compressed to file.
$!
$!
$   define   org_file 	  'p1'
$   define   gobj_file 	  'p2'
$   define   seg_file 	  'p3'
$
$   thick_histo = "''p1'" - F$PARSE(P1,,,"VERSION") - ".AIM" + "_TH.TXT"
$   separ_histo = "''p1'" - F$PARSE(P1,,,"VERSION") - ".AIM" + "_SP.TXT"
$   inv_n_histo = "''p1'" - F$PARSE(P1,,,"VERSION") - ".AIM" + "_1-OVER-N.TXT"
$   
$
$   show log org_file
$   show log gobj_file
$   show log seg_file
$!
$!
$   ipl_scanco_prog := $um:ipl_scanco_m.exe
$!
$ ON ERROR THEN EXIT
$   ipl_scanco_prog

!
!   Segmentation
!

/db_scanco_activate true

/read   org        org_file

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "support_gauss
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org seg
  -sigma       "sigma_gauss
  -support     "support_gauss
  -low         "threshold_seg  
  -upp	       "upper_thresh
  -value      127

/gobj
  -input_output              seg
  -gobj_filename             gobj_file
  -peel_iter                 "peel_iter_gobj

/write  seg    seg_file
  -compress  bin

/vox_scanco_param
  -input                     seg

! apparent density 
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             gobj_file
  -peel_iter                 "peel_iter_gobj
  -region_number 	     0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             seg_file
  -peel_iter                 2
  -region_number 	     1
..
$ ON ERROR THEN CONTINUE
$ipl_scanco_prog

/db_scanco_activate true

/read seg seg_file

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/tri seg tri
  -gobj_filename             gobj_file
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
$ipl_scanco_prog

/db_scanco_activate true

/read seg seg_file

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ipl_scanco_prog

/db_scanco_activate true

/read seg seg_file

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "thick_histo
..
$ ON ERROR THEN CONTINUE
$ipl_scanco_prog

/db_scanco_activate true

/read seg seg_file

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "separ_histo
..
$ ON ERROR THEN CONTINUE
$ipl_scanco_prog

/db_scanco_activate true

/read seg seg_file

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "inv_n_histo
..
$ exit
$ ON ERROR THEN CONTINUE
$ipl_scanco_prog

/db_scanco_activate true

/read seg seg_file

!   Mil Structural Parameters
/mil_param  org_seg
  -ray_plane_scale           2.000000
  -roi_radius_factor         1.00
  -t_dir_ortho               no
  -t_dir_ortho_nr            8
  -t_dir_radius              2

..
$ exit
