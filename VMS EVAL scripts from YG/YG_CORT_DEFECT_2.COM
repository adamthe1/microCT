$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! For new bone formation and quality of surrounding tissue, 2 VOIs based on
$! one contour of the original defect (_O.GOBJ). 
$! The cortex in this VOI and adjacent BM tissues are analyzed separately (PharmaSeed)
$! ipl_lower1 must be lower than ipl_lower0
$! Attn: seg_0 is low-dens bone (at thres lower1) and seg_1 starts at thres lower0
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM	
$!
$! Defect VOI only (analyzed)   	
$	SEG_0_FILE   :=  'DEV''DIR''FILENAME'_SEG_0.AIM 	
$! Surrounding bone only (analyzed) 
$	SEG_1_FILE   :=  'DEV''DIR''FILENAME'_SEG_1.AIM 
$! Reconstructed multi-object image:
$!	ILP_SEGAIM  
$	OUTER_MASK     :=  'DEV''DIR''FILENAME'_MASK.AIM  
$!	MASK_T_FILE    :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	TEMP_FILE      :=  'DEV''DIR''FILENAME'_TEMP.AIM
$!		
$! Dilation number knowing that scaling=2
$	dilation_nr   =  20
$	erosion_nr    = 'dilation_nr' - 2
$!
$! Miscellanous:
$       run_masking   =  ipl_misc1_0
$       run_analysis  =  ipl_misc1_1
$	redo_gfilt    =  ipl_misc1_2
$	dims_of_box   =  ipl_misc1_3 
$
$  IF 	run_masking .EQS. "YES"  .OR.  run_masking  .EQS. "Y"
$  THEN	
$ 	GOTO MASKING
$  ELSE
$	GOTO ANALYSIS
$  ENDIF  
$!
$ MASKING:
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

!/gobj org "ipl_gobj0 "ipl_peel0
/write org "ipl_aim
/del org

/write gau "gau_file

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
/del gau

! Keep seg w/o cl for analysis. Seg+cl will be used for mask only.
/write seg   "ipl_segaim 
/copy  seg  seg_cl

/cl seg_cl

! Make 2 masks: since defect is healed, no difference betw/ outer and inner. 
! The healed cort segment is extracted with _O.GOBJ to make _D.GOBJ
! Surrounding tissue mask is generated as before

! Cortical mask:
! -------------

/scale_elsize  seg_cl sca
  -down_scale                2
  -up_scale                  1
  -integrate		     false

! first remove attached trabeculae:
/ero sca ero 2
/cl  ero 
 
/dil ero dil  
  -dilate_distance 	     7 !to close pores only (incl first ero)

/bound dil bb
  -z_only                    true
  -border                    2  !BM should not be masked
/ren bb dil                     

/set dil 0 127 
/cl dil 
/set dil 0 127 

/erosion
  -input                     dil
  -output                    sca
  -erode_distance            5 !
  -use_previous_margin       true

/scale_elsize  sca  mask
  -down_scale                1
  -up_scale                  2
  -integrate		     false

! Ero=dil and no concat as superficial pores should be kept
                            
/gobj mask "ipl_gobj2

/togobj_from_aim  mask "ipl_gobj0
 -curvature_smooth   5 


! Now the outer mask:
! ------------------

/scale_elsize  seg_cl sca
  -down_scale                2
  -up_scale                  1
  -integrate		     false

! first remove attached trabeculae:
/ero sca ero 2
/cl  ero

/dil ero dil  
  -dilate_distance 	     "dilation_nr 

/bound dil bb
  -z_only                    true
  -border                    0
/ren bb dil                     

/set dil 0 127 

!/write dil "temp_file 
/cl_slicewise_extractow    
  -input_output              dil
  -lo_vol_fract_in_perc      50
  -up_vol_fract_in_perc      100
  -value_in_range            100

/set dil 0 127 

/erosion
  -input                     dil
  -output                    sca
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  2
  -integrate		     false

/concat ero seg_cl out_mask
  -common_region_only false
  -add_not_overlay    false  
 
! to remove 2 first and last gobjs (wrong b/c of the diff betw/ ero and dil):
/bound out_mask bb
  -z_only                    true
  -border                    -2
/ren bb out_mask                     
/write  out_mask "outer_mask

..
$!_________
$ ANALYSIS:
$!---------
$!
$! Now back to the native SEG file (no cl...)
$! In case the D_GOBJs is corrected, we need to make the S_GOBJ and 
$! write the SEGs at this point:
$ IPL_BATCH 

! Surrounding bone:
/gobj_to_aim  "ipl_gobj0  def
/dil def dil  
  -dilate_distance   20 
/subtract dil def sb
/gobj sb "outer_mask  2 ! to remove outer shell from dil_ero
/togobj_from_aim  sb "ipl_gobj1
 -curvature_smooth   5

! Generating correct SEGs:
/read  seg  "ipl_segaim
/set   seg  127 0
/copy  seg  seg0
/gobj  seg0  "ipl_gobj0 "ipl_peel0
/write seg0  "seg_0_file
/set   seg0  50 0

/copy  seg  seg1
/gobj  seg1  "ipl_gobj1 "ipl_peel1
/write seg1  "seg_1_file 
/set   seg1 100 0

/concat seg seg1 temp
  -common_region_only false
  -add_not_overlay    false  
 
/concat temp seg0 seg
  -common_region_only false
  -add_not_overlay    false  
 
/write seg   "ipl_segaim 
..
$!
$  IF 	run_analysis .EQS. "NO"  .OR.  run_analysis .EQS. "N"
$  THEN	
$ 	GOTO ENDCOM
$  ENDIF  
$! 
$!---------------------
$! In Defect VOI:
$!---------------------
$!
$ ipl_segaim = seg_0_file
$ IPL_BATCH 


! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/read seg "ipl_segaim
/db_clear_eval seg
/db_scanco_activate true

/set seg 127 0

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

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out    "ipl_fname0

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                1
  -min_number_pixels         6

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
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
$ UCT_LIST_D:
$! For the New BONE tissue in defect only:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_DEF.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_DEF.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_DEF.TXT
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
$!  
$!---------------------------------------
$! Surrounding bone:
$!---------------------------------------
$!
$  ipl_segaim = seg_1_file
$ IPL_BATCH 


! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/read seg "ipl_segaim
/db_clear_eval seg
/db_scanco_activate true

/set seg 127 0

/vox_scanco_param
  -input                     seg

! apparent density 
/read org "ipl_aim
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

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/tri seg tri
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
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

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out    "ipl_fname0

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                1
  -min_number_pixels         6

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
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
$ UCT_LIST_S:
$! For the surrounding BONE tissue only:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_SUR.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_SUR.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_SUR.TXT
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
$!  
$ ENDCOM:
$	PURGE 'EVAL_DIR'
$ EXIT
