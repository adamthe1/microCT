$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! For new bone formation (e.g. critical size defects), 2 VOIs based on Thres only
$! ipl_lower1 must be lower than ipl_lower0
$! Attn: seg_0 is low-dens bone (at thres lower1) and seg_1 starts at thres lower0
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	IPL_AIM      :=  'DEV''DIR''FILENAME'.AIM	
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM
$!
$! New bone only (analyzed)   	
$	SEG_0_FILE   :=  'DEV''DIR''FILENAME'_SEG_0.AIM 	
$! Old bone only (for Mask) 
$	SEG_1_FILE   :=  'DEV''DIR''FILENAME'_SEG_1.AIM 
$! Reconstructed multi-object image:
$!	ILP_SEGAIM  
$	MASK_FILE    :=  'DEV''DIR''FILENAME'_MASK.AIM  
$	MASK_T_FILE    :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$!		
$	dilation_nr   =  12
$	erosion_nr    = 'dilation_nr' + 1
$!
$ GOTO ANALYSIS
$! GOTO UCT_LIST_1
$!
$ IF 	F$SEARCH(gau_file) .NES. ""    
$ THEN	
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  "/read gau ""gau_file "
$ ENDIF
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH

/db_scanco_activate true         

! create .AIM file from .ISQ

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       0 0 0
  -dim                       -1 -1 -1
!  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
!  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                          
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gobj org "ipl_gobj0 "ipl_peel0
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

/thres gau seg_0 
  -low 			    "ipl_lower1
  -up			    "ipl_upper1		
  -value                    90
  -unit                     "ipl_unit0

/cl_nr_extract  seg_0  cl
  -min_number               20 !used to be 2000 for bone repair
  -max_number               0
  -value_in_range           90
/copy cl seg_0

!!! PROBLEM !!!
!!! What if there is no xxx_T.GOBJ? 
! If needed, original trabecular bone can be removed by drawing a CCW contour
! of endosteum and name it XXX_T.GOBJ
/gobj  seg_0 "ipl_gobj1  "ipl_peel1 
/subtr cl    seg_0   seg
/ren   seg   seg_0

/thres gau seg_1 
  -low 			    "ipl_lower0
  -up			    "ipl_upper0		
  -value                    100
  -unit                     "ipl_unit1

/cl_nr_extract  seg_1  cl
  -min_number               20 !used to be 2000 for bone repair
  -max_number               0
  -value_in_range           100
/ren cl seg_1

! Dilate seg_1 to mask the 2 vox layer of seg_0 lining seg_1:
/dil seg_1 dil_1  
  -dilate_distance 2 
/set dil_1 100 0

! Here I used the sub command to preserve the thres in seg_0 header: 
/subtract seg_0     dil_1    seg_0_new
/thres	  seg_0_new seg_0
  -low 			    90
  -up			    90		
  -value                    90
  -unit                     5

/concat seg_0 dil_1 seg_all f f

/write seg_all "ipl_segaim

/copy seg_all seg

/set seg_all 127 0
/scale_elsize  seg_all sca
  -down_scale                2
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because seg_hi was Gobj'ed with full.aim 
/set dil 0 127

/cl_slicewise_extractow    
  -input_output              dil
  -lo_vol_fract_in_perc      40
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

/concat ero seg_all mask
  -common_region_only false
  -add_not_overlay    false

! to remove 2 first and last gobjs (wrong b/c of the diff betw/ ero and dil):
/bound mask bb
  -z_only                    true
  -border                    -2
/copy bb temp

! In case we drew an endosteal contour (T.GOBJ), we can remove the bone marrow
! from the total volume. TV will now be the 'original CORT ring':
/gobj  bb  "ipl_gobj1  "ipl_peel1 
/subtr temp bb mask 

/togobj_from_aim  mask "ipl_gobj0
 -curvature_smooth   5

/write mask "mask_file

/gobj  seg_0 "ipl_gobj0 
/write seg_0 "seg_0_file

/gobj  seg_1 "ipl_gobj0 
/write seg_1 "seg_1_file 
 
/gobj  seg   "ipl_gobj0 
/write seg   "ipl_segaim 
..
$!
$! EXIT
$!_________
$ ANALYSIS:
$!---------
$!
$!---------------------
$! All bone:
$!---------------------
$!
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

/read seg "ipl_segaim
/db_scanco_activate true

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
$ UCT_LIST_A:
$! For the entire BONE tissue (All):
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_ALL.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_ALL.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_ALL.TXT
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
$!--------------------------------------------
$! New bone:
$!--------------------------------------------
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
$ UCT_LIST_N:
$! For the New BONE tissue only:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_NEW.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_NEW.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_NEW.TXT
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
$! Old bone:
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
$ UCT_LIST_O:
$! For the Old BONE tissue only:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_OLD.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_OLD.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_OLD.TXT
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
$	PURGE 'EVAL_DIR'
$ EXIT
