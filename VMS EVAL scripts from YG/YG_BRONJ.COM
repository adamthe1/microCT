$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! (c) Yankel Gabet, Tel Aviv University
$!
$! Analysis of bone necrosis (BRONJ) after extraction in rats
$! Define *_T.gobj for alveolar bone in one extraction socket; and *_C.GOBJ for
$!  the cortical plate buccal to an existing root.
$! Define thres for cortical bone (lower1) but lower values for mask (lower2). 
$! Variables (MISC): Last CL|#dilat_ero|Ring height (slice #)|Dims of box?|Ring pos (%)|Scale factor
$!
$!  Trabecular bone analysis in 2 subregions.
$!  Perform DT calculations?
$	DT_Calc	    :==  YES
$!
$	FILENAME      =  F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV           =  F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR           =  F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$!	ipl_segaim is the combined seg, 0 is for CORT, 1 is for TRAB
$	gau_file     :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	cort_seg      =  ipl_fname0
$	trab_seg      =  ipl_fname1
$	maskt_file   :=  'DEV''DIR''FILENAME'_MSK_T.AIM
$	maskc_file   :=  'DEV''DIR''FILENAME'_MSK_C.AIM
$	IPL_GOBJ_P   :=  'DEV''DIR''FILENAME'_P.GOBJ
$	IPL_GOBJ_D   :=  'DEV''DIR''FILENAME'_D.GOBJ
$!
$       analysis      =  ipl_misc1_0
$	dilation_nr   =  ipl_misc1_1
$	erosion_nr    = 'dilation_nr' + 1
$	redo_gfilt    =  ipl_misc1_2
$	dims_of_box   =  ipl_misc1_3 
$	sh sym dilation_nr 
$!
$! ON ERROR THEN EXIT
$ GOTO SEG 
$! GOTO END_MASKING
$! GOTO ANALYSIS  - Not good because misses the symbol for the number f slices in T, D, P
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
$	IPL_ISQ   :=  IGNORE.ISQ
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
$ ENDIF
$ ON ERROR THEN CONTINUE
$ IPL_BATCH
  
/db_scanco_activate true

! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

!/read  org "ipl_aim
"read_org

! write VOI to disk (as AIM)

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1


/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0

/write org "ipl_aim
/del org

/write gau "gau_file
"read_gau

/copy gau   gau_t

/gobj gau_t 
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/bound gau_t bb  false 5
/ren bb gau_t

/thres gau_t segt
  -low         		     "ipl_lower1  
  -upp	       		     "ipl_upper1
  -value       		     127
  -unit	       		     "ipl_unit1
/del gau_t

/write   segt    "trab_seg
  -compress  bin

/thres gau seg_all
  -low         		     "ipl_lower0  
  -upp	       		     "ipl_upper0
  -value       		     100
  -unit	       		     "ipl_unit0
/del gau
/copy seg_all segc

/gobj segc 
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/bound segc bb  false 5
/ren bb segc
              
/cl segc

/write  segc    "cort_seg
  -compress  bin

! Generate a combined ipl_segaim (with CORT and TRAB in colors):

/set segc 120 0 
/concat seg_all  segc  all_c
  -common_region_only        false
  -add_not_overlay           false 

/bound all_c bb  false 5
/ren bb all_c

/write  all_c  "ipl_segaim
..
$ IF  F$SEARCH(ipl_gobj1) .EQS. ""  
$ THEN 
$	DELETE/NOCONFIRM 'trab_seg';*
$	GOTO  MASK_C
$ ENDIF
$!
$ IPL_BATCH 

/read segt  "trab_seg
/set  segt  110 0 

/concat segt "ipl_segaim  all
  -common_region_only        false
  -add_not_overlay           false 

/write  all  "ipl_segaim
..
$ !!! Colors are ALL=100 ; TRAB=110 ; CORT=120 !!!
$!
$! IF  F$SEARCH(ipl_gobj0) .EQS. ""
$! THEN
$!   DELETE/NOCONFIRM 'cort_seg';*
$! ENDIF 
$! 
$ MASK_T:
$ IPL_BATCH 

! Generate Mask file in TRAB ROI (for midslice)

/gobj_to_aim
  -gobj_filename             "ipl_gobj1
  -output                    gobj
  -peel_iter                 "ipl_peel1

/bounding_box_cut
  -input                     gobj
  -output                    gobj1
  -z_only                    false
  -border                    0 0 0

/write gobj1 "maskt_file 
..
$ MASK_C:
$ IPL_BATCH 
! Generate Mask file in CORT ROI

/read seg "cort_seg

/dilation
  -input                     seg
  -output                    dil
  -dilate_distance           "dilation_nr

/set dil 0 127
/cl  dil
/set dil 0 127

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/concat ero seg mask
  -common_region_only false
  -add_not_overlay    false

/togobj_from_aim  mask "ipl_gobj0
 -curvature_smooth   5

/write mask "maskc_file 
..
$ END_MASKING:
$ IF  F$SEARCH(ipl_gobj1) .EQS. "" THEN  GOTO ANALYSIS
$! Generate Prox and Dist GOBJ (For TRAB ROI only):
$! ---------------------------
$ pipe aix 'maskt_file' | search sys$pipe "!> dim" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> dim"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimz = f$element(2," ",dim_clean)
$ sh sym dimz
$ ipl_voiz = 0
$ ipl_voidz = dimz/2
$ mid_slice = dimz/2
$ sh symb ipl_voiz
$ sh symb ipl_voidz
$!
$ IPL_BATCH 

/read gobj1  "maskt_file 

/sub_get
  -input                     gobj1
  -output                    gobjp
  -pos                       0 0 0
  -dim                       -1 -1 "mid_slice
  -global_pos_flag           false

/togobj_from_aim
  -input                     gobjp
  -gobj_filename             "ipl_gobj_p
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1

/sub_get
  -input                     gobj1
  -output                    gobjd
  -pos                       0 0   "mid_slice
  -dim                       -1 -1 -1
  -global_pos_flag           false

/togobj_from_aim
  -input                     gobjd
  -gobj_filename             "ipl_gobj_d
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1

..
$! Analysis of the entire TRAB region:
$ ANALYSIS:
$  IF 	analysis  .EQS. "N" .OR. analysis  .EQS. "NO"   
$  THEN
$    GOTO ENDCOM
$  ENDIF 	
$!
$ IF  F$SEARCH(ipl_gobj1) .EQS. "" THEN  GOTO CORT_ANALYSIS
$!
$! ipl_gobj1  = maskt_file
$ ipl_segaim = trab_seg 
$!
$ IPL_BATCH 

/read  seg    "ipl_segaim
  -compress  bin

/db_scanco_activate 	     true
/db_clear_eval               seg   

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/vox_scanco_param
  -input                     seg

! apparent density 
/read org "ipl_aim
/gobj org "ipl_gobj1

/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -region_number 	     0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number 	     1
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

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
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$!  IF	DT_Calc .EQS. "NO"  .OR.  DT_Calc  .EQS. "N"
$!  THEN	
$!	GOTO UCT_LIST_T
$!  ENDIF 
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       screen
/read   seg_all  "ipl_segaim
/set    seg_all  127 0
/transparent_concat out seg_all  th

/write  th    "ipl_fname2

..
$ ON ERROR THEN CONTINUE
$  IF	DT_Calc .EQS. "NO"  .OR.  DT_Calc  .EQS. "N"
$  THEN	
$	GOTO UCT_LIST_T
$  ENDIF 
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4
/read   seg_all  "ipl_segaim
/set    seg_all  127 0
/transparent_concat out seg_all  sp
/write  sp    "ipl_fname3
..
$ ON ERROR THEN CONTINUE
$ GOTO UCT_LIST_T   
$		! ****************************************** !
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       screen

..
$ UCT_LIST_T:
$! For the entire TRAB region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_T'DIMZ'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_T'DIMZ'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_T'DIMZ'.TXT
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
$! Analysis of the Proximal region:
$!
$ ipl_gobj1 = ipl_gobj_p
$ ipl_segaim = trab_seg 
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim
  -compress  bin

/db_clear_eval               seg   

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/vox_scanco_param
  -input                     seg

! apparent density 

/read org "ipl_aim
/gobj org "ipl_gobj1

/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -region_number 	     0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number 	     1
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

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
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$  IF	DT_Calc .EQS. "NO"  .OR.  DT_Calc  .EQS. "N"
$  THEN	
$	GOTO UCT_LIST_P
$  ENDIF 
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen      screen

!/write  out    "ipl_fname2

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4

!/write  out    "ipl_fname3
..
$ ON ERROR THEN CONTINUE
$	GOTO UCT_LIST_P   
$			! ************** !
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4

..
$ UCT_LIST_P:
$! For the Proximal region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_P'MID_SLICE'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_P'MID_SLICE'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_P'MID_SLICE'.TXT
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
$! Analysis of the Distal region:
$!
$ ipl_gobj1  = ipl_gobj_d
$ ipl_segaim = trab_seg 
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim

/db_clear_eval               seg   

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/vox_scanco_param
  -input                     seg

! apparent density 
/read org "ipl_aim
/gobj org "ipl_gobj1

/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -region_number 	     0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number 	     1
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

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
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$  IF	DT_Calc .EQS. "NO"  .OR.  DT_Calc  .EQS. "N"
$  THEN	
$	GOTO UCT_LIST_D
$  ENDIF 
$  IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen      screen

!/write  out    "ipl_fname2

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4

!/write  out    "ipl_fname3
..
$ ON ERROR THEN CONTINUE
$	GOTO UCT_LIST_D  
$			! ****************** !
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen      screen

..
$ UCT_LIST_D:
$! For the Distal region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_D'MID_SLICE'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_D'MID_SLICE'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_D'MID_SLICE'.TXT
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
$ CORT_ANALYSIS:
$ IPL_BATCH
!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "cort_seg  
/db_scanco_activate true
/db_clear_eval seg
/gobj seg "maskc_file  0

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "maskc_file
  -peel_iter                 1
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "cort_seg
  -peel_iter                 1
  -region_number             1
/del org

! Cortical Thickness (ignoring voids):
! -------------------

/read cort "maskc_file

/dt_object
  -input                     cort
  -output                    out
  -gobj_filename             "ipl_gobj0
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       screen
/del    cort
/write out "ipl_fname2
/read   trab_th "ipl_fname2
/concat trab_th out th
  -common_region_only        false
  -add_not_overlay           false
/write  th "ipl_fname2
/del trab_th
/del th

! Cortical spacing (intracortical voids):
! ---------------------------------------

!/dt_background
!  -input                     seg
!  -output                    out
!  -gobj_filename             "maskc_file
!  -peel_iter                 0
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname4
!/del seg
!/read   trab_sp "ipl_fname3
!/concat trab_sp out sp
!  -common_region_only        false
!  -add_not_overlay           false 
!/write  sp "ipl_fname3

..
$ UCT_LIST_C:
$! For the cortical plate:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_CORT.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_CORT.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_CORT.TXT
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
$ ON ERROR THEN CONTINUE
$ V1 :== "@YGCOM:VERSION1.COM"
$ V1 	'ipl_aim'     
$ V1	'ipl_segaim'
$ V1 	'gau_file'  
$ V1	'cort_seg'    
$ V1	'trab_seg'
$ V1	'maskt_file' 
$ V1	'maskc_file'
$ V1	'IPL_GOBJ_P'
$ V1	'IPL_GOBJ_D'
$ EXIT
$!
$!
$! Definition of Script control file:
UE:UCT_EVALUATION_V6.COM|UE:YG_BRONJ.COM|UE:UCT_EVALUATION_V6_PRSUCT.COM
?|?|+.ISQ|+.AIM|+_SEG.AIM|+_C_SEG.AIM|+_T_SEG.AIM|+_TH.AIM|+_SP.AIM|+_SP.TXT|
0|+_C.GOBJ|0|+_T.GOBJ|
?|?|?|?|?|?
0.800000|1|200|1000|6|0.800000|1|160|1000|6
BRONJ|?|?|?|?|SYS$SCRATCH:|+.LOG|SYS$fast
Y|5|N|Y
