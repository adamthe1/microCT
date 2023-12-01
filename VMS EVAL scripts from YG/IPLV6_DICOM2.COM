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
$!
$!  Converts the VOI to DICOM files
$!
$!
$ ! Definitions to create sub-directory for DICOM in the meas.dir:
$  mkdir	:== @YGCOM:MKDIR.COM
$  truncated  	= EVAL_DIR - "]"
$  samp_dir     := 'truncated'.'EVAL_MISC1_0'] 
$  sh sym samp_dir
$  IF samp_dir .EQS. ""  THEN  MKDIR 'samp_dir'
$  samp_tr_dir  = samp_dir - "]" 
$  dicoma_dir := 'samp_tr_dir'.GFILT_DCM]
$  sh sym dicoma_dir
$  IF F$SEARCH(dicoma_dir) .EQS. "" THEN MKDIR 'dicoma_dir'
$  dcma_file  := 'DICOMA_DIR'GRAY_'EVAL_MISC1_0'
$  sh sym dcma_file
$  dicomb_dir := 'samp_tr_dir'.SEG_DCM]
$  sh sym dicomb_dir
$  IF F$SEARCH(dicomb_dir) .EQS. "" THEN MKDIR 'dicomb_dir'
$  dcmb_file  := 'DICOMB_DIR'BINA_'EVAL_MISC1_0'
$  sh sym dcmb_file 
$ EXIT
$!
$ GRAY:
$ IF IPL_MISC1_1 .EQS. "NO" THEN GOTO BINA
$ ON ERROR THEN EXIT
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/gauss org gau
  -sigma       "ipl_sigma0
  -support     "ipl_support0

/write gau "ipl_aim

/todicom_from_aim
  -aim_name                  gau
  -dicom_filename            "dcma_file
  -multifile                 "ipl_misc1_3
..
$ BINA:
$ IF IPL_MISC1_2 .EQS. "NO" THEN GOTO ENDCOM
$!
$ IF F$SEARCH(ipl_segaim) .EQS. ""
$ THEN
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
..
$ ELSE
$ IPL_BATCH
! 
! Convert Seg AIM  to DICOM
!

/read seg "ipl_segaim

/todicom_from_aim
  -aim_name                  seg
  -dicom_filename            "dcmb_file
  -multifile                 "ipl_misc1_3
..
$ ENDIF
$ ENDCOM:
$ EXIT
