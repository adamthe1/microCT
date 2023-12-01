$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!
$!
 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$    	
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	IPL_GOBJ_P   :=  'DEV''DIR''FILENAME'_P.GOBJ
$	IPL_GOBJ_D   :=  'DEV''DIR''FILENAME'_D.GOBJ
$       IPL_FULL     :=  'DEV''DIR''FILENAME'_FULL_SEG.AIM

$!
$ ON ERROR THEN CONTINUE




 

..
$! Generate Prox and Dist GOBJ:
$! ---------------------------
$ pipe aix 'ipl_full' | search sys$pipe "!> phys dim in mm" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> phys dim in mm"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimz = f$element(2," ",dim_clean)
$ sh sym dimz
$ !IPL_BATCH 

..
$ !UCT_LIST_T:


$! Generate RESULT list and append to PROJECT txt file:
$ !D3RESULT	:= dk0:'EVAL_FNAME'_'EVAL_PROJECTT'_L'DIMZ'.TXT
$ !D3RESULT_ALL	:= dk0:'EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_L'DIMZ'.TXT
$ !D3RESULT_LOG	:= dk0:UCT_LIST_3DLOG_'EVAL_PROJECTT'_L'DIMZ'.TXT

$!
$!------------------------------------------------------------------------------
$!    !   COMMANDFILE := SYS$SCRATCH:ULIST_'FILENAME'.COM
$     !   COMMANDFILE := SYS$SCRATCH:Ulist_test.com
$     !   SHOW SYMBOL COMMANDFILE
$!------------------------------------------------------------------------------
$  !     OPEN/WRITE OUTFILE 'COMMANDFILE'
$!------------------------------------------------------------------------------
$ !WRITE OUTFILE "$! Reading out 3D result database and putting it into appended .txt files"
$ !WRITE OUTFILE "$!"
$ !WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_ALL'"") .EQS. """" "
$ !WRITE OUTFILE "$ THEN"
$ !WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_ALL'"
$ !WRITE OUTFILE "$ ENDIF"
$ !WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_LOG'"") .EQS. """" "
$ !WRITE OUTFILE "$ THEN"
$ !WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_LOG'"
$ !WRITE OUTFILE "$ ENDIF"
$!
$ !WRITE OUTFILE "$ UCT_LIST"
$ !WRITE OUTFILE "UU:UCT_3D_LIST_NOHEAD.TXT"
$ !WRITE OUTFILE "''D3RESULT'"
$ !WRITE OUTFILE "0" ! DEFAULT UNIT
$! WRITE OUTFILE "''EVAL_MEASNO'"
$ OPEN/APPEND OUT DK0:TEMP.TXT
$ !WRITE OUT "'' EVAL_MEASNO'" ":" "''dimz'"
$ WRITE OUT dir, "	", DIMZ
$  WRITE OUTFILE "''EVAL_MEASNO'"
$!
$ !WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_ALL'"
$ !WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_LOG'"
$!
$ !WRITE OUTFILE "$ DELETE ''D3RESULT';"
$ !WRITE OUTFILE "$ EXIT"
$!
$!------------------------------------------------------------------------------
$       !CLOSE OUTFILE
$	
$!------------------------------------------------------------------------------
$!      !SET NOVERIFY
$       !@'COMMANDFILE'
$       !DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$ CLOSE OUT
$ ENDCOM:
$ EXIT

