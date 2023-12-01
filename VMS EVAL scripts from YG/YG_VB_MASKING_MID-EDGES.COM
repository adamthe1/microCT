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
$!  Trabecular bone analysis in 2 subregions.
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file     :=  ipl_aim
$	oldgau_file  :=  'DEV''DIR''FILENAME'_gau.aim
$	inn_mask     :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	out_mask     :=  'DEV''DIR''FILENAME'_MASK_C.AIM
$	IPL_GOBJ_X   :=  'DEV''DIR''FILENAME'_X.GOBJ
$	IPL_GOBJ_T   :=  'DEV''DIR''FILENAME'.GOBJ
$	IPL_GOBJ_O   :=  'DEV''DIR''FILENAME'_O.GOBJ   ! O for outer, not zero
$	IPL_GOBJ_M   :=  'DEV''DIR''FILENAME'_M.GOBJ
$	IPL_GOBJ_E   :=  'DEV''DIR''FILENAME'_E.GOBJ 
$!
$	ipl_gobj0     =  ipl_gobj_t
$	run_auto_mask =  ipl_misc1_0
$	thres_mask    =  'ipl_lower0' - 50
$	dilation_nr   =  ipl_misc1_1
$	erosion_nr    =  'dilation_nr' + 1
$	down_scale    =  ipl_misc1_2
$	redo_gfilt    =  ipl_misc1_3
$	sh sym dilation_nr 
$!
$ GOTO SEG 
$! GOTO END_MASKING
$! GOTO ANALYSIS 
$!
$ v1   :== @YGCOM:version1.COM
$ V1       'IPL_ORIG_ISQ' 
$ PURGE    'IPL_ORIG_ISQ'
$ IPL_ISQ = IPL_ORIG_ISQ
$!
$ SEG:
$ IF  F$SEARCH(gau_file) .EQS. "" .AND. F$SEARCH(oldgau_file) .NES. ""
$ THEN
$	rename 'oldgau_file' 'gau_file'
$ ENDIF 
$ IF  F$SEARCH(gau_file) .NES. ""
$ THEN
$  IF 	redo_gfilt .EQS. "YES"  .OR.  redo_gfilt  .EQS. "Y"
$  THEN	
$       READ_GAU  :=  "!!!   ***  New GFILT generated  *** "
$  ELSE 
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  " /read gau ''gau_file' "
$  ENDIF
$ ENDIF
$!
$ sh sym ipl_gobj_x
$ sh sym ipl_gobj_t
$ sh sym read_gau
$ sh sym run_auto_mask
$!
$ IF run_auto_mask .EQS. "YES" .OR. run_auto_mask .EQS. "Y"  
$ THEN
$   IF F$SEARCH(ipl_gobj_x) .EQS. "" THEN GOTO MISSING
$   IF F$SEARCH(ipl_gobj_x) .NES. "" THEN GOTO MASKING
$ ELSE
$   IF F$SEARCH(ipl_gobj_t) .EQS. "" THEN GOTO MISSING
$   IF F$SEARCH(ipl_gobj_t) .NES. "" THEN GOTO NO_MASKING
$ ENDIF 
$!
$ MISSING:
$   WRITE SYS$OUTPUT ""
$   WRITE SYS$OUTPUT "**** Missing files or wrong answer ****"
$   WRITE SYS$OUTPUT "	For automatic masking you need:"
$   WRITE SYS$OUTPUT "	   - Answer YES"
$   WRITE SYS$OUTPUT "	   - Save Elipse as _X.GOBJ"
$   WRITE SYS$OUTPUT "	For direct analysis (no masking) you need:"
$   WRITE SYS$OUTPUT "	   - Answer NO"
$   WRITE SYS$OUTPUT "	   - Save accurate contour as C0001234.GOBJ"
$   WRITE SYS$OUTPUT ""
$   EXIT
$!
$ MASKING:
$ ON ERROR THEN EXIT
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

!
! write VOI to disk (as AIM)
!
/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0
/del org

/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj_x
  -peel_iter                 0

/bounding_box_cut
  -input                     gau
  -output                    out
  -z_only                    false
  -border                    0 0 0

/ren out gau
/write gau "ipl_aim
"read_gau                            

/thres gau seg
  -low         		     "ipl_lower0  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/write  seg    "ipl_segaim
  -compress  bin

/thres gau seg_lo
  -low         		     "thres_mask  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/del gau
/write  seg_lo    "inn_mask
  -compress  bin 

! processing of seg for outer mask only:

! First make an outer mask (with normal thres seg):
/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because this will cut the dilated surface before ero... 
/set dil 0 127
/cl  dil                                                                          
/set dil 0 127

/erosion
  -input                     dil                                            
  -output                    sca
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale                                    
  -integrate		     false

/set ero 50 0
/concat ero seg mask
  -common_region_only false
  -add_not_overlay    false
 
/togobj_from_aim  mask "ipl_gobj_o
 -curvature_smooth   5              

/write mask "out_mask
                            
! Now use the outer mask to separate the inner background (with lo thres seg):

/inv seg_lo 
 -gobj_filename  "out_mask
/ren seg_lo seg_inv

! To delete small bubbles in the primary spongiosa: 
/cl  seg_inv

/scale_elsize  seg_inv sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because this will cut the dilated surface before ero... 
/set dil 0 127
/cl  dil                                                                          
/set dil 0 127

! For this ero, use the same nr as dilation for acuracy. 
! Peel_iter will be used at analysis
/erosion
  -input                     dil                                            
  -output                    sca
  -erode_distance            "dilation_nr
  -use_previous_margin       true

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale                                    
  -integrate		     false

/set ero 50 0
/concat ero seg_inv mask
  -common_region_only false
  -add_not_overlay    false
 
/togobj_from_aim  mask "ipl_gobj_t
  -min_elements       200
  -max_elements       0      
  -curvature_smooth   5              

/write mask "inn_mask

/read  seg "ipl_segaim
/gobj  seg "ipl_gobj_t 5
/write seg "ipl_segaim
..
$ NO_MASKING:
$ IF (run_auto_mask .EQS. "YES") .OR. (run_auto_mask .EQS. "Y")  
$ THEN
$   GOTO ANALYSIS
$ ENDIF 
$!
$! Vb segmentation without auto masking:
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

!
! write VOI to disk (as AIM)
!
/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0
/del org

/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/bounding_box_cut
  -input                     gau
  -output                    out
  -z_only                    false
  -border                    0 0 0

/ren out gau
/write gau "ipl_aim
"read_gau                            

/thres gau seg
  -low         		     "ipl_lower0  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/write  seg    "ipl_segaim
  -compress  bin

! Generate Mask file (for midslice)

/gobj_to_aim
  -gobj_filename             "ipl_gobj0
  -output                    gobj
  -peel_iter                 0

/bounding_box_cut
  -input                     gobj
  -output                    gobj0
  -z_only                    false
  -border                    0 0 0

/write gobj0 "inn_mask 
..
$!_________
$ ANALYSIS:
$!---------
$! Generate Prox and Dist GOBJ:
$! ---------------------------
$ pipe aix 'inn_mask' | search sys$pipe "!> dim" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> dim"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimz = f$element(2," ",dim_clean)
$ sh sym dimz
$ ipl_voiz = 0
$ ipl_voidz = dimz/3
$ mid_start = dimz/3
$ sh symb ipl_voiz
$ sh symb ipl_voidz
$!
$ IPL_BATCH 

/read gobj0  "inn_mask 

/sub_get
  -input                     gobj0
  -output                    gobjm
  -pos                        0  0 "mid_start
  -dim                       -1 -1 "ipl_voidz
  -global_pos_flag           false

/togobj_from_aim
  -input                     gobjm
  -gobj_filename             "ipl_gobj_m
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5

/subtract_aims     
  -input1                    gobj0
  -input2                    gobjm
  -output                    gobje

/togobj_from_aim
  -input                     gobje
  -gobj_filename             "ipl_gobj_e
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5

..
$! Analysis of the entire TRAB region:
$!
$ ipl_gobj0 = inn_mask
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim
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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/tri seg tri
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out    "ipl_fname0

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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write  out    "ipl_fname2
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
  -histofile_or_screen       "ipl_fname4

..
$ UCT_LIST_T:
$! For the entire TRAB region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_TRAB_F.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_TRAB_F.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_TRAB_F.TXT
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
$! Analysis of the Center (Middle) region:
$!
$ ipl_gobj0 = ipl_gobj_m
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim
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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

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
$ UCT_LIST_M:
$! For the Middle (central) region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_TRAB_M.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_TRAB_M.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_TRAB_M.TXT
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
$! Analysis of the Edge region:
$!
$ ipl_gobj0 = ipl_gobj_e
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim
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
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

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
$ UCT_LIST_E:
$! For the Distal region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_TRAB_E.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_TRAB_E.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_TRAB_E.TXT
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
$ ENDCOM:
$ PURGE	'DEV''DIR''FILENAME'*.ISQ
$ PURGE	'DEV''DIR''FILENAME'*.AIM
$ PURGE	'DEV''DIR''FILENAME'*.GOBJ
$!
$ EXIT
