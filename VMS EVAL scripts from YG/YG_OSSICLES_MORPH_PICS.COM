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
$! EVAL: UE:UCT_EVALUATION_V6.COM|UE:YG_OSSICLES_MORPH_PICS.COM|UE:UCT_EVALUATION_V6_MOIRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_3DRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_PRSUCT.COM 
$!
$ 	PRJ_DIR		:== OSSICLES
$!
$	seg_file        =   IPL_SEGAIM 
$!
$ ON ERROR THEN EXIT
$ GOTO ANALYSIS 
$! GOTO PICTURES
$!
!
!   This script assumes seg files are final
!
$ ANALYSIS:
$!
$ GOTO CORT
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
  -output                   pores

/write pores "ipl_fname3
..
$!
$ PICTURES:
$!
$! Definitions to create sub-directory for DICOM in the PROJECTS folder:
$  mkdir	:== @YGCOM:MKDIR.COM
$  PRJ_DIR	:=  DK0:[MICROCT.PROJECTS.'PRJ_DIR']
$  IF F$SEARCH(prj_dir) .EQS. ""  THEN  MKDIR 'PRJ_DIR'
$  truncated  	= prj_dir - "]"
$  TIF_dir     := 'truncated'.TIF] 
$  sh sym tif_dir
$  IF F$SEARCH(tif_dir) .EQS. ""  THEN  MKDIR 'tif_dir'
$!
$ PRESET1	:==  UU:3D_PRESET_STAPES_AR1.DAT
$ PRESET2	:==  UU:3D_PRESET_STAPES_AR2.DAT
$ PRESET3	:==  UU:3D_PRESET_STAPES_AR3.DAT
$ PRESET4	:==  UU:3D_PRESET_STAPES_AR4.DAT
$ PRESET5	:==  UU:3D_PRESET_STAPES_FP1.DAT
$ PRESET6	:==  UU:3D_PRESET_STAPES_FP2.DAT
$ PRESET7	:==  UU:3D_PRESET_STAPES_SD1.DAT
$ PRESET8	:==  UU:3D_PRESET_STAPES_SD2.DAT
$ PRESET9	:==  UU:3D_PRESET_STAPES_SD3.DAT
$ PRESET0	:==  UU:3D_PRESET_STAPES_SD4.DAT
$ SAMP_NAME	= EVAL_SAMPNAMET - "MAROM_OSSICLES_"
$ NAME		:= 'TIF_DIR''samp_name'
$!
$!------------------------------------------------------------------------------
$       COMMANDFILE := SYS$SCRATCH:TIFF_'SAMP_NAME'.COM
$       SHOW SYMBOL COMMANDFILE
$!------------------------------------------------------------------------------
$       OPEN/WRITE OUTFILE 'COMMANDFILE'
$!------------------------------------------------------------------------------
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET1'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_AR1.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET2'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_AR2.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET3'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_AR3.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET4'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_AR4.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET5'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_FP1.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET6'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_FP2.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET7'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_SD1.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET8'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_SD2.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET9'"
$ WRITE OUTFILE "''IPL_SEGAIM'"               
$ WRITE OUTFILE "''NAME'_SD3.TIF"
$!
$ WRITE OUTFILE "$ UCT_THREEDEE_BATCH ''PRESET0'"
$ WRITE OUTFILE "''IPL_SEGAIM'"
$ WRITE OUTFILE "''NAME'_SD4.TIF"
$!
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
