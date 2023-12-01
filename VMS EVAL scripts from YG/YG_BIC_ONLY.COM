$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!
$!  BIC calculation and Trabecular PIB analyses in 1/2 subregions.
$!    PART 1: Definition of the 2 VOIs
$	NEW_VOI :== NO
$	newdist  =  52
$!    PART 2: %OI analysis
$	CALC_OI :== YES
$!    PART 3: PIB 3D analysis
$	CAL_PIB :== NO
$!  Required input:
$!	thresholded *_F_SEG.AIM  
$!
$	FILENAME     = F$EXTRACT(0,8,F$PARSE("''IPL_ISQ'",,,"NAME"))
$	EVAL_FNAME   = F$EXTRACT(0,8,F$PARSE("''IPL_ISQ'",,,"NAME"))
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	NAME	     :=  'DEV''DIR''FILENAME'
$!
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	IPL_GOBJ_T   :=  'DEV''DIR''FILENAME'.GOBJ
$	IPL_GOBJ_PIB :=  'DEV''DIR''FILENAME'_PIB.GOBJ
$	IPL_GOBJ_BIC :=  'DEV''DIR''FILENAME'_BIC.AIM
$!
$	surfoit_file := 'NAME'_T_BIC.AIM
$	pibonet_file := 'NAME'_T_PIB.AIM
$	maskoit_file := 'NAME'_T_MASKBIC.AIM
$	maskpit_file := 'NAME'_T_MASKPIB.AIM
$   	implf_file   := 'NAME'_F_SEG.AIM
$   	implt_file   := 'NAME'_T_SEG.AIM
$   	temp_file    := 'NAME'_TEMP.AIM
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH
       
!!! Use a ref volume to set the meas # after the org .ISQ
/isq   in "ipl_isq
	  -pos               "ipl_voix  "ipl_voiy  "ipl_voiz
	  -dim               "ipl_voidx "ipl_voidy "ipl_voidz        

/sub in sub 
 -pos			0 0 0
 -dim			1 1 10
 -global_pos_flag	local

/thres sub ref 0 1000 1 6

/read impl "implf_file

/gobj impl
  -gobj_filename             "ipl_gobj_t
  -peel_iter                 "ipl_peel0

/bounding_box_cut  impl  impl_bb
  -z_only                    false
  -border                    0

/thres impl_bb impl 100 100 100 5
/concat impl   ref  impref false true 
/thres impref  impl 100 100 100 5


/thres impl_bb trab  50  50 50 5

/cop impl void
/set void 0 127
/cl  void  1 1 false 127 
/set void  0 99 
!/write void "test_file
!!! Needs to remove bubbles in the implant:
!/dilate impl dil 3
!/set dil 0 127
!/cl dil 1  1
!/set dil 0 100
!/ero dil ero 4
!/concate ero impl out f f 
!/ren out impl
/concat void impl clean_imp false false
/write clean_imp "implt_file
/concat trab clean_imp imp_trab f f 
/write imp_trab "temp_file 

..
$ EXIT
$ IPL_BATCH 

/read gobj0  "implt_file 

! In the prox VOI:

/sub_get
  -input                     gobj0
  -output                    gobjp
  -pos                       0 0 0
  -dim                       -1 "mid_slice -1
  -global_pos_flag           false

/copy gobjp pip
/ren  gobjp oip

/gobj pip "maskpit_file

/togobj_from_aim
  -input                     pip
  -gobj_filename             "ipl_gobj_pip
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5

/gobj oip "maskoit_file

!/togobj_from_aim
  -input                     oip
  -gobj_filename             "ipl_gobj_oip
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5
/write oip "ipl_gobj_oip                                
! In the distal VOI:

/sub_get
  -input                     gobj0
  -output                    gobjd
  -pos                       0 "mid_slice 0
  -dim                       -1 -1 -1
  -global_pos_flag           false

/copy gobjd pid
/ren  gobjd oid

/gobj pip "maskpit_file

/togobj_from_aim
  -input                     pid
  -gobj_filename             "ipl_gobj_pid
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5

/gobj oid "maskoit_file

!/togobj_from_aim
  -input                     oid
  -gobj_filename             "ipl_gobj_oid
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5
/write oid  "ipl_gobj_oid                               
..
$ IF CALC_OI .EQS. "YES"
$ THEN
$! %OI
$! Analysis of the entire TRAB region:
$!
$ ipl_segaim = surfoit_file
$ ipl_gobj0  = maskoit_file
$!
$ IPL_BATCH 
/db_scanco_activate 	     true

/read  seg    "ipl_segaim

/gobj  seg 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg
..
$ UCT_LIST_OI:
$! OI for the entire TRAB region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_FULL_OI.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_FULL_OI.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_FULL_OI.TXT
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
$! %OI
$! Analysis of the PROX region:
$!
$ ipl_segaim = surfoit_file
$ ipl_gobj0  = IPL_GOBJ_OIP
$!
$ IPL_BATCH 
/db_scanco_activate 	     true

/read  seg    "ipl_segaim

/gobj  seg 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg
..
$ UCT_LIST_OI:
$! OI for the PROX region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_PROX_OI.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_PROX_OI.TXT
$ D3RESULT_LOG	:=  UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_PROX_OI.TXT
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
$! %OI
$! Analysis of the DIST region:
$!
$ ipl_segaim = surfoit_file
$ ipl_gobj0  = IPL_GOBJ_OID
$!
$ IPL_BATCH 
/db_scanco_activate 	     true

/read  seg    "ipl_segaim

/gobj  seg 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg
..
$ UCT_LIST_OI:
$! OI for the DIST region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_DIST_OI.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_DIST_OI.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_DIST_OI.TXT
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
$ ON ERROR THEN CONTINUE
$ ENDIF
$ IF CAL_PIB .EQS. "YES"
$ THEN
$!!! PIB
$!!! Analysis of the entire TRAB region:
$!
$ ipl_segaim = pibonet_file
$ ipl_gobj0  = maskpit_file
$!
$ IPL_BATCH 

/db_scanco_activate true

/read  seg    "ipl_segaim

/gobj  seg 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

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
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname1

!/write  out    "ipl_fname0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4
..
$ UCT_LIST_PIB:
$! For the entire TRAB region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_FULL_PIB.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_FULL_PIB.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_FULL_PIB.TXT
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
$!!! PIB
$!!! Analysis of the PROX region:
$!
$ ipl_segaim = pibonet_file
$ ipl_gobj0  = IPL_GOBJ_PIP
$!
$ IPL_BATCH 

/db_scanco_activate true

/read  seg    "ipl_segaim

/gobj  seg 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

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
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname1

!/write  out    "ipl_fname0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4
..
$ UCT_LIST_PIB:
$! For the PROX region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_PROX_PIB.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_PROX_PIB.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_PROX_PIB.TXT
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
$!!! PIB
$!!! Analysis of the DIST region:
$!
$ ipl_segaim = pibonet_file
$ ipl_gobj0  = IPL_GOBJ_PID
$!
$ IPL_BATCH 

/db_scanco_activate true

/read  seg    "ipl_segaim

/gobj  seg 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

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
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname1

!/write  out    "ipl_fname0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4
..
$ UCT_LIST_PIB:
$! For the DIST region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_DIST_PIB.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_DIST_PIB.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_DIST_PIB.TXT
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
$ ENDIF
$ ENDCOM:
$ EXIT
