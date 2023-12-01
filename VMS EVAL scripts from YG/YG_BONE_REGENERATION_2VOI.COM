$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! For new bone formation (e.g. critical size defects), two VOIs.
$! The new bone is defined as additional BV over the defect
$! Defect is Average BV on the untouched side - defect side in the controls
$! New bone is 'BV defect side' - 'BV contralat side' - 'Defect' 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM	
$!
$	SIDE0_NAME   = F$PARSE("''IPL_GOBJ0'",,,"NAME")
$	SIDE1_NAME   = F$PARSE("''IPL_GOBJ1'",,,"NAME")
$!
$	SEG_0_FILE   :=  'DEV''DIR''SIDE0_NAME'_SEG.AIM 	
$	SEG_1_FILE   :=  'DEV''DIR''SIDE1_NAME'_SEG.AIM  
$	MASK0_FILE   :=  'DEV''DIR''SIDE0_NAME'_MASK.AIM  	
$	MASK1_FILE   :=  'DEV''DIR''SIDE1_NAME'_MASK.AIM  
$	MASK_FILE   :=  'DEV''DIR'TEST_MASK.AIM  
$	MASK0_GOBJ   :=  'DEV''DIR''SIDE0_NAME'_MASK.GOBJ  	
$	MASK1_GOBJ   :=  'DEV''DIR''SIDE1_NAME'_MASK.GOBJ 
$!		
$! Reconstructed multi-object image:  ILP_SEGAIM 
$!		
$! GOTO VOI_0
$! GOTO UCT_LIST_1
$!
$! IF 	F$SEARCH(gau_file) .NES. ""    
$! THEN	
$!	IPL_ISQ   :=  IGNORE.ISQ
$!	READ_GAU   =  "/read gau ""gau_file "
$! ENDIF
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

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                          
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss org gau
  -sigma		    "ipl_sigma0	
  -sup                      "ipl_support0

/write org "ipl_aim
/del org

/write gau "gau_file
  -compress_type             bin
  -version_020               true

"read_gau
!/read  gau "gau_file

!
!   Segmentation
!

/thres gau seg 
  -low 			    "ipl_lower0
  -up			    "ipl_upper0		
  -value                    127
  -unit                     "ipl_unit0

/bounding_box_cut
  -input                     seg
  -output                    bb
  -z_only                    false
  -border                    1 1 1

/ren bb seg
 
!/write seg "ipl_segaim 

! Gobj region "0"
! ---------------

/copy seg    seg_0
/gobj seg_0  "ipl_gobj0 "ipl_peel0 
/writ seg_0 "SEG_0_FILE
/set  seg_0  40


! GOBJ region "1"
! ---------------

/copy seg    seg_1
/gobj seg_1  "ipl_gobj1 "ipl_peel1 
/writ seg_1 "SEG_1_FILE
/set  seg_1  80


! Merge calvarial regions "0" & "1" to full 
! -----------------------------------------

/concat seg seg_0 seg_f0
  -common_region_only        false
  -add_not_overlay           false
 
/concat seg_f0 seg_1 seg
  -common_region_only        false
  -add_not_overlay           false

/write seg  "ipl_segaim
..
$! EXIT
$!
$ IF (ipl_misc1_0 .EQS. "F") .OR. (ipl_misc1_0 .EQS. "NO") THEN GOTO ENDCOM
$!
$! --------------------------|
$! Morphometric calculations |
$! --------------------------|
$!
$ VOI_0:
$!
$ SEG_FILE  = SEG_0_FILE
$ GOBJ_FILE = ipl_gobj0
$ PEEL_ITER = ipl_peel0
$ SIDE 	    = F$EXTRACT(8,10,side0_name) - "_"  
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/db_clear_eval seg 
/gobj seg  "gobj_file

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
  -gobj_filename             "gobj_file
  -peel_iter                 1
  -region_number             1
  
/tri seg tri
  -gobj_filename             "gobj_file
  -peel_iter                 "peel_iter
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
                                   

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write out "ipl_fname0

 
!!! Sp of voids:

!/dt_background
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write out "ipl_fname2              

..
$ WRITE SYS$OUTPUT "Side 0 analysis done; writing UCT_List"     
$ UCT_LIST_0:
$! For the VOI 0:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'SIDE'.TXT
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
$ VOI_1:
$!
$ SEG_FILE  = SEG_1_FILE
$ GOBJ_FILE = ipl_gobj1
$ PEEL_ITER = ipl_peel1
$ SIDE 	    = F$EXTRACT(8,10,side1_name) - "_"  
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/gobj seg  "gobj_file

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
  -gobj_filename             "gobj_file
  -peel_iter                 1
  -region_number             1
  
/tri seg tri
  -gobj_filename             gobj_from_log                      
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

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/concat "ipl_fname0 out all
  -common_region_only        false
  -add_not_overlay           false

/write all "ipl_fname0

 
!!! Sp of voids:

!/dt_background
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/concat "ipl_fname2 out all
!  -common_region_only        false
!  -add_not_overlay           false

!/write all "ipl_fname2

..
$ WRITE SYS$OUTPUT "Side 1 analysis done; writing UCT_List"     
$ UCT_LIST_1:
$! For the VOI 1:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'SIDE'.TXT
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
$ PURGE 'gau_file'
$ PURGE 'ipl_aim'
$!
$!
$ ENDCOM:
$ EXIT
