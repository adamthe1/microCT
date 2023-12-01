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
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_GP.AIM
$	mask_gobj    :=  'DEV''DIR''FILENAME'_MASK_GP.GOBJ
$	IPL_GOBJ_cart   :=  'DEV''DIR''FILENAME'_cart.GOBJ
$	IPL_GOBJ_spon   :=  'DEV''DIR''FILENAME'_spon.GOBJ
$	out_gobj	:=  'DEV''DIR''FILENAME'_out.GOBJ
$	ps_mask		:=  'DEV''DIR''FILENAME'_PS_MASK.AIM
$       gp_full         :=  'DEV''DIR''FILENAME'_GP_FULL.AIM
$       seg1_sm         :=  'DEV''DIR''FILENAME'_GP_SEG1_SM.AIM
$       seg2_sm		:=  'DEV''DIR''FILENAME'_GP_SEG2_SM.AIM
$!
$	ipl_voiz = ipl_voiz - 10
$	ipl_voidz = ipl_voidz + 20
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


/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0

/write gau "ipl_aim

!/del org


/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

!/thres gau gau1 0 1000 127 0 


/bounding_box_cut
  -input                     gau
  -output                    out
  -z_only                    false
  -border                    1
             
/del gau

/thres out gp                                                           
  -low         		     0  
  -upp	       		     "ipl_lower0
  -value       	     	     127
  -unit	       		     "ipl_unit0 
 
/gobj
  -input_output              gp
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/thres out ps
 -low         		     "ipl_lower0  
 -upp	       		     1000
 -value       		     127
 -unit	       		     "ipl_unit0
/del out
 
/gobj
  -input_output              ps
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0



/ren gp seg1
/ren ps seg2

/write  seg1    "ipl_segaim
  -compress  bin

/write  seg2    "ipl_fname5
  -compress  bin






! seg1 (cartilage) smoothing:

/gauss_seg seg1 seg1_er 
  -sigma                     2
  -support                   2
  -lower_in_perm_aut_al      450
  -upper_in_perm_aut_al      1000
  -value_in_range            127
  -unit                      6

/write seg1_er "seg1_sm            



! seg2 (spon) smoothing:

/gauss_seg seg2 seg2_er 
  -sigma                     2
  -support                   2
  -lower_in_perm_aut_al      450
  -upper_in_perm_aut_al      1000
  -value_in_range            127
  -unit                      6

/write seg2_er "seg2_sm            




/del seg1
!/del seg2 

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

/cl seg1_er  
  -first_rank                1
  -last_rank                 1
  -connect_boundary          false
  -value_in_range            127

/togobj_from_aim
 -input			    seg1_er 	! smoothed aim object (cart) is used
 -gobj_filename		    "ipl_gobj_cart                         
 -min_elements              0
 -max_elements              0
 -curvature_smooth          5

/write seg1_er "seg1_sm 
  

! For SPON:                 

! SPON mask

/read gau "ipl_aim
/thres gau seg
  -low         		     "ipl_lower0
  -upp	       		     1000
  -value       		     127
  -unit	       		     "ipl_unit0 
/del gau
 
/dilation
  -input                     seg
  -output                    dilp1
  -dilate_distance           10

! Here, the VOI box cut at a clean ring (for masking)
/bounding_box_cut dilp1 dil
  -z_only true
  -border 0

/del dilp1

/invert dil
/cl dil
/invert dil

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            12
  -use_previous_margin       true

/bounding_box_cut  ero ero_bb
  -z_only false
  -border 2

/concat ero_bb seg mask
  -common_region_only false
  -add_not_overlay    false

/togobj_from_aim  mask "out_gobj
 -curvature_smooth   5

/gobj gobj    "out_gobj
  -peel_iter         10        
/gobj seg1_er "out_gobj
  -peel_iter         10  

/subtract gobj seg1_er spon

! To remove the epiphyseal bone spickles:
/cl spon
  -first_rank                1
  -last_rank                 1
  -connect_boundary          false
  -value_in_range            127

/write spon "ps_mask
/togobj spon "ipl_gobj_spon

/gobj seg2 "ps_mask

/concat seg1_er spon gobj
/write gobj "mask_file
/togobj_from_aim
 -input			    gobj	! concatenated smoothed aims
 -gobj_filename		    "mask_gobj
 -min_elements              0
 -max_elements              0
 -curvature_smooth          5

! ..
! $ EXIT
! $ !ANALYSIS OF CART:

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
/read seg1_er "seg1_sm






/dt_object
  -input                     seg1
  -output                    out
  -gobj_filename             seg1_er

  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname7

/write  out "ipl_fname6



!/dt_background
  -input                     seg1
  -output                    out
  -gobj_filename             "ipl_gobj_cart
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2   
..
$ UCT_LIST_CART:
$! For the SPON region:
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
/read seg2_er "seg2_sm


/gobj_maskaimpeel_ow
  -input_output              seg2
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 "ipl_peel0

/write seg2 "ipl_fname5

/dt_object
  -input                     seg2
  -output                    out
  -gobj_filename             seg2_er
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out  "ipl_fname0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg2 "ipl_fname5


/dt_background
  -input                     seg2
  -output                    out
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname2

/write  out    "ipl_fname3   
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

$ IPL_BATCH


/read seg1 "seg1_sm

/read seg2 "ipl_fname5
/set seg1 1 0
/set seg2 127 0 
/conca seg1 seg2 out

 -common_region_only        false
 -add_not_overlay           false
 -make_edge                 false
 -shift_ofin2               0 0 0 
 -turnangle                 0
 -turnpoint_global          -1 -1


/write out "gp_full  

..




$ ENDCOM:
$ EXIT

