$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!  Typical application: trab. bone shown within transparent full bone.
$!
$!  Segmentation with gauss filter and thresholding.
$!  Two VOI are segmented, and then combined into a solid/transparent image
$!  The first segmented volume will be solid and undergo MORPH.
$!  The second one transparent in the combined image. If there is an overlap between first and second
$!  input volume: the solid volume wins over the transparent volume.
$!
$!  This script can take TWO contours: 
$!  the 'normal' c0001234.gobj AND optionally, c0001234_F.gobj
$!  The second object is then created with the bigger gobj file, and is
$!  concatenated transparently.
$!
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

/write  org    "ipl_aim
  -compress  bin

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

/write  seg    "ipl_fname0
  -compress  bin

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support1
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org seg1
  -sigma       "ipl_sigma1
  -support     "ipl_support1
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -unit	       "ipl_unit1
  -value       127

/gobj
  -input_output              seg1
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/write  seg1    "ipl_fname1
  -compress  bin

/transparent_concat
  -input_solid               seg
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
..
$ IF ipl_misc1_0 .eqs. "0" .OR. ipl_misc1_0 .eqs. "NO" .OR. ipl_misc1_0 .eqs. "N"
$ THEN 
$	WRITE SYS$OUTPUT "	*** No CL was performed ***"
$	GOTO ENDCOM
$ ENDIF
$!
$ CL_NR:
$ IF  ipl_misc1_0 .GT. 6 
$ THEN 
$!
$   WRITE SYS$OUTPUT "	*** CL_NR was performed to clear out objects < ''ipl_misc1_0' voxels ***"
$   IPL_BATCH
/read seg   "ipl_fname0
/read seg1  "ipl_fname1
/cl_nr_extract
  -input                     seg
  -output                    cl
  -min_number                "ipl_misc1_0

/transparent_concat
  -input_solid               cl
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
/write  cl     "ipl_fname0
  -compress  bin
..
$   GOTO ENDCOM
$ ENDIF
$ CL:
$ IF  ipl_misc1_0 .GE. 1 
$ THEN
$!
$   WRITE SYS$OUTPUT "	*** CL was performed to clear out objects < rank ''ipl_misc1_0' ***"
$   IPL_BATCH
/read seg   "ipl_fname0
/read seg1  "ipl_fname1

/cl_ow_rank_extract
  -input_output              seg
  -first_rank                1
  -last_rank                 "ipl_misc1_0
  -connect_boundary          false

/transparent_concat
  -input_solid               seg
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
/write  seg    "ipl_fname0
  -compress  bin
..
$   GOTO ENDCOM
$ ENDIF
$ ENDCOM:
$ IPL_BATCH

/db_scanco_activate 	     true

/read  seg    "ipl_fname0
  -compress  bin

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg

! apparent density 
/read org "ipl_aim
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number 	     0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_fname0
  -peel_iter                 2
  -region_number 	     1
..
$ UCT_LIST:
$! For the VOI1 (Seg1):
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_BV.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_BV.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_BV.TXT
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
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';*
$!------------------------------------------------------------------------------
$! PURGE 'ipl_segaim'
$ PURGE 'ipl_aim'
$ PURGE 'ipl_fname0'
$ EXIT
