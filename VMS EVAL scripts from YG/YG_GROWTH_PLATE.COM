$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!  ?|?|+.ISQ|+_GP.AIM                                           
$!  |+_GP_SPON.AIM|+_GP_TH_spon.AIM|+_GP_TH_spon.TXT|+_GP_SP_spon.AIM|+_GP_SP_spon.TXT|+_1-OVER-N.TXT
$!  |+_GP_CART.AIM|+_GP_TH_cart.AIM|+_GP_TH_cart.TXT
$!  Growth plate analysis in 2 subregions: 
$!  unmineralized cartilage and primay spongiosa
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")            
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	mask_file    :=  'DEV''DIR''FILENAME'_GP_MASK.AIM
$	gp_gobj      :=  'DEV''DIR''FILENAME'_gp.GOBJ
$	cart_gobj    :=  'DEV''DIR''FILENAME'_cart.GOBJ
$	spon_gobj    :=  'DEV''DIR''FILENAME'_spon.GOBJ
$! Corrected gobjs:
$	c_gobj       :=  'DEV''DIR''FILENAME'_c.GOBJ
$	s_gobj       :=  'DEV''DIR''FILENAME'_s.GOBJ
$	c1_gobj       :=  'DEV''DIR''FILENAME'_c1.GOBJ
$	s1_gobj       :=  'DEV''DIR''FILENAME'_s1.GOBJ
$	c2_gobj       :=  'DEV''DIR''FILENAME'_c2.GOBJ
$	s2_gobj       :=  'DEV''DIR''FILENAME'_s2.GOBJ
$       cart_sm         :=  'DEV''DIR''FILENAME'_GP_CART_SM.AIM
$       spon_sm		:=  'DEV''DIR''FILENAME'_GP_SPON_SM.AIM
$!
$	ipl_gobj_cart = cart_gobj 
$	ipl_gobj_spon = spon_gobj 
$!
$	ipl_voiz = ipl_voiz - 10
$	ipl_voidz = ipl_voidz + 20
$!
$! GOTO SPON_ANALYSIS
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
!/read gau "ipl_aim

!/del org


/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/bounding_box_cut
  -input                     gau
  -output                    out
  -z_only                    false
  -border                    1
             
/del gau

/thres out cart                                                           
  -low         		     0  
  -upp	       		     "ipl_lower0
  -value       	     	     127
  -unit	       		     "ipl_unit0 
                                                                                                                                                      
/gobj
  -input_output              cart
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/thres out spon
 -low         		     "ipl_lower0  
 -upp	       		     "ipl_upper0
 -value       		     127
 -unit	       		     "ipl_unit0
/del out
 
/gobj
  -input_output              spon
  -gobj_filename             "ipl_gobj0
  -peel_iter                 1
 

!!! Here in 2018 there was an error as seg1 is cart written as ipl_segaim
!!! ("SPON")
! Oct 2019, corrected
/write  spon    "ipl_segaim
  -compress  bin

/write  cart    "ipl_fname5
  -compress  bin
!!! For testing only: !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!/togobj_from_aim  cart "c1_gobj
! -curvature_smooth   5
!/togobj_from_aim  spon "s1_gobj
! -curvature_smooth   5
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   
! seg1 (cartilage) smoothing:

!!! If CART is narrow, total nr of components might be <8000
!!! Consider using min_nr = 2000 or less
/cl_nr_extract cart cl
 -min_number		     4000 
/ren cl cart

!/dil cart dil
!  -dilate_distance           3
!/ero dil cart_mask_de
!  -erode_distance            3
!  -use_previous_margin       false
!/set cart_mask_de        127 0

/set cart                127 0

!!
!/togobj_from_aim  cart_mask_de "cart_gobj
! -curvature_smooth   5
!!
!/gobj  cart "cart_gobj  

!!! The cart_sm is the best for GOBJ  !!!

/gauss_seg cart cart_sm 
  -sigma                     3
  -support                   3
  -lower_in_perm_aut_al      400
  -upper_in_perm_aut_al      1000
  -value_in_range            127
  -unit                      6

/write cart_sm "cart_sm            
/gobj  cart    "cart_sm
!/write cart    "ipl_fname5     !!! not final yet. see end.

!!! For testing: !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/togobj_from_aim  cart "c2_gobj
 -curvature_smooth   5
/togobj_from_aim  cart_sm "c1_gobj
 -curvature_smooth   5
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!! NEW:
!!! If SPON is narrow, total nr of components might be <8000
!!! Consider using min_nr = 500 or less
/write cart    "ipl_fname5
/subt  spon cart_sm new_spon
/thres new_spon spon  127 127 127 
  -unit			     5 

!--------------------------------------------------------------------------
!!! CLEANING OF FALSE 'SPON' ACROSS CART
!!! Assuming the CART is higher (Y axis, e.g. humerus), we will shift it up 
!!! to erase false "spon" from epiphyseal side (values should be -)
!!! Use positive values for cart at the bottom (e.g. femur):
/copy cart_sm eraser
/set eraser 1 0
/concat spon eraser out f f f 
  -shift_ofin2		     0  0 0  
/concat out  eraser out2 f f f 
  -shift_ofin2		     0  2 0 
/concat out2  eraser out f f f 
  -shift_ofin2		     0  4 0  
/concat out  eraser out2 f f f 
  -shift_ofin2		     0  6 0  
/concat out2  eraser out  f f f 
  -shift_ofin2		     0  8 0  
/thres  out   spon_mask  127 127 127 
  -unit			     5  
!--------------------------------------------------------------------------

/cl_nr_extract spon_mask cl
  -min_number		     1000 
/ren cl spon_mask         

!!! For normal SPON, use sigma=3 and Thres=450
!!! For thinner SPON, use 2 or 1 and Thres=400
/gauss_seg spon_mask spon_sm 
  -sigma                     1.2
  -support                   1
  -lower_in_perm_aut_al      400
  -upper_in_perm_aut_al      1000
  -value_in_range            127
  -unit                      6

/write spon_sm "spon_sm            
!/gobj  spon    "spon_sm

/togobj_from_aim  spon_sm "spon_gobj
 -curvature_smooth   5

!!! Use spon here (and not spon_sm) b/c of the porosity in the spon
/gobj  spon "spon_gobj  

/write spon    "ipl_segaim
  -compress  bin

!!! Here, spon is final and written as ipl_segaim;
!!! spon_mask is final and written as spon_gobj

!---------------------------------------------------------------------------
!!! IF NEEDED ONLY:
! Now redo the same eraser trick for 'cart' mistakes
!!! CLEANING OF CART ACROSS SPON
!!! Assuming the SPON is lower (Y axis, e.g. humerus), we will shift it down 
!!! to erase false "cart" from 2ry spongiosa side  (values should be +)
!!! Use negative values for spon on top (e.g. femur):
/copy spon eraser
/set eraser 1 0
/concat cart eraser out f f f 
  -shift_ofin2		     0  0 0  
/concat out  eraser out2 f f f 
  -shift_ofin2		     0  -2 0 
/concat out2  eraser out f f f 
  -shift_ofin2		     0  -4 0  
/concat out  eraser out2 f f f 
  -shift_ofin2		     0  -6 0  
/concat out2  eraser out  f f f 
  -shift_ofin2		     0  -8 0  
/thres  out   cart_mask  127 127 127 
  -unit			     5  
/cl_nr_extract cart_mask cl
  -min_number		 1000 
/ren cl cart_mask         

! Here out=cart_mask are the CART outer contour only without mistakes across the SPON
! Unlikely to include mineralized tissue from the epiph cortex b/c of the segmentation 
!----------------------------------------------------------------------------

! The optimal contours are the sm forms:
/write cart_sm "cart_sm 
/ren   cart_sm  cart_mask
/write spon_sm "spon_sm 
/ren   spon_sm  spon_mask

! Make a mask with both combined and isolate cart after concat:
/set cart_mask 50 0
/concat cart_mask spon_mask new_gobj0        f f 
/togobj_from_aim  new_gobj0 "gp_gobj
 -curvature_smooth   5 
/write  new_gobj0 "mask_file

/thres  new_gobj0 cart_mask 50 50 127 
  -unit			     5  
/togobj_from_aim  cart_mask "cart_gobj
 -curvature_smooth   5     
/gobj  cart "cart_gobj 0
/write cart "ipl_fname5

/set new_gobj0 127 0
/togobj_from_aim  new_gobj0 "gp_gobj
 -curvature_smooth   5 
..
$! EXIT
$ GOTO ANALYSIS
$! GOTO ENDCOM
$!===========================================================
$ ANALYSIS:
$! ANALYSIS OF CART:
$ IPL_BATCH

/read  cart    "ipl_fname5  ! No point in using cart_sm 
  -compress  bin

/db_scanco_activate 	     true   
/db_clear_eval               cart

/gobj_maskaimpeel_ow
  -input_output              cart
  -gobj_filename             "ipl_gobj_cart
  -peel_iter                 0

/vox_scanco_param
  -input                     cart

/read org "ipl_aim

/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj_cart
  -peel_iter                 0
  -region_number 	     0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read cart "ipl_fname5
/read cart_sm "cart_sm
/add_aims
  -input1                    cart
  -input2                    cart_sm
  -output                    out
/ren out cart_sm
/dt_object
  -input                     cart_sm
  -output                    out
  -gobj_filename             "cart_sm
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname7

/write  out "ipl_fname6

!/dt_background
!  -input                     seg1
!  -output                    out
!  -gobj_filename             "ipl_gobj_cart
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       

!/write  out    "ipl_fname2   
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
$ SPON_ANALYSIS:
$!
$ IPL_BATCH 
/read  spon    "ipl_segaim

/db_scanco_activate 	     true

/db_clear_eval               spon   

/gobj_maskaimpeel_ow
  -input_output              spon
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 0

/vox_scanco_param
  -input                     spon

! apparent density 

/read org "ipl_aim

! Bone density of entire volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 0
  -region_number 	     0

! tissue (matrix) density of thresholded volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 0
  -region_number 	     1

..
$ ON ERROR THEN EXIT 
$ IPL_BATCH

/db_scanco_activate true

!/read seg2 "ipl_segaim
/read spon_sm "spon_sm

/dt_object
  -input                     spon_sm
  -output                    out
  -gobj_filename             none
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write  out  "ipl_fname0

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg2 "ipl_segaim

/dt_background
  -input                     seg2
  -output                    out
  -gobj_filename             "ipl_gobj_spon
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write  out    "ipl_fname2   
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
$!-------------------------------------------
$! Analysis of the combined GP region:
$!
$ GP_ANALYSIS:
$!
$ IPL_BATCH 
/read  gp    "mask_file

/db_scanco_activate 	     true

/db_clear_eval               gp   

/gobj_maskaimpeel_ow
  -input_output              gp
  -gobj_filename             "gp_gobj
  -peel_iter                 0

/vox_scanco_param
  -input                     gp

! apparent density 

/read org "ipl_aim

! Mineral density of entire volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gp_gobj
  -peel_iter                 0
  -region_number 	     0

! tissue (matrix) density of thresholded volume (same as previous)
!/voxgobj_scanco_param
!  -input                     org
!  -gobj_filename             "ipl_segaim
!  -peel_iter                 0
!  -region_number 	     1

..
$ ON ERROR THEN EXIT 
$ IPL_BATCH

/db_scanco_activate true

!/read seg2 "ipl_segaim
/read gp "mask_file

/dt_object
  -input                     gp
  -output                    out
  -gobj_filename             none
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write  out  "ipl_fname4

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate true

!/read seg2 "ipl_segaim

!/dt_background
!  -input                     seg2
!  -output                    out
!  -gobj_filename             "ipl_gobj_spon
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname2

!/write  out    "ipl_fname3   
..
$ UCT_LIST_GP:
$! For the combined GP region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_GP.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_GP.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_GP.TXT
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
$!-------------------------------------------
$!
$! Delete old files:
$	mask_file    :=  'DEV''DIR''FILENAME'_MASK_GP.AIM
$	mask_gobj    :=  'DEV''DIR''FILENAME'_MASK_GP.GOBJ
$	cart_gobj    :=  'DEV''DIR''FILENAME'_cart.GOBJ
$	spon_gobj    :=  'DEV''DIR''FILENAME'_spon.GOBJ
$	out_gobj	:=  'DEV''DIR''FILENAME'_out.GOBJ
$	ps_mask		:=  'DEV''DIR''FILENAME'_PS_MASK.AIM
$       gp_full         :=  'DEV''DIR''FILENAME'_GP_FULL.AIM
$       cart_sm         :=  'DEV''DIR''FILENAME'_GP_CART_SM.AIM
$       spon_sm		:=  'DEV''DIR''FILENAME'_GP_SPON_SM.AIM
$ DEL/NOCONFIRM  'mask_file';*
$ DEL/NOCONFIRM  'mask_gobj';*
$ DEL/NOCONFIRM  'out_gobj';*
$ DEL/NOCONFIRM  'ps_mask';*
$ DEL/NOCONFIRM  'gp_full';* 
$ DEL/NOCONFIRM  'c1_gobj';* 
$ DEL/NOCONFIRM  'c2_gobj';* 
$ DEL/NOCONFIRM  's1_gobj';* 
$ DEL/NOCONFIRM  's2_gobj';* 
$ PURGE 'DEV''DIR''FILENAME'*.AIM
$ PURGE 'DEV''DIR''FILENAME'*.GOBJ
$ PURGE 'DEV''DIR''FILENAME'*.TXT
$ ENDCOM:
$ EXIT
