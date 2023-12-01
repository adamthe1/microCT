$!
$! 
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
$! EVAL: UE:UCT_EVALUATION_V6.COM|UE:SHB_OSSICLE_REFNMT.COM|UE:UCT_EVALUATION_V6_MOIRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_3DRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_PRSUCT.COM 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file     :=  'DEV''DIR''FILENAME'_GFILT.AIM
$!
$	REG1_NAME    = F$PARSE("''IPL_gobj1'",,,"NAME")
$	REG2_NAME    = F$PARSE("''IPL_gobj2'",,,"NAME")
$	REG3_NAME    = F$PARSE("''IPL_gobj3'",,,"NAME")
$ 	REG1_EXT     = F$EXTRACT(8,10,reg1_name) - "_"  
$ 	REG2_EXT     = F$EXTRACT(8,10,reg2_name) - "_"  
$ 	REG3_EXT     = F$EXTRACT(8,10,reg3_name) - "_"  
$	MASK1_FILE   :=  'DEV''DIR''REG1_NAME'_MASK.AIM  	
$	MASK2_FILE   :=  'DEV''DIR''REG2_NAME'_MASK.AIM  
$	MASK3_FILE   :=  'DEV''DIR''REG3_NAME'_MASK.AIM  
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

!!! MISSING HERE for future scripts: ISQ, Gauss, Thres

!----------------------------------------------| 
!  generation of MASK.aim for regions A, M, P  |
!----------------------------------------------|
/db_scanco_activate true

/gobj_to_aim "ipl_gobj0 mask 0
/copy mask   mask1
/gobj mask1 "ipl_gobj1 "ipl_peel1
/writ mask1 "mask1_file
/copy mask   mask2
/gobj mask2 "ipl_gobj2 "ipl_peel2
/writ mask2 "mask2_file
/copy mask   mask3
/gobj mask3 "ipl_gobj3 "ipl_peel3
/writ mask3 "mask3_file

!---------------------------------------------| 
!  generation of SEG.aim for regions A, M, P  |
!---------------------------------------------|

/db_scanco_activate true
/read seg      "ipl_segaim 
/set seg 127 0

/copy seg seg1
/gobj  seg1  "mask1_file
/set seg1 10 0             
/copy seg seg2
/gobj  seg2  "mask2_file
/set seg2 20 0
/copy seg seg3
/gobj  seg3  "mask3_file
/set seg3 40 0

/concat seg1 seg2 out1 	  false true 
/concat out1 seg3 out2 	  false true 
/concat seg  out2 seg_all false false
/write seg_all "ipl_fname0     
..
$!------------------------------------|
$! Morphometric analysis for region 1 |
$!------------------------------------|
$!
$ SEG_FILE  = IPL_SEGAIM
$ REG	    = REG1_EXT
$ MASK_FILE = MASK1_FILE
$ GOBJ_FILE = MASK1_file
$ PEEL_ITER = 0
$!              
$ ANALYSIS:
$ IPL_BATCH
/db_scanco_activate true

/read seg "seg_file 
/gobj seg "gobj_file "peel_iter

/db_clear_eval               seg

/vox_scanco_param
   -input                    seg

!!! Thickness of mask:             

/read mask "mask_file
/dt_object
  -input                     mask
  -output                    out
  -gobj_filename             none
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write out "ipl_fname2

..                                           
$ UCT_LIST:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'REG'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'REG'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'REG'.TXT    
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
$!----------------------------------------------------------------------------- 
$!
$ IF REG .EQS. REG1_EXT
$ THEN
$ 	REG	    = REG2_EXT
$ 	MASK_FILE   = MASK2_FILE
$ 	GOBJ_FILE   = MASK2_file
$	GOTO ANALYSIS
$ ENDIF
$!
$ IF REG .EQS. REG2_EXT
$ THEN
$ 	REG	    = REG3_EXT
$ 	MASK_FILE   = MASK3_FILE
$ 	GOBJ_FILE   = MASK3_file
$	GOTO ANALYSIS
$ ENDIF
$!              
$ EXIT                                                                        
$ 
$ IPL_BATCH
!----------------------------------| 
!  Morphometric analysis D region- |
!----------------------------------|
/db_scanco_activate true

/read seg     "ipl_fname1
/db_clear_eval  seg
                   
      
/vox_scanco_param
   -input                    seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param               
  -input                     org
  -gobj_filename             "ipl_gobj2
  -peel_iter                 "ipl_peel2
  -region_number             1      
..                                           

$ UCT_LIST_D:
$! For the entire femur:                                                  
$!
$! Generate RESULT list and append to PROJECT txt file:    
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_D.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_D.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_D.TXT
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
$ IPL_BATCH
!----------------------------------| 
!  Morphometric analysis U region- |
!----------------------------------|
/db_scanco_activate true

/read seg      "ipl_fname2
/db_clear_eval  seg


      
/vox_scanco_param
   -input                    seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param               
  -input                     org
  -gobj_filename             "ipl_gobj3
  -peel_iter                 "ipl_peel3
  -region_number             1      
..                                           

$ UCT_LIST_U:
$! For the entire femur:                                                  
$!
$! Generate RESULT list and append to PROJECT txt file:    
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_U.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_U.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_U.TXT
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
$!----------------------------------------------------------------------------- 
$ ENDCOM:
$ ON ERROR THEN CONTINUE
$ V1 :== @YGCOM:VERSION1.COM
$ V1 'gau_file'
$ V1 'ipl_segaim'
$!
$ EXIT
