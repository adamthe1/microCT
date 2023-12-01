$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! This script is for the analysis of periodontal bone on the pressure (P) and
$! tension (T) sides of one root.
$! Contours will be drawn at the lamina dura (LD) of the root (+_M/D.GOBJ)
$! and a triangle will define the 90 deg facing the T or P side of the root(s)
$! so there will be 2 triangles: +_MP.GOBJ; +_MT.GOBJ (or _DP...)
$! ipl_misc1_1 (variable 2) defines the number of pixels away from LD for VOI limit
$  DIL_NB = ipl_misc1_1
$!!!  DIL_NB = 6
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM	
$!
$	ROOT0_NAME   = F$PARSE("''IPL_GOBJ0'",,,"NAME")
$ IF F$SEARCH(IPL_GOBJ1) .NES. ""
$ THEN
$	ROOT1_NAME   = F$PARSE("''IPL_GOBJ1'",,,"NAME")
$ ENDIF
$!
$       VOI0P_MASK   :=  'DEV''DIR''ROOT0_NAME'P_MASK.AIM 
$       VOI0T_MASK   :=  'DEV''DIR''ROOT0_NAME'T_MASK.AIM 
$       VOI1P_MASK   :=  'DEV''DIR''ROOT1_NAME'P_MASK.AIM 
$!
$       VOI0P_GOBJ   :=  'DEV''DIR''ROOT0_NAME'P.GOBJ 
$       VOI0T_GOBJ   :=  'DEV''DIR''ROOT0_NAME'T.GOBJ 
$       VOI1P_GOBJ   :=  'DEV''DIR''ROOT1_NAME'P.GOBJ 
$!
$! 0 is for M; 1 is for D root:
$	SEG_0_FILE   :=  'DEV''DIR''ROOT0_NAME'_SEG.AIM 	
$!	SEG_1_FILE   :=  'DEV''DIR''ROOT1_NAME'_SEG.AIM  
$!	MASK0_FILE   :=  'DEV''DIR''ROOT0_NAME'_MASK.AIM  	
$!	MASK1_FILE   :=  'DEV''DIR''ROOT1_NAME'_MASK.AIM  
$!	MASK0_GOBJ   :=  'DEV''DIR''ROOT0_NAME'_MASK.GOBJ  	
$!	MASK1_GOBJ   :=  'DEV''DIR''ROOT1_NAME'_MASK.GOBJ 
$!		
$! GOTO VOI_1
$! GOTO UCT_LIST_1
$!
$ IF 	F$SEARCH(gau_file) .NES. ""    
$ THEN	
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  "/read gau ""gau_file "
$ ELSE 
$       READ_GAU   =  "! New GFILT generated"
$ ENDIF
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH

/db_scanco_activate true         

! create .AIM file from .ISQ

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/write org "ipl_aim

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                          
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss org gau
  -sigma		    "ipl_sigma0	
  -sup                      "ipl_support0

/del org

/write gau "gau_file

"read_gau
!/read  gau "gau_file

/thres gau seg_all 
  -low 			    "ipl_lower0
  -up			    "ipl_upper0		
  -value                    127
  -unit                     "ipl_unit0
/del gau

!consider saving gfilt only

/bounding_box_cut
  -input                     seg_all
  -output                    seg
  -z_only                    false
  -border                    1 1 1
/del seg_all

!!! 
/write seg "ipl_segaim

! Periodontal region "0"
! ----------------------

!/read seg_0 "ipl_segaim

/gobj_to_aim "ipl_gobj0 gobj   "ipl_peel0
/dilation    gobj 	dil
 -dilate_distance      "dil_nb
/subtract    dil        gobj   ring

! Make Pressure and Tension masks:
! --------------------------------
!!! This does address the possility that the ring gets out of the jaw !!!

/copy    ring  zerop
/gobj    zerop "voi0p_gobj
/write   zerop "voi0p_mask
/del     zerop

/ren  	 ring  zerot	
/gobj	 zerot "voi0t_gobj
/write   zerot "voi0t_mask
/del     zerot

/copy   seg    seg_0p
/gobj 	seg_0p "voi0p_mask
/cl 	seg_0p
/dil    seg_0p dil
  -dilate_distance     5
/set 	dil    0 127
/cl 	dil
/set	dil    0 127
/ero 	dil    ero
  -erode_distance      5
  -use_previous_margin false 
/write  ero    "voi0p_mask
/copy 	seg    seg_0p
/gobj 	seg_0p "voi0p_mask
/set    seg_0p 30 0

/copy   seg    seg_0t
/gobj 	seg_0t "voi0t_mask
/cl 	seg_0t
/dil    seg_0t dil
 -dilate_distance      5
/set 	dil    0 127
/cl 	dil
/set	dil    0 127
/ero 	dil    ero
  -erode_distance      5
  -use_previous_margin true 
/write  ero    "voi0t_mask
/copy 	seg    seg_0t
/gobj 	seg_0t "voi0t_mask
/set    seg_0t 60 0

! Merge regions "P" & "T" to full seg 
! -----------------------------------

/concat seg  seg_0p segp
  -common_region_only        false
  -add_not_overlay           false
 
/concat segp seg_0t seg_colors
  -common_region_only        false
  -add_not_overlay           false       

/write seg_colors "ipl_segaim

..
$! EXIT
$!
$ ANALYSIS:
$!
$! --------------------------|
$! Morphometric calculations |
$! --------------------------|
$!
$ IF (ipl_misc1_0 .EQS. "N") .OR. (ipl_misc1_0 .EQS. "NO") THEN GOTO ENDCOM
$!
$ VOI_0P:
$!
$ IF F$SEARCH(VOI0P_GOBJ) .EQS. "" THEN GOTO VOI_0T
$!
$ SEG_FILE  = ipl_segaim
$ TEMP_FILE = SEG_0_FILE
$ GOBJ_FILE = VOI0P_MASK
$ PEEL_ITER = 0
$ ROI 	    = F$EXTRACT(8,10,root0_name) - "_" + "P" 
$ WRITE sys$output " ***  ANALYSIS OF THE ''ROI' REGION  ***"
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/gobj seg  "gobj_file
/set  seg  127 0
/writ seg  "temp_file

/db_clear_eval seg 

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gobj_file
  -peel_iter                 "peel_iter
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "temp_file
  -peel_iter                 1
  -region_number             1             

! Bone thickness:
/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write out "ipl_fname0

!!! Sp of voids:
/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write out "ipl_fname2              

..
$ UCT_LIST_0P:
$! For the ROI 0:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'ROI'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'ROI'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'ROI'.TXT
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
$!------------------------------------------------------------------------------
$!
$ VOI_0T:
$!
$ IF F$SEARCH(VOI0T_GOBJ) .EQS. "" THEN GOTO ENDCOM
$!
$ SEG_FILE  = ipl_segaim
$ TEMP_FILE = SEG_0_FILE
$ GOBJ_FILE = VOI0T_MASK
$ PEEL_ITER = 0
$ ROI 	    = F$EXTRACT(8,10,root0_name) - "_" + "T" 
$ WRITE sys$output " ***  ANALYSIS OF THE ''ROI' REGION  ***"
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/gobj seg  "gobj_file
/set  seg  127 0
/writ seg  "temp_file

/db_clear_eval seg 

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gobj_file
  -peel_iter                 "peel_iter
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "temp_file
  -peel_iter                 1
  -region_number             1             

! Bone thickness:
/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write out "ipl_fname0

!!! Sp of voids:
/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "gobj_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write out "ipl_fname2              

..
$ UCT_LIST_0T:
$! For the VOI 0:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'ROI'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'ROI'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'ROI'.TXT
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
$ ENDCOM:
$ PURGE:
$ PURGE 'VOI0P_MASK'
$ PURGE 'VOI0T_MASK'
$ PURGE 'IPL_SEGAIM'  
$ PURGE 'SEG_0_FILE'  
$ DELETE/NOCONFIRM 'SEG_0_FILE';*
$!
$ EXIT
