$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$! 
$! 
$! Performs automatic masking + basic bone morphometry 
$! Define thres for cortical bone (lower1) but lower values for mask (lower2). 
$! Variables (MISC): 1-Last CL|2-#dilat_ero|3-Scal_dw|4-redo_Gfilt?|5-Dims of box?
$! DT spacing analyzes voids morphometry (DT object is for solid ring)
$! - also produces moment of inertia (MOI) file. 
$! Define mid-diaphyseal ring height at ~1 mm (last parameter in VOI in #slice)
$!
$! EVAL: UE:UCT_EVALUATION_V6.COM|UE:YG_MIDSHAFT_MASK.COM|UE:UCT_EVALUATION_V6_MOIRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_3DRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_PRSUCT.COM 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file       :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	seg_file        =   IPL_SEG.AIM 
$	seg_l_file     :=  'DEV''DIR''FILENAME'_LO_SEG.AIM
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$!for testing:
$	seg_d_file     :=  'DEV''DIR''FILENAME'_dil_SEG.AIM	! After voids deletion
$	seg_e_file     :=  'DEV''DIR''FILENAME'_ero_seg.AIM
$! 
$	cl_last_rank  =  ipl_misc1_0
$! cl to remove outer debris but not the epiphysis:
$	cl_min_nb     :==  2000 
$	dilation_nr   =  ipl_misc1_1
$	erosion_nr    = 'dilation_nr' + 1
$	border	      =  dilation_nr * 2 + 1
$	down_scale    =  ipl_misc1_2
$	surf_peel     =  down_scale
$	dims_of_box   =  ipl_misc1_4 
$	redo_gfilt    =  ipl_misc1_3
$	sh sym dilation_nr
$	sh sym redo_gfilt
$	sh sym dims_of_box
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
$	IPL_ISQ   :==  IGNORE.ISQ
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
$       WRITE SYS$OUTPUT "White box dimensions not considered"
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

/threshold  gau  seg_big
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0	

/bounding_box_cut seg_big seg
  -z_only  false
  -border  1 1 1  

/del seg_big

"keep_gau 
!/del gau

!_______________________________________________
!Use the rotated GOBJ as a mask to refine itself:
!_______________________________________________

/gobj_to_aim  "ipl_gobj0 org_mask

/dilation 
 -input    		org_mask
 -output   		dil
 -dilation_distance  	1

/del org_mask

/erosion 
 - input         dil
 - output        ero
 - erode_distance 2
 - use_previous_margin   true

/del dil
/set ero 1 0 
/set seg 40 0
/concat ero seg mask
 - common_region_only  false
 - add_not_overlay     true

/write mask "out_mask

/set mask 127 0
/togobj_from_aim mask "ipl_gobj0
 - curvature_smooth  5



..
$ EXIT
$!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!----------------
$ ANALYSIS:
$! GOTO CORT
$ FULL:
$ IPL_BATCH
!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "seg_file  
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
$! EXIT
$ CORT:
$ IPL_BATCH

!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "ipl_segaim  
/gobj seg "ipl_gobj0   
/db_clear_eval seg
/db_scanco_activate true

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

! TV - BV = PORES VOLUME  
/voxgobj_scanco_param
  -input                     seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/read org  "ipl_aim

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

/tri seg tri                      
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
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
$! EXIT
$ ON ERROR THEN CONTINUE
$ PURGE 'IPL_AIM'
$! Skip MOI unless bones are similarly aligned
$ GOTO SKIP_MOI
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
  -gobj_filename             "ipl_gobj1
  -peel_iter                 0

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                4
  -min_number_pixels         6

..
$ SKIP_MOI:
$! EXIT
$!
$! REMOVE EXIT ABOVE, IF YOU SCAN MORE THAN E.G. 50 SLICES, AND YOU WANT TO
$! CALCULATE ALSO DIRECT MEASURES
$!
$! CONSIDER REMOVING VOIDS IN CORTICAL RING BEFORE DT
$!
$ ON ERROR THEN CONTINUE
$! GOTO SKIP_DT_OB
$ IPL_BATCH

/db_scanco_activate true

!----------------------------------------------------------------------|
!  Remove voids in cortical bone before DT analysis by using ring_mask |
!----------------------------------------------------------------------|
/read seg "ipl_segaim

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
  -input_transp              seg
  -output                    th

/write th "ipl_fname1

..
$ ON ERROR THEN CONTINUE
$ SKIP_DT_OB:
$ IPL_BATCH

/db_scanco_activate true

!------------------------------------------------------------|
!  Analysis of cortical porosity using TRI (BV/TV is PoV/TV) |
!  Can be deleted as performed earlier as VOX !!!            |
!------------------------------------------------------------|
!--------------------------------------------------------------------------|
!  Analysis of cortical pores mean size using DT_Sp (Tb.Sp is Po diameter) |
!--------------------------------------------------------------------------|

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj0
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4

/transparent_concat        
  -input_solid               out
  -input_transp              seg 
  -output                    pores

/write pores "ipl_fname3
..
$ V1 :== "@YGCOM:VERSION1.COM"
$ V1 'seg_f_file'
$ V1 'ipl_segaim'
$ V1 'seg_r_file'
$ V1 'out_mask'
$ V1 'ipl_fname1'
$ V1 'ipl_fname2'
$ V1 'ipl_fname3'
$ V1 'ipl_fname4'
$!
$ ORG_COM := 'EVAL_DIR''EVAL_FNAME'_EVAL_'EVAL_PROJECTT'.COM 
$ NEW_COM := 'EVAL_DIR''EVAL_FNAME'_CORT_'EVAL_PROJECTT'.COM 
$ RENAME/NOCONFIRM 'ORG_COM' 'NEW_COM'
$ EXIT
