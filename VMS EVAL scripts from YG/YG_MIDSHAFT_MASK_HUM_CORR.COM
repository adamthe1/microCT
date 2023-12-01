$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$! 
$!        
$! Starts after masking and segmentation to remove trabeculae in the diaphyseal
$! ring
$! DT spacing analyzes voids morphometry (DT object is for solid ring)
$! - also produces moment  of inertia (MOI) file. 
$!
$	FILENAME     = F$PARSE("''P1'",,,"NAME")
$	DEV          = F$PARSE("''P1'",,,"DEVICE")
$	DIR          = F$PARSE("''P1'",,,"DIRECTORY")
$	FILENAME     = F$EXTRACT(0,8,filename)
$	ipl_segaim     =    P1      			! Should be '_CORT_SEG.AIM'
$	seg_c_file     =    P1 
$	seg_r_file     :=  'DEV''DIR''FILENAME'_RING_SEG.AIM	! After voids deletion
$	seg_c2_file    :=  'DEV''DIR''FILENAME'_CORT2_SEG.AIM	      		
$	seg_r2_file     :=  'DEV''DIR''FILENAME'_RING2_SEG.AIM	
$	out_gobj       :=  'DEV''DIR''FILENAME'_C.GOBJ
$	ipl_fname0     :=  'DEV''DIR''FILENAME'_MOI.TXT
$	ipl_fname1     :=  'DEV''DIR''FILENAME'_C_TH.AIM
$	ipl_fname2     :=  'DEV''DIR''FILENAME'_C_TH.TXT
$	ipl_fname3     :=  'DEV''DIR''FILENAME'_C_SP.AIM
$	ipl_fname4     :=  'DEV''DIR''FILENAME'_C_SP.TXT
$!for testing:
$	temp_gobj     :=  'DEV''DIR''FILENAME'_temp.GOBJ	! After voids deletion
$	seg_e_file     :=  'DEV''DIR''FILENAME'_ero_seg.AIM
$	seg_f_file     :=  'DEV''DIR''FILENAME'_FULL_seg.AIM
$! 
$!	cl_last_rank  =  ipl_misc1_0
$	down_scale    =  3
$	dilation_nr   =  6
$	erosion_nr    = 'dilation_nr' + 1
$!	border	      =  dilation_nr * 2 + 1
$!	surf_peel     =  down_scale
$! 	ring_height   =  ipl_misc1_2  
$! 	ring_pc_pos   =  ipl_misc1_5  
$	sh sym ipl_segaim
$	sh sym seg_r_file 
$!
$! ON ERROR THEN EXIT
$! GOTO SEG 
$! GOTO END_MASKING
$!
$ IPL_BATCH  

/read ring "seg_r_file
/bound ring bb f 
 -border  10 10 0

/scale_elsize  bb sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false
/del bb

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/bound dil bb f 
 -border  10 10 0
/ren bb dil 

/set  dil 0 127
/cl   dil  
/set  dil 0 127

/bound dil bb f 
 -border  10 10 1
/ren bb dil 

/erosion
  -input                     dil
  -output                    sca
  -erode_distance            "dilation_nr
  -use_previous_margin       true

/scale_elsize  sca  ero
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false

/concat ero ring bb
/write bb "seg_e_file  
/gobj ero "seg_e_file 2
/concat ero ring bb

/togobj bb "out_gobj 
  -curvature_smooth  5

/inv  ring "out_gobj   3
/scale_elsize  ring sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false
/del ring

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/erosion
  -input                     dil
  -output                    sca
  -erode_distance            "dilation_nr
  -use_previous_margin       true

/scale_elsize  sca  ero
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false

/togobj_from_aim ero "temp_gobj 
  -curvature_smooth  1
/gobj ero "temp_gobj 4
/write ero "seg_e_file

/read  ring "seg_r_file
/subtract  ring ero new_ring
/thres new_ring thres 127
/write thres "seg_r2_file

/read cort "seg_c_file
/gobj cort "seg_r2_file
/bound cort bb f 
 -border 5 5 0 
/write bb  "seg_c2_file

..
$!----------------
$! EXIT
$ seg_c_file = seg_c2_file
$ ipl_segaim = seg_c2_file
$ seg_r_file = seg_r2_file
$ ipl_gobj1  = out_gobj
$ ipl_peel1  :== 0
$!
$ ANALYSIS:
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

! To obtain meaningful porosity volume, VOX is run in the RING mask:
! TV - BV = PORES VOLUME 
/voxgobj_scanco_param
  -input                     seg
  -gobj_filename             "seg_r_file
  -peel_iter                 0

/read org  "ipl_aim

! apparent density
!!!
!/voxgobj_scanco_param
!  -input                     org
!  -gobj_filename             "ipl_gobj1
!  -peel_iter                 "ipl_peel1
!  -region_number             0

! tissue (matrix) density of segmented volume
!!!
!/voxgobj_scanco_param
!  -input                     org
!  -gobj_filename             "ipl_segaim
!  -peel_iter                 2
!  -region_number             1

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

/moment2d_of_inertia
  -input                     seg
  -fileout_or_screentab      "ipl_fname0
  -turnangle_cw              0.000000
  -gobj_filename             "ipl_gobj1
  -peel_iter                 0

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                4
  -min_number_pixels         6

..
$! EXIT
$!
$! REMOVE EXIT ABOVE, IF YOU SCAN MORE THAN E.G. 50 SLICES, AND YOU WANT TO
$! CALCULATE ALSO DIRECT MEASURES
$!
$! CONSIDER REMOVING VOIDS IN CORTICAL RING BEFORE DT
$!
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

!----------------------------------------------------------------------|
!  Remove voids in cortical bone before DT analysis by using ring_mask |
!----------------------------------------------------------------------|
/read seg "seg_r_file

! Cortical Thickness:
! -------------------
/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             ipl_gobj1
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname2

/transparent_concat        
  -input_solid               out
  -input_transp              "seg_f_file
  -output                    th

/write th "ipl_fname1

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true


!--------------------------------------------------------------------------|
!  Analysis of cortical pores mean size using DT_Sp (Tb.Sp is Po diameter) |
!--------------------------------------------------------------------------|

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

/transparent_concat        
  -input_solid               out
  -input_transp              "seg_r_file
  -output                    pores

/write pores "ipl_fname3
..
$ ENDCOM:
$ V1 == "@YGCOM:VERSION1.COM"
$ V1 'seg_e_file'
$ V1 'ipl_segaim'
$ V1 'seg_r_file'
$ V1 'seg_r2_file'
$ V1 'out_mask'
$ V1 'ipl_fname0' 
$ V1 'ipl_fname1'
$ V1 'ipl_fname2'
$ V1 'ipl_fname3'
$ V1 'ipl_fname4'
$ V1 'out_mask'
$ DEL/NOCONFIRM 'temp_gobj';*
$ DEL/NOCONFIRM 'seg_e_file';*
$!
$! ORG_COM := 'EVAL_DIR''EVAL_FNAME'_EVAL_'EVAL_PROJECTT'.COM 
$! NEW_COM := 'EVAL_DIR''EVAL_FNAME'_CORT_'EVAL_PROJECTT'.COM 
$! RENAME/NOCONFIRM 'ORG_COM' 'NEW_COM'
$ EXIT
