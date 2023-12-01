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
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_GP3.AIM
$	IPL_GOBJ_cart   :=  'DEV''DIR''FILENAME'_cart.GOBJ
$	IPL_GOBJ_spon   :=  'DEV''DIR''FILENAME'_spon.GOBJ
$	ps_mask		:=  'DEV''DIR''FILENAME'_PS_MASK.AIM
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH

/db_scanco_activate true


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

!exit



/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0

/write gau "ipl_aim

! /del org


/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0


/bounding_box_cut
  -input                     gau
  -output                    out
  -z_only                    false
  -border                    1

!/write gau "ipl_aim

!/del gau 

/thres out ps
  -low         		     0  
  -upp	       		     "ipl_lower0
  -value       		     127
  -unit	       		     3 !"ipl_unit0

/thres out gp
 -low         		     "ipl_lower0  
 -upp	       		     1000
 -value       		     127
 -unit	       		     3 !"ipl_unit1

/ren ps seg1
/ren gp seg2

/del out

/write  seg1    "ipl_segaim
  -compress  bin

/write  seg2    "ipl_fname5
  -compress  bin

/del seg1
/del seg2 

! Generate Mask file

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


! Create seperate .GOBJs for both CART and SPON

! For CART: 

/togobj_from_aim
 -input			"ipl_segaim	
 -gobj_filename		"ipl_gobj_cart
 -min_elements              0
 -max_elements              0
 -curvature_smooth          1

! For SPON:

/togobj_from_aim
 -input			"ipl_fname5	
 -gobj_filename		"ipl_gobj_spon
 -min_elements              0
 -max_elements              0
 -curvature_smooth          1



! Analysis of CART:

/read  seg1    "ipl_segaim
  -compress  bin

/db_scanco_activate 	     true   
/db_clear_eval               seg1

/gobj_maskaimpeel_ow
  -input_output              seg1
  -gobj_filename             "ipl_gobj_cart
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg1

/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj_cart
  -peel_iter                 "ipl_peel0
  -region_number 	     0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg1 "ipl_segaim



/gobj_maskaimpeel_ow
  -input_output              seg1
  -gobj_filename             "ipl_gobj_cart
  -peel_iter                 "ipl_peel0

/dt_object
  -input                     seg1
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out    "ipl_fname0

! dt background parameter is unnecessary here

..
$ UCT_LIST_CART:
$! For the CART region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_CART.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_CART.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_CART.TXT
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
$! Analysis of the SPON  region:
$!
$
$!
$ IPL_BATCH 
/read  seg2    "ipl_fname5
  -compress  bin

/db_scanco_activate 	     true

/db_clear_eval               seg2   

/gobj_maskaimpeel_ow
  -input_output              seg2
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 "ipl_peel0

/vox_scanco_param
  -input                     seg2

! apparent density 

/read org "ipl_aim

! tissue (matrix) density of entire volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 "ipl_peel0
  -region_number 	     0



..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg2 "ipl_fname5

/gobj_maskaimpeel_ow
  -input_output              seg2
  -gobj_filename             "ipl_gobj0		! reads the original contour 
  -peel_iter                 "ipl_peel0

/dilation  seg2 seg_dil
  -dilate_distance           "ipl_lower2
  -continuous_at_boundary    0 0 0

/inv seg_dil
/cl seg_dil
/inv seg_dil

/erosion  seg_dil  seg2
  -erode_distance            3
  -use_previous_margin       true      

/write seg2 "ps_mask

/dt_object
  -input                     seg2
  -output                    out
  -gobj_filename             "ipl_gobj0
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

/read seg2 "ipl_fname5

/dt_background
  -input                     seg2
  -output                    out
  -gobj_filename             "ps_mask
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "fname7

!/write  out    "fname6   
..
$ UCT_LIST_SPON:
$! For the SPON region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_SPON.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_SPON.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_SPON.TXT
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
