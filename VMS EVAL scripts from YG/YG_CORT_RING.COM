$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$! 
$! 
$! Assumes scan is only mid-diaphyseal ring ~1 mm height
$! Define thres for cortical bone only (lower1=high thres). 
$! Variables (MISC): #dilat_ero|Scale factor|Dims of box?|Redo GFILT?
$! DT spacing analyzes voids morphometry (DT object is for solid ring)
$! - also produces moment of inertia (MOI) file. 
$!
$! EVAL: UE:UCT_EVALUATION_V6.COM|UE:YG_MIDSHAFT_MASK.COM|UE:UCT_EVALUATION_V6_MOIRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_3DRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_PRSUCT.COM 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file       :=  'DEV''DIR''FILENAME'_GFILT.AIM
$!	seg_f_file     :=  'DEV''DIR''FILENAME'_FULL_SEG.AIM
$	seg_c_file     =    IPL_SEGAIM      			! Should be '_CORT_SEG.AIM'
$	seg_r_file     :=  'DEV''DIR''FILENAME'_RING_SEG.AIM	! After voids deletion
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$!for testing:
$	seg_d_file     :=  'DEV''DIR''FILENAME'_dil_SEG.AIM	! After voids deletion
$	seg_e_file     :=  'DEV''DIR''FILENAME'_ero_seg.AIM
$! 
$	dilation_nr   =  ipl_misc1_0
$	erosion_nr    = 'dilation_nr' + 1
$	down_scale    =  ipl_misc1_1      
$	dims_of_box   =  ipl_misc1_2 
$	redo_gfilt    =  ipl_misc1_3
$	sh sym erosion_nr 
$!
$! ON ERROR THEN EXIT
$ GOTO SEG 
$! GOTO END_MASKING
$! GOTO ANALYSIS 
$!
$ SEG:
$ IF  F$SEARCH(gau_file) .NES. ""
$ THEN
$  IF 	redo_gfilt .EQS. "YES"  .OR.  redo_gfilt  .EQS. "Y"
$  THEN	
$       READ_ORG   =  "!!!   ***  Entire ISQ was used, new GFILT is generated  ***"
$       READ_GAU   =  "!!!   ***  New GFILT generated  *** "
$       KEEP_GAU   =  "!/del  gau "
$  ELSE 
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_ORG   =  "!/read org ''ipl_aim' "
$       KEEP_GAU   =  " /del  gau "
$	READ_GAU   =  " /read gau ''gau_file' "
$  ENDIF
$ ENDIF
$!
$ IF 	dims_of_box  .EQS. "N" .OR. dims_of_box  .EQS. "NO"   
$ THEN	
$       ipl_voix   = 0
$       ipl_voiy   = 0
$       ipl_voiz   = 0
$	ipl_voidx  = -1
$	ipl_voidy  = -1
$	ipl_voidz  = -1
$ ENDIF
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
!!! Important: use "ipl_voi...  here, only if white box is defined in the eval window
!!! Last variable defines if the box dimensions are used (Y/N)

"read_org
!/read  org "ipl_aim

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                           
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_lp  org gau                                                  
  -sigma                     "ipl_sigma0
  -support                   "ipl_support0 

!/write gau "gau_file
"read_gau

/threshold  gau  seg_hi_big
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0	

/bounding_box_cut seg_hi_big seg_hi
  -z_only  false
  -border  5 5 0  

/del seg_hi_big

"keep_gau 
!/del gau

/ren seg_hi  cl

/cl_slicewise_extractow
  -input_output              cl
  -lo_vol_fract_in_perc      50.000000
  -up_vol_fract_in_perc      100.000000
  -value_in_range            127

/bounding_box_cut cl seg_hi
  -z_only false
  -border  5 5 0  

/write seg_hi "seg_c_file

!----------------------------------------
! save full AIM & GFILT in a minimum size volume:

/copy seg_hi box
/set box 127 127
/togobj box  "ipl_gobj0
/del box 
/gobj org "ipl_gobj0
/bound org org_bb
/write org_bb "ipl_aim
/del org
/del org_bb
/gobj gau "ipl_gobj0  
/bound gau gau_bb
/write gau_bb "gau_file
!----------------------------------------
..
$ MASKING:
		!--------------------------|
		!  Masking of Total Volume |
		!--------------------------| 
$! No correction of outer mask should be required:
$!
$ IPL_BATCH
/read seg_hi "seg_c_file
!!! Done with seg_hi/out_mask to avoid outer spickles.

! For high-res volumes, downscale before dil_ero and cl
/scale_elsize  seg_hi sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because seg_hi was Gobj'ed with full.aim
! Needs expanding the background for successful cl 

! Ero for Ring mask (excludes the BM, but masks the pores):
! --------------------------------------------------------- 
/erosion
  -input                     dil
  -output                    sca
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/scale_elsize  sca ero_borders
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false
/del sca

/bounding_box_cut ero_borders ero
  -z_only  false
  -border  5 5 0 
/del ero_borders
                 
/concat ero seg_hi ring
  -common_region_only true
  -add_not_overlay    false 
 
/writ ring  "seg_r_file 
/del ring

! Outer mask (Total Area, includes the BM):
! ----------------------------------------- 
/bounding_box_cut dil dil_big
  -z_only  false
  -border  50 50 0  
/ren dil_big dil

/set dil 0 127
/cl  dil
/set dil 0 127

/bounding_box_cut dil dil_small
  -z_only  false
  -border  5 5 0  
/ren dil_small dil

/erosion
  -input                     dil
  -output                    sca
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/scale_elsize  sca ero_borders
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false
/del sca

/bounding_box_cut ero_borders ero
  -z_only  false
  -border  5 5 0 
/del ero_borders
                 
/concat ero seg_hi mask
  -common_region_only true
  -add_not_overlay    false 

/togobj_from_aim  mask "ipl_gobj0
 -curvature_smooth   5

/write mask   "out_mask

!Use ipl_gobj0 instead of seg_r to maintain TV including medulla (for MOI)    
/gobj  seg_hi "ipl_gobj0
/write seg_hi "seg_c_file
..
$ END_MASKING:
$! EXIT
$! 
$!----------------
$ ANALYSIS:
$ CORT:
$ IPL_BATCH

!------------------------|
!  Morphometric analysis |
!------------------------|

! Definitions:
! ipl_segaim = seg_c_file = only mineralized tissue
! seg_r_file = cortical ring masking pores but without BM
! ipl_gobj0  = peristeal envelope incl. BM
 
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
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number             0

! *** Apparent density of cortical ring including Ct.Po *** 
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "seg_r_file
  -peel_iter                 2
  -region_number             1

! tissue (matrix) density of segmented volume (mineralized bone only)
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number             2

..
$! EXIT
$ ON ERROR THEN CONTINUE
$ PURGE 'IPL_AIM'
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim
/gobj seg "ipl_gobj0

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/moment2d_of_inertia
  -input                     seg
  -fileout_or_screentab      "ipl_fname0
  -turnangle_cw              0.000000
  -gobj_filename             "ipl_gobj0
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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname2

/transparent_concat        
  -input_solid               out
  -input_transp              "seg_c_file
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
$ V1 == "@YGCOM:VERSION1.COM"
$ V1 'gau_file'
$ V1 'ipl_segaim'
$ V1 'seg_r_file'
$ V1 'out_mask'
$ V1 'ipl_fname0'
$ V1 'ipl_fname1'
$ V1 'ipl_fname2'
$ V1 'ipl_fname3'
$ V1 'ipl_fname4'
$!
$ ORG_COM := 'EVAL_DIR''EVAL_FNAME'_EVAL_'EVAL_PROJECTT'.COM 
$ NEW_COM := 'EVAL_DIR''EVAL_FNAME'_CORT_'EVAL_PROJECTT'.COM 
$ RENAME/NOCONFIRM 'ORG_COM' 'NEW_COM'
$ EXIT
