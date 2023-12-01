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
$	gobj_full    :=  'DEV''DIR''FILENAME'_F.GOBJ
$	IPL_GOBJ_P   :=  'DEV''DIR''FILENAME'_P.GOBJ
$	IPL_GOBJ_D   :=  'DEV''DIR''FILENAME'_D.GOBJ
$	IPL_GOBJ_S   :=  'DEV''DIR''FILENAME'_S.GOBJ
$	test_aim     :=  'DEV''DIR''FILENAME'_test.aim
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH
  
/db_scanco_activate true

! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  isq
  -isq_filename              "ipl_isq
  -pos 			     0 0 0
  -dim                       -1 -1 -1
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

!
! write VOI to disk (as AIM)
!

! Here ipl_lower should be 1
/thres isq seg
  -low         		     "ipl_lower0  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/del out

/gobj   seg    "gobj_full
/bound  seg bb false  
  -border                    0 0 0
/ren    bb seg
/write  seg    "ipl_segaim
  -compress  bin

! Generate Mask file (for midslice)

/gobj_to_aim
  -gobj_filename             "gobj_full
  -output                    gobj
  -peel_iter                 0

/bounding_box_cut
  -input                     gobj
  -output                    gobj0
  -z_only                    false
  -border                    0 0 0

/write gobj0 "mask_file 
! At this stage, mask_file is the full mask
..
$! Generate Prox and Dist GOBJ:
$! ---------------------------
$ pipe aix 'mask_file' | search sys$pipe "!> dim" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ pipe aix 'mask_file' | search sys$pipe "!> pos" |  -
	(read sys$pipe pos_txt ;  defin/nolog/job poslog &pos_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> dim"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimz = f$element(2," ",dim_clean)
$ sh sym dimz
$ pos_log = f$trnlnm("poslog")
$ pos_log = pos_log - "!> pos"
$ pos_clean = f$edit(pos_log,"COMPRESS, TRIM")
$ sh sym pos_clean
$ posz = f$element(2," ",pos_clean)
$ sh sym posz
$!
$ first_slice =  (dimz * 3 / 4)
$ sh sym first_slice
$!
$ IPL_BATCH 

/read gobj0  "mask_file 
/examine gobj0 geo
/sub_get
  -input                     gobj0
  -output                    gobjs
  -pos                       0 0 "first_slice
  -dim                       -1 -1 -1
  -global_pos_flag           false

/gobj  gobjs  "ipl_gobj0
/examine gobjs geo

/togobj_from_aim
  -input                     gobjs
  -gobj_filename             "ipl_gobj_s
  -min_elements              0
  -max_elements              0
  -curvature_smooth          5

/read seg "ipl_segaim
/gobj seg "ipl_gobj_s
/writ seg "ipl_segaim
..
$! Analysis of a TRAB subregion:
$!
$ ipl_gobj0 = ipl_gobj_s
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
$! EXIT
$ UCT_LIST_T:
$! For the TRAB subregion:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_S'IPL_VOIDZ'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_S'IPL_VOIDZ'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_S'ipl_voidz'.TXT
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
$ ENDCOM:
$ EXIT
