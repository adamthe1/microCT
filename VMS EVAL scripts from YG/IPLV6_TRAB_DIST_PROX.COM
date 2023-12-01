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
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	IPL_GOBJ_P   :=  'DEV''DIR''FILENAME'_P.GOBJ
$	IPL_GOBJ_D   :=  'DEV''DIR''FILENAME'_D.GOBJ

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

exit
/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0

/write gau "ipl_aim
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

/del gau

/thres out seg
  -low         		     "ipl_lower0  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/del out

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

/write gobj0 "mask_file 
..
$! Generate Prox and Dist GOBJ:
$! ---------------------------
$ pipe aix 'mask_file' | search sys$pipe "!> dim" |  -
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

/read gobj0  "mask_file 

/sub_get
  -input                     gobj0
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
  -input                     gobj0
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
$!
$ ipl_gobj0 = mask_file
$!
$ IPL_BATCH 

/read  seg    "ipl_segaim
  -compress  bin

/db_scanco_activate 	     true
/db_clear_eval               seg   

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
..
$! Analysis of the Proximal region:
$!
$ ipl_gobj0 = ipl_gobj_p
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim
  -compress  bin

/db_clear_eval               seg   

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
$ ipl_gobj0 = ipl_gobj_d
$!
$ IPL_BATCH 

/db_scanco_activate 	     true

/read  seg    "ipl_segaim
  -compress  bin

/db_clear_eval               seg   

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
$ ENDCOM:
$ EXIT
