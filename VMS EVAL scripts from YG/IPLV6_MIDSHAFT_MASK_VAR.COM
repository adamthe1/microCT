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
$	down_scale    =  ipl_support2
$	dilation_nr   =  ipl_lower2
$	erosion_nr    = 'dilation_nr' + 1
$	border	      =  dilation_nr * 2 + 1
$	surf_peel     =  down_scale
$ 	ring_height   =  ipl_upper2  
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
  -pos                        0  0  0   !!! "ipl_voix  "ipl_voiy  "ipl_voiz 
  -dim                       -1 -1 -1   !!! "ipl_voidx "ipl_voidy "ipl_voidz      
!!! Important: use "ipl_voi...  here, only if white box is defined in the eval window

/gobj org "ipl_gobj2

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

/cl seg_lo2 

/bounding_box_cut seg_lo2 seg_lo
  -z_only false
  -border  1 1 1  

/del seg_lo2

/write seg_lo "seg_f_file

!----------------------------------------
! save full AIM in a minimum size volume:

/copy seg_lo box
/set box 127 127
/togobj box  "ipl_gobj0
/del box 
/gobj org "ipl_gobj0
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
!/write seg_hi "ipl_segaim  

/del seg_hi
..
$ MASKING:
$ IPL_BATCH
		!--------------------------|
		!  Masking of Total Volume |
		!--------------------------|
/read seg "seg_c_file
!!! try with seg_hi to avoid outer spickles.

! For high-res volumes, downscale before dil_ero and cl
/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

/invert dil
/cl dil
/invert dil

/erosion
  -input                     dil
  -output                    sca
  -erode_distance            "erosion_nr
  -use_previous_margin       true

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
/read  full "seg_f_file
/gobj  full "ipl_gobj0
/write full "seg_f_file
..
$ END_MASKING:
$! EXIT
$! 
$!--------------------------------------------|
$!  Isolation of mid-diaphyseal cortical ring |
$!--------------------------------------------|
$!
$ pipe aix 'SEG_F_FILE' | search sys$pipe "!> dim" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> dim"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimz = f$element(2," ",dim_clean)
$ sh sym dimz
$ ipl_voiz = dimz/2
$! Define 1 mm height for ring:
$ pipe aix 'SEG_F_FILE' | search sys$pipe "!> element size in mm" |  -
	(read sys$pipe res_txt ;  defin/nolog/job reslog &res_txt)
$ res_log = f$trnlnm("reslog")
$ res_log = res_log - "!> element size in mm"
$ res_clean = f$edit(res_log,"COMPRESS, TRIM")
$ sh sym res_clean
$ res = f$element(2," ",res_clean)
$ sh sym res
$ ring_height =  1 / res 
$ sh sym ipl_voiz
$ sh sym ring_height
$!----------------
$ IPL_BATCH

/read in "seg_c_file 
                          
/sub_get
  -input                     in
  -output                    ring
  -pos                        0  0 "ipl_voiz
  -dim                       -1 -1 "ring_height
  -global_pos_flag           false
/del in

!!! The FULL gobj (ipl_gobj0/out_mask) was created from low thres bone. 

!!! To adapt it to the high thres in the mid-diaphysis, take off ~3 surface
!!! voxels and replace by seg_hi surface:

/read mask "out_mask

!/peel3d  mask mask_e
!  -peel_iter    "surf_peel   

!/set mask 127 0
!/set ring 127 0
!/examine mask geo
!/examine ring geo

/concat  ring mask  mask_c
  -common_region_only        true
  -add_not_overlay           false

/togobj_from_aim mask_c "ipl_gobj1

/ren ring seg
/gobj seg  "ipl_gobj1

!/write_v020 seg "seg_c_file
/write seg "ipl_segaim  

..
$!----------------
$ ANALYSIS:
$ FULL:
$ IPL_BATCH
!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "seg_f_file  
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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number             0
..
$ UCT_LIST_F:
$! For the entire femur:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_FULL.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_FULL.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_FULL.TXT
$!
$!------------------------------------------------------------------------------
$       COMMANDFILE := SYS$SCRATCH:ULIST_'FILENAME'.COM
$       SHOW SYMBOL COMMANDFILE
$!------------------------------------------------------------------------------
$       OPEN/WRITE OUTFILE 'COMMANDFILE'
$!------------------------------------------------------------------------------
$ WRITE OUTFILE "$! Reading out 3D result database and putting it into appended .txt files"
$ WRITE OUTFILE "$!"
$ WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_ALL'"") .EQS. """" "
$ WRITE OUTFILE "$ THEN"
$ WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_ALL'"
$ WRITE OUTFILE "$ ENDIF"
$ WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_LOG'"") .EQS. """" "
$ WRITE OUTFILE "$ THEN"
$ WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_LOG'"
$ WRITE OUTFILE "$ ENDIF"
$!
$ WRITE OUTFILE "$ UCT_LIST"
$ WRITE OUTFILE "UU:UCT_3D_LIST_NOHEAD.TXT"
$ WRITE OUTFILE "''D3RESULT'"
$ WRITE OUTFILE "0" ! DEFAULT UNIT
$ WRITE OUTFILE "''EVAL_MEASNO'"
$ WRITE OUTFILE "''EVAL_MEASNO'"
$!
$ WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_ALL'"
$ WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_LOG'"
$!
$ WRITE OUTFILE "$ DELETE ''D3RESULT';"
$ WRITE OUTFILE "$ EXIT"
$!
$!------------------------------------------------------------------------------
$       CLOSE OUTFILE
$!------------------------------------------------------------------------------
$!      SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$!
$ CORT:
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
$ PURGE 'seg_f_file'
$ EXIT
