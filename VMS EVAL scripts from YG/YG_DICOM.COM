$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  Written by Yankel Gabet, Tel Aviv University
$!
$!  IPL Batch Scanco
$!
$!  Converts the VOI to DICOM files
$!  General definitions:
$!
$   multifile_t_f = ipl_misc1_4
$   IF multifile_t_f .EQS. "" THEN multifile_t_f :== true
$   move_aims	  = ipl_misc1_3
$!
$  IF EVAL_MISC1_0 .EQS. "LOCAL" THEN GOTO LOCAL
$! Definitions to create sub-directory for DICOM in the PROJECTS folder:
$  mkdir	:== @YGCOM:MKDIR.COM
$  PRJ_DIR	:=  DK0:[MICROCT.PROJECTS.'EVAL_MISC1_0']
$  IF F$SEARCH(prj_dir) .EQS. ""  THEN  MKDIR 'PRJ_DIR'
$  truncated  	= prj_dir - "]"
$  samp_dir     := 'truncated'.'EVAL_SAMPNAMET'] 
$  sh sym samp_dir
$  IF F$SEARCH(samp_dir) .EQS. ""  THEN  MKDIR 'samp_dir'
$  samp_tr_dir  = samp_dir - "]" 
$  dicoma_dir := 'samp_tr_dir'.DICOM_A]
$  sh sym dicoma_dir
$  IF F$SEARCH(dicoma_dir) .EQS. "" THEN MKDIR 'dicoma_dir'
$  dcma_file  := 'DICOMA_DIR''EVAL_SAMPNO'
$  sh sym dcma_file
$  dicomb_dir := 'samp_tr_dir'.DICOM_B]
$  sh sym dicomb_dir
$  IF F$SEARCH(dicomb_dir) .EQS. "" THEN MKDIR 'dicomb_dir'
$  dcmb_file  := 'DICOMB_DIR''EVAL_SAMPNO'
$  sh sym dcmb_file 
$!
$! STL:
$  stl_file   := 'samp_dir''EVAL_SAMPNAMET'.stl
$  sh sym stl_file
$! 
$  GOTO GRAY
$!
$ LOCAL:
$ ! Definitions to create sub-directory for DICOM in the meas.dir:
$  mkdir	:== @YGCOM:MKDIR.COM
$  truncated  	= EVAL_DIR - "]"
$  samp_dir     := 'truncated'.DICOM] 
$  sh sym samp_dir
$  IF samp_dir .EQS. ""  THEN  MKDIR 'samp_dir'
$  samp_tr_dir  = samp_dir - "]" 
$  dicoma_dir := 'samp_tr_dir'.GFILT_DCM]
$  sh sym dicoma_dir
$  IF F$SEARCH(dicoma_dir) .EQS. "" THEN MKDIR 'dicoma_dir'
$  dcma_file  := 'DICOMA_DIR'GRAY_'EVAL_SAMPNAMET'
$  sh sym dcma_file
$  dicomb_dir := 'samp_tr_dir'.SEG_DCM]
$  sh sym dicomb_dir
$  IF F$SEARCH(dicomb_dir) .EQS. "" THEN MKDIR 'dicomb_dir'
$  dcmb_file  := 'DICOMB_DIR'BINA_'EVAL_SAMPNAMET'
$  sh sym dcmb_file 
$! EXIT
$!
$! STL:
$  stl_file   := 'eval_dir''EVAL_SAMPNAMET'.stl
$  sh sym stl_file
$! 
$!
$ GRAY:
$ IF IPL_MISC1_1 .EQS. "NO"
$ THEN 
$       DELETE 'samp_dir'dicom_a.dir;*   
$ 	GOTO BINA
$ ENDIF	
$ IF F$SEARCH(ipl_aim) .EQS. "" 
$ THEN
$   Write sys$output "Converting newly generated GFILT"  
$   IF ipl_support0 .EQS. "0"
$   THEN
$   Write sys$output "Converting to DICOM without G_FILT"  
$      org :== ignore
$      gau :== org
$      ipl_aim = ipl_fname0
$      ON ERROR THEN CONTINUE 
$   ELSE
$      org :== org
$      gau :== gau
$      ON ERROR THEN EXIT
$   ENDIF
$   IPL_BATCH  
! 
! extract VOI from ISQ
!
/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/gobj org "ipl_gobj0

/sup org
  -supdim_numbers            8 8 8
  -testoff_pixels            "ipl_support0                                           
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss org gau
  -sigma       "ipl_sigma0
  -support     "ipl_support0

/write "gau "ipl_aim

/todicom_from_aim
  -aim_name                  "gau
  -dicom_filename            "dcma_file
  -multifile                 "multifile_t_f
..
$ ELSE
$ Write sys$output "Converting existing GFILT"  
$ IPL_BATCH
! 
! Convert GFILT to DICOM
!

/read gau "ipl_aim

/todicom_from_aim
  -aim_name                  gau
  -dicom_filename            "dcma_file
  -multifile                 "multifile_t_f
..
$ ENDIF   
$ BINA:
$ IF IPL_MISC1_2 .EQS. "NO" 
$ THEN 
$   DELETE 'samp_dir'dicom_b.dir;*   
$   GOTO MOVE_FILES
$ ENDIF
$!
$ IF F$SEARCH(ipl_segaim) .EQS. ""
$ THEN  
$ Write sys$output "Converting newly generated SEG"  
$ IPL_BATCH

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/sup org
  -supdim_numbers            4 4 2
  -testoff_pixels            "ipl_support0

/gauss_seg  org seg
  -sigma       "ipl_sigma0
  -support     "ipl_support0
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0

/write seg "ipl_segaim

/todicom_from_aim
  -aim_name                  seg
  -dicom_filename            "dcmb_file
  -multifile                 "multifile_t_f

/stl   seg stl 
  -stl_output_file           "stl_file

..
$ ELSE
$ Write sys$output "Converting existing SEG"  
$ IPL_BATCH
! 
! Convert Seg AIM  to DICOM
!

/read seg "ipl_segaim

/todicom_from_aim
  -aim_name                  seg
  -dicom_filename            "dcmb_file
  -multifile                 "multifile_t_f

/stl   seg stl 
  -stl_output_file           "stl_file
..
$ ENDIF   
$ MOVE_FILES:
$ IF EVAL_MISC1_0 .EQS. "LOCAL" THEN GOTO ENDCOM
$ IF MOVE_AIMS .EQS. "YES" .OR. MOVE_AIMS .EQS. "Y"
$ THEN 
$ 	COPY  'EVAL_DIR'*SEG*.AIM;*  'SAMP_DIR'
$	COPY  'EVAL_DIR'*.GOBJ     'SAMP_DIR'
$	PURGE 'SAMP_DIR'
$	PURGE 'EVAL_DIR'
$ ENDIF
$ ENDCOM:
$ EXIT
