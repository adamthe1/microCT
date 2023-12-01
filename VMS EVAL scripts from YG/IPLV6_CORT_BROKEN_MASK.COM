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
$! - also produces moment of inertia (MOI) file. 
$!                         
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	seg_f_file     :=  'DEV''DIR''FILENAME'_FULL_SEG.AIM
$	seg_c_file     :=  'DEV''DIR''FILENAME'_CORT_SEG.AIM      ! Should be same as "ipl_segaim
$	seg_r_file     :=  'DEV''DIR''FILENAME'_RING_SEG.AIM      ! After voids deletion
$	temp_gobj      :=  'DEV''DIR''FILENAME'_TEMP.GOBJ     
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$!for testing:
$ del_files = 1
$	box_r_file     :=  'DEV''DIR''FILENAME'_RING_BOX.AIM
$	box_f_gobj     :=  'DEV''DIR''FILENAME'_FULL_BOX.GOBJ
$	cor_c_gobj     :=  'DEV''DIR''FILENAME'_CORR.GOBJ
$!
$	down_scale    =  ipl_support2
$	dilation_nr   =  ipl_lower2
$	erosion_nr    = 'dilation_nr' + 1
$	border	      =  dilation_nr * 2 + 1
$	surf_peel     =  down_scale
$ 	ring_height   =  ipl_upper2
$	dist_from_met =  ring_height * 2
$!  
$	sh sym dilation_nr
$	sh sym erosion_nr
$!
$ IF F$SEARCH(ipl_gobj2) .EQS. ""                                            
$ THEN
$	write sys$output " For broken bones, TRAB gobj must be defined"
$	EXIT
$ ENDIF
$!
$ ON ERROR THEN EXIT
$!
$! ipl_gobj3 is a corrected CORT gobj created when the auto masking did not work
$! If present, this script runs without masking
$!
$ GOTO SEG
$!
$ SEG:
$ IPL_BATCH
  
!
!   Segmentation
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix  "ipl_voiy  "ipl_voiz 
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz      
!!! Important: use "ipl_voi...  here, only if white box is defined in the eval window
!!! For broken bones, define box to cut at first complete cort ring.

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

/threshold  gau  seg_hi
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0	

/threshold  gau  seg_lo
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -value       127
  -unit	       "ipl_unit1	

/del gau

/bounding_box_cut seg_lo seg_lo2
  -z_only  false
  -border  0  
/del seg_lo

/write seg_lo2 "seg_f_file

/cl seg_lo2 

/bounding_box_cut seg_lo2 seg_lo
  -z_only false
  -border  1 1 1  

/del seg_lo2

!----------------------------------------
! save full AIM in a minimum size volume:

/copy seg_lo box
/set box 127 127
/togobj box  "box_f_gobj
/del box 
/gobj org "box_f_gobj
/bound org org_bb
/write org_bb "ipl_aim
/del org
/del org_bb
!----------------------------------------

/bounding_box_cut seg_hi seg_hi2
  -z_only  false
  -border  0  

/del seg_hi

/cl seg_hi2 

/bounding_box_cut seg_hi2 seg_hi
  -z_only false
  -border  1 1 1  

/del seg_hi2

/write seg_hi "seg_c_file

!For use in masking only:
/write seg_hi "out_mask
 
/del seg_hi
..
$ MASKING:
$!
$ IF F$SEARCH(ipl_gobj3) .NES. ""
$ THEN
$ IPL_BATCH
/gobj_to_aim "ipl_gobj3 corr 0
/read seg_hi "out_mask
/concat seg_hi corr mask
  -common_region_only false
  -add_not_overlay    false
/write mask "out_mask 
..
$ ENDIF 
$ IPL_BATCH
		!--------------------------|
		!  Masking of Total Volume |
		!--------------------------|
!!! Use seg_hi/out_mask to avoid outer spickles.
!!! seg_hi underwent cl so no unattached trabeculae inside.

/read seg "out_mask

! For high-res volumes, downscale before dil_ero and cl
/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dilp1
  -dilate_distance           "dilation_nr

/del sca

! For broken bones, the VOI box cut at a clean ring (for masking)
/bounding_box_cut dilp1 dil
  -z_only true
  -border 0

/del dilp1

/invert dil
/cl dil
/invert dil

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/bounding_box_cut  ero sca
  -z_only false
  -border 2

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false

/concat ero seg mask
  -common_region_only false
  -add_not_overlay    false

/togobj_from_aim  mask "ipl_gobj0
 -curvature_smooth   5

/write mask "out_mask 
..
$ END_MASKING:
$! EXIT
$! 
$!-------------------------------------------------------------|
$!  Isolation of cortical ring as relative to metaphyseal VOI  |
$!  Ring height is ~1mm and starts ~2mm above metaphyseal VOI  |
$!-------------------------------------------------------------|
$!
$ IPL_BATCH

/gobj_to_aim
  -gobj_filename             "ipl_gobj2
  -output                    trab_voi
  -peel_iter                 0

/bounding_box_cut  trab_voi big
  -z_only 		     false
  -border                    "dist_from_met
/del trab_voi

/gobj big "box_f_gobj

/sub_get
  -input                     big
  -output                    ring_voi
  -pos                       0  0  0
  -dim                       -1 -1 "ring_height
  -global_pos_flag           false
/del big

/set ring_voi 127 127 
/write ring_voi "box_r_file
/togobj ring_voi "temp_gobj

/read ring "seg_c_file 
                          
/gobj ring "box_r_file

/bounding_box_cut  ring  ring_bb
  -z_only 		     false
  -border                    10 10 0

/del ring
/read mask "out_mask

/concat  ring_bb mask  mask_c
  -common_region_only        true
  -add_not_overlay           false

/togobj_from_aim mask_c "ipl_gobj1

/ren ring_bb seg
/gobj seg  "ipl_gobj1

!/write_v020 seg "seg_c_file
/write seg "ipl_segaim  
..
$ ANALYSIS:
$ sh sym ipl_gobj1
$ IPL_BATCH
!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "ipl_segaim 
/gobj seg  "ipl_gobj1
/write seg "ipl_segaim 

/db_clear_eval seg
/db_scanco_activate true   

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org     
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number             1

..
$ IF F$SEARCH(temp_gobj) .NES. "" THEN DELETE/NOCONFIRM 'TEMP_GOBJ';*
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
$! EXIT
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

!--------------------------------------------------|
!  Remove voids in cortical bone before DT_Object  |
!--------------------------------------------------|

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

!----------------------------------------------------------------|
! Voids in cortical bone are analyzed (spacing) in DT_background |
!----------------------------------------------------------------|

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
$!for testing:
$ ON ERROR THEN CONTINUE 
$	IF del_files .EQS. "1"
$	THEN
$ 	  IF F$SEARCH(temp_gobj) .NES. "" THEN DELETE/NOCONFIRM 'TEMP_GOBJ';*
$	  IF F$SEARCH(BOX_R_FILE) .NES. "" THEN DELETE/NOLOG/NOCONFIRM  'box_r_file';* 
$	  IF F$SEARCH(box_f_gobj) .NES. "" THEN DELETE/NOLOG/NOCONFIRM  'box_f_gobj';* 
$	  PURGE  F$SEARCH(seg_c_file)
$	  PURGE  F$SEARCH(ipl_aim)
$	ENDIF
$ EXIT
