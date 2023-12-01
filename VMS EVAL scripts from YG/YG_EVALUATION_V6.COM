$!	UCT_EVALUATION V6.0
$!
$! Revision History:
$! 04-APR-2006 Implementation Bruno Koller
$! 02-DEC-2006 User Procedures added BK
$! 30-JUN-2009 AL: if eval_equeue == inline --> inline instead of submit batch job
$!             to force immediate execution, e.g. to prevent timing delays of db readout
$!
$!---------------------------------------------------------------------
$!
$! Parser
$ WRITE SYS$OUTPUT "UCT_EVALUATION V6.0"
$ SHOW SYMBOL P%
$!
$ @UE:UCT_EVALUATION_V6_PARSE.COM "''P1'" "''P2'" "''P3'" "''P4'" -
	"''P5'" "''P6'" "''P7'" "''P8'"
$!
$ SMNAME = F$FAO("!8ZL_!8ZL",F$INTEGER(EVAL_SAMPNO),F$INTEGER(EVAL_MEASNO))
$ EVAL_LOGFILE2 := 'EVAL_LOGDEST'EVAL_'EVAL_PROJECTTT'_'SMNAME''EVAL_LOGFILE'
$ JOBNAME := EVAL_'EVAL_PROJECTTT'_'SMNAME'
$!
$ COMMANDFILE := 'EVAL_DIR''EVAL_FNAME'_EVAL_'EVAL_PROJECTT'.COM
$!
$ IF EVAL_PROJECTT .EQS. "SEPARATION"
$ THEN
$	SAMPNO        =  'EVAL_SAMPNO' + 'EVAL_MISC1_0'
$	COMMANDFILE   := 'EVAL_DIR''EVAL_FNAME'_EVAL_'EVAL_PROJECTT'_'SAMPNO'.COM
$ 	EVAL_LOGFILE2 := 'EVAL_LOGDEST'EVAL_'EVAL_PROJECTTT'_'EVAL_SAMPNO'_TO_'SAMPNO''EVAL_LOGFILE'
$ 	JOBNAME       :=  EVAL_'EVAL_PROJECTTT'_'EVAL_SAMPNO'_TO_'SAMPNO'
$ ENDIF
$!
$ OPEN/WRITE OUTFILE 'COMMANDFILE'
$ COMMANDFILE = F$SEARCH(COMMANDFILE) 	! get version no.
$!
$ @UE:UCT_EVALUATION_V6_WRITE 'OUTFILE'
$!
$ IF EVAL_IPLFILE .NES. ""
$ THEN
$  WRITE SYS$OUTPUT "UCT_EVALUATION_V6 Writing IPL Script ''EVAL_IPLFILE'"
$  WRITE OUTFILE "$!"
$  WRITE OUTFILE "$! Starting IPL"
$  WRITE OUTFILE "$!"
$  WRITE OUTFILE "$ @''EVAL_IPLFILE'"
$ ENDIF
$!
$ K = 0
$ LOOP:
$ IF F$TYPE(EVAL_USERFILE'K') .NES. ""
$ THEN
$  IF EVAL_USERFILE'K' .NES. ""
$  THEN
$    WRITE OUTFILE "$!"
$    WRITE OUTFILE "$! User Procedure ''K':"
$    TEMP = F$STRING(EVAL_USERFILE'K') 
$    WRITE SYS$OUTPUT "UCT_EVALUATION_V6 Writing UserScript''K' ''TEMP'"
$    @'TEMP' 'OUTFILE'
$  ENDIF
$  K = K+1
$  GOTO LOOP 
$ ENDIF
$!
$! Call further scripts here, 2 possibilities:
$! Either: $ @UE:MYSCRIPT.COM 'OUTFILE' ! has to write to outfile
$! or: 	   $ WRITE OUTFILE "$ @UE:MYIPLSCRIPT.COM"
$! 
$!
$ WRITE OUTFILE "$ EXIT"
$!
$ CLOSE:
$ CLOSE OUTFILE
$!
$ IF EVAL_EQUEUE .NES. "INLINE"
$ THEN
$  WRITE SYS$OUTPUT "UCT_EVALUATION_V6 Submitting Batch Job"
$  SUBMIT/NOPRINT/NOTIFY/QUE='EVAL_EQUEUE'/LOG='EVAL_LOGFILE2'/NAME='JOBNAME' -
	'COMMANDFILE'	! /DELETE   remove "!" if you want commandfile to be deleted
$ ELSE
$  EVAL_LOGFILE2 = "SYS$SCRATCH:NON_DEFINED.LOG"
$  JOBNAME = "NON_DEFINED"
$  @'COMMANDFILE'
$ ENDIF
$!
$ EXIT
