$!	YG_REIMPORT_MULT_OBJ.COM
$!
$! Revision History:
$! V1.0 04-JAN-2007 Implementation Andres Laib
$! Adapted by Yankel Gabet for separation of multiple objects from one scan
$!-------------------------------------------------------------------------
$!
$! FOR BEST RESULTS USE 
$! EVAL:  UE:YG_EVALUATION_V6.COM|UE:YG_ISQ.COM|ue:YG_reimport_mult_obj.com
$! 
$! Project name must remain "separation"
!  Creates new measurement directory for samp_nb defined as:
!	samp_nb = org samp_nb + VALUE IN VARIABLE BOX
!  Define scanning ctlFile/org pos in variables 3&4
$!
$ OUTFILE = P1
$!
$! First letter of new isq (still in org directory) will be changed to "R" for
$!  separated objects or "A" for subvolume in same directory.
$!
$ NEW_ISQ     = EVAL_DIR+"R"+F$STRING(F$EXTRACT(1,7,EVAL_FNAME))+".ISQ"
$! 
$! Object will be renamed with new sample number (+1, +2 .. + eval_misc1_0)
$! Note: "ipl_xxx" is not yet recognized. Use "eval_xxx" instead
$! IF EVAL_MISC1_0 .NES. "0"  
$! THEN  
$	SAMPNO       = "1568" !'EVAL_SAMPNO' - "89" !+ 'EVAL_MISC1_0'
$	NEW_SAMPNO :==  'SAMPNO'
$ 	WRITE OUTFILE "$! Org EVAL number: ''EVAL_SAMPNO'"
$ 	WRITE OUTFILE "$! NEW EVAL number = "1088" !''EVAL_SAMPNO' + ''EVAL_MISC1_0' = ''NEW_SAMPNO'"
$! ELSE
$! 	WRITE OUTFILE "$! New ISQ will not be reimported"
$! 	NEW_ISQ     = EVAL_DIR+"A"+F$STRING(F$EXTRACT(1,7,EVAL_FNAME))+".ISQ"	
$! 	WRITE OUTFILE "$ RENAME/LOG ''EVAL_FNAME0' ''NEW_ISQ'"
$!       GOTO ENDCOM
$! ENDIF 
$!
$ sh sym ipl_support0
$ sh sym eval_sampno
$ sh sym new_isq
$!
$ WRITE OUTFILE "$!"
$ WRITE OUTFILE "$! Starting Re-Import of the reformatted ISQ"
$ WRITE OUTFILE "$! New Sample number will be ''NEW_SAMPNO'"
$ WRITE OUTFILE "$!"
$ WRITE OUTFILE "$ RENAME/LOG ''EVAL_FNAME0' ''NEW_ISQ'"
$! for version import 1.2
$ WRITE OUTFILE "$ DEFINE/USER UCT_XRAY_LOGFILE SYS$SCRATCH:TEMP.TMP"
$ WRITE OUTFILE "$ RUN UM:UCT_IMPORT.EXE"
$ WRITE OUTFILE "''NEW_ISQ'"
$ WRITE OUTFILE "''NEW_SAMPNO'"
$ WRITE OUTFILE "Y" ! change name in header
$ WRITE OUTFILE "1" ! oper
$ WRITE OUTFILE "''EVAL_MISC1_1'" ! ctrlfile
$ WRITE OUTFILE "Y" ! rename file
$!
$ ENDCOM:
$ EXIT
