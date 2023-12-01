$!------------------------------------------------------------------------------
$!	IPL_THRE_SUBMIT_ALL.COM
$!------------------------------------------------------------------------------
$!
$!	Image processing on scanned and gaussfiltered data for the evaluation
$!	of TITANIUM IMPLANT OSSEOINTEGRATION
$!
$!------------------------------------------------------------------------------
$!
$!	Input : 	.ISQ
$!
$!	also needed: 	*f.gobj
$!		     	*t.gobj
$!
$!	Output: *_THRES_SUB.AIM	  (Thresholded image of Implant, OI surface,
$!				   Bone and Background)
$!
$!	Usage:
$!		@SUBMIT_ALL_IPL  THRES  'p2'
$!
$!	Note: 'p2' must be part of a GFILT-filename in MODELS-directory 
$!	      If 'p2' = "" all the samples will be submitted
$!
$!------------------------------------------------------------------------------
$	ipl_isq  = P1
$	FILENAME	= F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV		= F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR		= F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!	
$	NAME		:= 'DEV''DIR''FILENAME'
$	FNAME		:= 'DEV''DIR''FILENAME'_F
$	TNAME		:= 'DEV''DIR''FILENAME'_T
$!
$!	"Common part of filename:"
$	SHOW SYM NAME
$	SHOW SYM FNAME
$	SHOW SYM TNAME
$!	
$!------------------------------------------------------------------------------
$!
$!	For testing:
$!	stepto		: Position to jump to in this file. 
$!			  Skips the first part of the calculations.
$!
$	stepto 		= "POSITION_01" 
$!                         
$!-------------------------------
$!
$       tres_up  	=100000 !  ipl_upper0 	! Max gray values
$       tres_imp  	= 10000 !  ipl_lower0 	! Implant
$       tres_boi  	=  5000 !  ipl_lower1	! was 6000 OI bone
$       tres_b1oi  	=  5200 !  ipl_lower1 	! was 5000 next to OI bone
$       tres_b1  	=  5300 !  ipl_lower2	! was 5300 Bone1 from 1st to 2nd layer
$       tres_b2  	=  4300 !  ipl_lower3	! was 4600 Bone2 from 2nd to 3rd layer
$	tres_b3		=  3500 !  ipl_lower4	! Bone3 w/o artifacts
$!
$!  Define the three scattering-affected layers:
$	impl_dilat_1 	=  1  !! maybe incr to 2 and correct impl_dilat to 2
$	impl_dilat_2 	=  4  ! was 5
$	impl_dilat_3 	= 15  ! was 20
$!			
$!  Define the PIB VOI:
$	impl_dilat_4 	= 100   !!! PIB is measured at up to 2 mm radially
$!                      
$!  Removing int voids:
$       impl_dil1 	= 1
$       impl_ero1 	= 2
$!
$!  Implant smoothening (gau_seg):
$	impl_sup 	= 2
$       impl_sig 	= "2"
$	impl_th 	= 400
$!			Should be less than 500
$!
$	impl_cl 	= 1
$!
$	impl_ero_dil    = 2
$!
$!  Implant: obliterate threads:
$	impl_close 	= 20
$!
$!  Surfoi smoothening by growing out from bone1:
$	bone1_erosi_dilat 	= 1
$!
$!  PIB smoothening for figures (gau_seg):
$	bone_sup 	= 1
$	bone_sig 	= "1.2"
$	bone_th  	= 450
$!
$!  Set values:
$	col_impl   	= 120
$	col_bone1  	=  80
$	col_bone2  	=  70
$	col_bone3  	=  50
$	col_bone   	=  60              
$	col_surf	=  40
$!	col_marrow 	=  30
$!
$	offset		=   0
$!
$!------------------------------------------------------------------------------
$!	TO LAUNCH NEW VERSION OF IPL:
$!	=============================
$!
$ 	ON ERROR THEN EXIT
$!   	ipl_scanco_prog := IPL_BATCH
$!
$!------------------------------------------------------------------------------
$!	Skip first part of the file?
$!	============================
$!	'stepto' is a given POSITION
$	GOTO 'stepto'
$!
$!-----------------------------------------------------------------------------
$  POSITION_01:
$!
$!	Extract the implant (IMPLF is for full implant)
$!	===================
$!
$   	gau_file  := 'FNAME'_GFILT.AIM
$   	imp_file  := 'FNAME'_IMPLF.AIM
$!   	imco_file := 'NAME'_I_MASK.AIM
$	test1    := 'FNAME'_TEST1.AIM
$	test2    := 'FNAME'_TEST2.AIM
$	test3    := 'FNAME'_TEST3.AIM
$	temp     := 'FNAME'_TEMP.AIM
$!
$	show sym    gau_file
$!	show sym    imp_file
$!
$ 	IPL_BATCH

	/db_scanco_activate false

!	/isq_to_aim
!	  -aim_name          aim
!	  -isq_filename      "ipl_isq
!	  -pos               "ipl_voix "ipl_voiy "ipl_voiz
! 	  -dim               "ipl_voidx "ipl_voidy "ipl_voidz        

/read aim "p2

	/gau aim inp
	  -sigma		"ipl_sigma0
	  -support		"ipl_support0
/del aim 
/write inp "gau_file

!/read inp "gau_file

	/thres
	  -input		inp
	  -output		implant
	  -lower_in_perm	"tres_imp
	  -upper_in_perm	100000
	  -value_in_range	127
	  -unit	      		5
/del inp
!!! create box with original dimensions:
/copy implant box
/set box 127 127
/write box "temp

	/cl implant
	/bounding_box_cut
	  -input                implant
	  -output               imp_mask
	  -z_only               false
	  -border               5	

! 	Remove voids inside implant
!	---------------------------

/dilation
  -input                     imp_mask
  -output                    dil1
  -dilate_distance           "impl_dil1
  -up_scale                  1
  -integrate		     false

/bounding_box_cut dil1 dil
  -z_only false
  -border 0
  
/del dil1

/invert dil
/cl dil
/invert dil

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            "impl_ero1
  -use_previous_margin       false
/del dil

/concat ero imp_mask mask
  -common_region_only false
  -add_not_overlay    true

!/write mask "test3
/ren mask impl

! 	Smoothing by Gaussian filtration of the solid implant ("impl")
!	--------------------------------------------------------------

	/gauss_seg
	  -input		impl
	  -output		impl_sm
	  -sigma		"impl_sig
	  -support		"impl_sup
	  -lower_in_perm	"impl_th
	  -upper_in_perm	1000
	  -value_in_range	"col_impl


!	Smoothing by erosion-dilation
!	-----------------------------

	/erosion   impl_sm  ero                
	  -erode_distance       "impl_ero_dil
	  -use_previous_margin  false

	/dilation  ero  impl_sm            
	  -dilate_distance       "impl_ero_dil
	  -use_previous_margin  true

	/write impl_sm "imp_file
..
$!
$  EXIT
$!
$  POSITION_02:
$!	=========================================
$!			MASKS
$!	=========================================
$!
$!	create and write inverted implant (impli)
$!	=========================================
$!
$   	implf_file	:= 'FNAME'_IMPLF.AIM
$   	impli_file	:= 'FNAME'_IMPLI.AIM
$	cort_gobj	:= 'FNAME'.GOBJ
$!
$   	IPL_BATCH

	/db_scanco_activate false

	/read 
	  -name 		implf 
	  -filename 		"implf_file
	/set implf 127 0
	
	/read box "temp
	/set box 10 10  
	
	/concat
	  -input1		box
	  -input2		implf
	  -output		impl
	  -common_region_only	false
	  -add_not_overlay	true
                                      
	/absolute_threshold
	  -input 		impl 	
	  -output		implf	
	  -lower_in_abs		120
	  -upper_in_abs		127	
	  -value_in_range	127	   

	/write
	  -name 		implf 
	  -filename 		"implf_file
	
/set implf 0 100
	/ren implf impli

	/gobj_maskaimpeel_ow 
	  -input_output		impli 
	  -gobj_filename	"cort_gobj
	  -peel_iter		0

	/write
	  -name 		impli 
	  -filename 		"impli_file

	..
$!-------------------------------------------------------------------------
$!  At this point, we have an implant MASK (implf) and its negative (impli)
$!  Note: impli comprises only contoured structures.
$!-------------------------------------------------------------------------
$!
$!
$  POSITION_03:
$!
$!     Create and write: MaskOI, Mask_1, Mask_2, Mask_3 (PIB) and Mask_4 (w/cortex)
$!	=================================================================
$!
$  	implf_file 	:= 'FNAME'_IMPLF.AIM
$  	impli_file 	:= 'FNAME'_IMPLI.AIM
$   	impld1_file	:= 'FNAME'_IMPLD1.AIM
$   	impld2_file	:= 'FNAME'_IMPLD2.AIM
$   	impld3_file	:= 'FNAME'_IMPLD3.AIM
$   	impld4_file	:= 'FNAME'_IMPLD4.AIM
$	mask_1_file	:= 'FNAME'_MASK_1.AIM
$	mask_2_file	:= 'FNAME'_MASK_2.AIM
$	mask_3_file	:= 'FNAME'_MASK_3.AIM
$	maskpit_file	:= 'FNAME'_MASKPIT.AIM
$	maskpic_file	:= 'FNAME'_MASKPIC.AIM
$	maskoi_file	:= 'FNAME'_MASKOI.AIM
$	maskoit_file	:= 'FNAME'_MASKOIT.AIM
$	maskoic_file	:= 'FNAME'_MASKOIC.AIM
$	cort_gobj	:= 'FNAME'.GOBJ
$	trab_gobj	:= 'TNAME'.GOBJ
$	cort_mask	:= 'FNAME'_MASK_C.AIM
$!
$ 	IPL_BATCH

	/db_scanco_activate false

	/read 
	  -name 		implf 
	  -filename 		"implf_file

	/dilation  implf impld1            
	  -dilate_distance      "impl_dilat_1

! First obliterate threads of implants and then make other masks
	/dilation  implf  dil           
	  -dilate_distance      "impl_close
	  -use_previous_margin  false
	/erosion   dil  closed                
	  -erode_distance       "impl_close
	  -use_previous_margin  false

	/dilation  closed impld2            
	  -dilate_distance      "impl_dilat_2
	/dilation  closed impld3            
	  -dilate_distance      "impl_dilat_3

/dilation  closed impld4_big            
  -dilate_distance      "impl_dilat_4

/gobj_maskaimpeel_ow 
  -input_output		     impld4_big 
  -gobj_filename	     "cort_gobj
  -peel_iter		     0

/bounding_box_cut impld4_big impld4  
  -z_only false
  -border 5 5 0 
  
/write impld4 "impld4_file


	/set_val 
	  -input		implf
	  -value_object		10 
	  -value_background	0

	/set_val 
	  -input		impld1
	  -value_object		20 
	  -value_background	0

	/set_val 
	  -input		impld2
	  -value_object		30 
	  -value_background	0

 	/set_val 
	  -input		impld3
	  -value_object		40 
	  -value_background	1

	/concat
	  -input1		implf
	  -input2		impld1
	  -output		fd1
	  -common_region_only	false
	  -add_not_overlay	true
                                      
	/concat
	  -input1		fd1
	  -input2		impld2
	  -output		fd1d2
	  -common_region_only	false
	  -add_not_overlay	true

	/concat
	  -input1		fd1d2
	  -input2		impld3
	  -output		fd1d2d3
	  -common_region_only	false
	  -add_not_overlay	true

	/gobj_maskaimpeel_ow 
	  -input_output		fd1d2d3 
	  -gobj_filename	"cort_gobj
	  -peel_iter		0

	/concat
	  -input1		fd1d2d3
	  -input2		implf
	  -output		ffd1d2d3
	  -common_region_only	false
	  -add_not_overlay	true

       /bounding_box_cut ffd1d2d3  fd1d2d3 
	  -z_only false
	  -border 5 5 0 

/del impld1
/del impld2
/del impld3
/del fd1
/del fd1d2
/del ffd1d2d3  

! Here, create bone masks w/ cortex for sequential segmentation (masks 1,2,3&4):

/absolute_threshold
  -input 		fd1d2d3 	
  -output		mask_1	
  -lower_in_abs		70
  -upper_in_abs		70
  -value_in_range	127

/write
  -name 		mask_1 
  -filename 		"mask_1_file

/absolute_threshold
  -input 		fd1d2d3 	
  -output		mask_2	
  -lower_in_abs		40
  -upper_in_abs		40	
  -value_in_range	127
	   
/write
  -name 		mask_2 
  -filename 		"mask_2_file

/absolute_threshold
  -input 		fd1d2d3 	
  -output		mask_3	
  -lower_in_abs		1
  -upper_in_abs		1
  -value_in_range	127

/write mask_3 "mask_3_file

/del mask_1
/del mask_2
/del mask_3

! Then, create masks for regional analysis

	/gobj_to_aim               
	  -gobj_filename        "cort_gobj     
	  -output               mask_out
	  -peel_iter            0

	/gobj_to_aim               
	  -gobj_filename        "trab_gobj     
	  -output               trab_mask
	  -peel_iter            0

	/set mask_out  10 0
	/set trab_mask 20 0
	
	/concat
	  -input1		mask_out
	  -input2		trab_mask
	  -output		masks
	  -common_region_only	false
	  -add_not_overlay	true

	/del mask_out
	/del trab_mask

	/absolute_threshold
	  -input 		masks	
	  -output		cort_mask	
	  -lower_in_abs		10
	  -upper_in_abs		10
	  -value_in_range	127
		
	/del masks
	/write
	  -name 		cort_mask 
	  -filename 		"cort_mask

	/absolute_threshold
	  -input 		fd1d2d3 	
	  -output		maskoi	
	  -lower_in_abs		90
	  -upper_in_abs		90
	  -value_in_range	127
	
	/write
	  -name 		maskoi 
	  -filename 		"maskoi_file

	/gobj_maskaimpeel_ow 
	  -input_output		maskoi 
	  -gobj_filename	"trab_gobj
	  -peel_iter		5

	/write
	  -name 		maskoi 
	  -filename 		"maskoit_file

	/absolute_threshold
	  -input 		fd1d2d3 	
	  -output		maskoic	
	  -lower_in_abs		90
	  -upper_in_abs		90
	  -value_in_range	127
	
	/gobj_maskaimpeel_ow 
	  -input_output		maskoic 
	  -gobj_filename	"cort_mask
	  -peel_iter		0

	/write
	  -name 		maskoic 
	  -filename 		"maskoic_file

	/gobj_maskaimpeel_ow 
	  -input_output		fd1d2d3 	
	  -gobj_filename	"impld4_file
	  -peel_iter		0

	/absolute_threshold
	  -input 		fd1d2d3 	
	  -output		maskpi	
	  -lower_in_abs		1
	  -upper_in_abs		90
	  -value_in_range	127
	
	/gobj_maskaimpeel_ow 
	  -input_output		maskpi 
	  -gobj_filename	"trab_gobj
	  -peel_iter		5

	/write
	  -name 		maskpi 
	  -filename 		"maskpit_file

	/absolute_threshold
	  -input 		fd1d2d3 	
	  -output		maskpic	
	  -lower_in_abs		1
	  -upper_in_abs		90
	  -value_in_range	127
	
	/gobj_maskaimpeel_ow 
	  -input_output		maskpic 
	  -gobj_filename	"cort_mask
	  -peel_iter		0

	/write
	  -name 		maskpic 
	  -filename 		"maskpic_file
	..
$!
$!---------------------------------------------
$!  At this point, we have all the needed masks
$!---------------------------------------------
$!
$!  EXIT
$  POSITION_04:
$!
$!	Bone image OI ('Severely scattered' bone in contact with implant)
$!	Bone image 1  ('highly scattered' bone) 
$!	Bone image 2  ('mildly scattered' bone) 
$!	Bone image 3  ('non scattered' bone) 
$!
$!	After this step, Bone 1 is all the bony structures, with high threshold 
$!	+ the scattering ring to be replaced by bone dilated out from adjacent bone
$!	===========================================================================
$!
$   	gau_file	:= 'FNAME'_GFILT.AIM
$   	surfoi_file	:= 'FNAME'_SURFOI.AIM
$   	impli_file	:= 'FNAME'_IMPLI.AIM
$   	test_file	:= 'FNAME'_test_oi.AIM
$   	maskoi_file	:= 'FNAME'_MASKOI.AIM
$   	maskoic_file	:= 'FNAME'_MASKOIC.AIM
$!
$   	IPL_BATCH

	/db_scanco_activate false

!	Mask the implant out (replaced in AIM by zero)
!	Note: impli is more appropriate than "mask_1 + maskoi" 
!	------------------------------------------------------

	/read
	  -name 		gau 
	  -filename 		"gau_file

	/gobj_maskaimpeel_ow 
	  -input_output		gau 
	  -gobj_filename	"impli_file
	  -peel_iter		0

!	Extract bone OI (with OI threshold)
!	-----------------------------------

	/thres
	  -input		gau
	  -output		surfoi
	  -lower_in_perm	"tres_boi
	  -upper_in_perm	100000
	  -value_in_range	"col_surf
	  -unit	       		5


!	Extract bone 1oi (for ero_dilat only)
!	-------------------------------------

	/thres
	  -input		gau
	  -output		bone1oi
	  -lower_in_perm	"tres_b1oi
	  -upper_in_perm	100000
	  -value_in_range	"col_surf
	  -unit			5
/del gau

	/gobj_maskaimpeel_ow 
	  -input_output		bone1oi 
	  -gobj_filename	"mask_1_file
	  -peel_iter		0

	/concat
	  -input1		surfoi
	  -input2		bone1oi
	  -output		bone1_oi
	  -common_region_only	false
	  -add_not_overlay	false

	/bounding_box_cut bone1_oi surfoi
	  -z_only false
	  -border 10 10 0

!	Keep only surfoi attached to adjacent bone (erosion-dilation) !!!! Don't skip 
!	-------------------------------------------------------------  

	/erosion   surfoi  ero                
	  -erode_distance       "bone1_erosi_dilat
	  -use_previous_margin  false

	/dilation  ero  surfoi            
	  -dilate_distance       "bone1_erosi_dilat
	  -use_previous_margin  true

!	Because of the successive erosion-dilatation, the scattering ring is 
!	replaced by adjacent bone
!	From this image, only keep the OI bone close to the implant (surfoi)
!       that was affected by the scattering and segmented with high threshold 
!	=====================================================================
/del ero
/del bone1oi
/del bone1_oi
/del 

	/gobj_maskaimpeel_ow 
	  -input_output		surfoi
	  -gobj_filename	"maskoi_file
	  -peel_iter		0

	/cl_nr_extract             
	  -input                surfoi
	  -output               surfoi_cl
	  -min_number           5
	  -max_number           0
	  -value_in_range       90

! To smoothen OI: the gau_seg value (25) fits to an input of 90 !

/vox surfoi_cl

	/gauss_seg
	  -input                surfoi_cl
	  -output               smooth_oi
	  -sigma                2.000000
	  -support              2
	  -lower_in_perm        25
	  -upper_in_perm        1000
	  -value_in_range       "col_surf	
	  -unit                 5
/vox smooth_oi

	/gobj_maskaimpeel_ow 
	  -input_output		smooth_oi
	  -gobj_filename	"maskoi_file
	  -peel_iter		0

	/write
	  -name 		smooth_oi 
	  -filename 		"surfoi_file

	..
$!
$!---------------------------------------------------------------------------
$!  At this point, we have all needed bone MASKS and GOBJ + all the %OI files
$!  Surfoi includes the cortical & trabecular regions.
$!---------------------------------------------------------------------------
$!
$!
$  POSITION_05:
$!
$!	Bone images 1, 2 and 3
$!	======================
$!
$   	gau_file	:= 'FNAME'_GFILT.AIM
$   	thres_file   	:= 'FNAME'_THRES_SUB.AIM
$   	implf_file   	:= 'FNAME'_IMPLF.AIM
$   	impli_file   	:= 'FNAME'_IMPLI.AIM
$	mask_1_file	:= 'FNAME'_MASK_1.AIM
$	mask_2_file	:= 'FNAME'_MASK_2.AIM
$	mask_3_file	:= 'FNAME'_MASK_3.AIM
$   	maskoi_file	:= 'FNAME'_MASKOI.AIM
$   	bone12_file	:= 'FNAME'_BONE12.AIM
$   	bone_3_file	:= 'FNAME'_BONE_3.AIM
$	trab_gobj	:= 'TNAME'_MASK.AIM
$	surfoi_file	:= 'FNAME'_SURFOI.AIM
$	surfoit_file	:= 'FNAME'_SURFOIT.AIM
$	surfoic_file	:= 'FNAME'_SURFOIC.AIM
$	pibonet_file	:= 'FNAME'_PIBONET.AIM
$	pibonec_file	:= 'FNAME'_PIBONEC.AIM
$	maskoit_file	:= 'FNAME'_MASKOIT.AIM
$	maskoic_file	:= 'FNAME'_MASKOIC.AIM
$	maskpit_file	:= 'FNAME'_MASKPIT.AIM
$	maskpic_file	:= 'FNAME'_MASKPIC.AIM
$	imploi_file	:= 'FNAME'_IMPLOI.AIM
$!
$!
$	IPL_BATCH

	/db_scanco_activate false

	/read
	  -name 		gau 
	  -filename 		"gau_file

!	Extract bone image 1
!	--------------------

	/thres
	  -input		gau
	  -output		bone1
	  -lower_in_perm	"tres_b1
	  -upper_in_perm	100000
	  -value_in_range	127
	  -unit			5

	/gauss_seg
	  -input		bone1
	  -output		gauseg1
	  -sigma		1
	  -support		1
	  -lower_in_perm	450
	  -upper_in_perm	1000
	  -value_in_range	"col_bone1

	/gobj_maskaimpeel_ow 
	  -input_output		gauseg1 
	  -gobj_filename	"mask_1_file
	  -peel_iter		0

!!!!!!!! WAS 15   !!!
	/cl_nr_extract             
	  -input                gauseg1
	  -output               bone1
	  -min_number           5    
	  -max_number           0
	  -value_in_range       "col_bone1 

	/del gauseg1

!	Extract bone image 2
!	--------------------

	/thres
	  -input		gau
	  -output		bone2
	  -lower_in_perm	"tres_b2
	  -upper_in_perm	100000
	  -value_in_range	"col_bone2
	  -unit			5

	/gobj_maskaimpeel_ow 
	  -input_output		bone2 
	  -gobj_filename	"mask_2_file
	  -peel_iter		0

!	Extract bone image 3 + Cortex (w/o scattering on implant head)
!	-----------------------------

	/thres
	  -input		gau
	  -output		bone3
	  -lower_in_perm	"tres_b3
	  -upper_in_perm	100000
	  -value_in_range	"col_bone3
	  -unit			5

	/gobj_maskaimpeel_ow 
	  -input_output		bone3 
	  -gobj_filename	"mask_3_file
	  -peel_iter		0

	/del gau

	/write bone3 "bone_3_file
 
!	Concatenate bone images 1, 2, 3 and OI
!	--------------------------------------

	/concat
	  -input1		bone1
	  -input2		bone2
	  -output		bone12
	  -common_region_only	false
	  -add_not_overlay	false

	/del bone1
	/del bone2

 	/read  bone3  "bone_3_file

	/concat
	  -input1		bone12
	  -input2		bone3
	  -output		bone123
	  -common_region_only	false
	  -add_not_overlay	false

/del bone12
/del bone3

	/read surfoi  "surfoi_file 

	/concat
	  -input1		bone123
	  -input2		surfoi
	  -output		bone123oi
	  -common_region_only	false
	  -add_not_overlay	false

/del bone123

	/absolute_threshold
	  -input 		bone123oi 	
	  -output		bone_127	
	  -lower_in_abs		1
	  -upper_in_abs		127
	  -value_in_range	127

! Originally, bonea image was used for analysis (no further processing)
! sm_bone will now be processed for images and analyses

	/gauss_seg
	  -input		bone_127
	  -output		sm_bone
	  -sigma		"bone_sig
	  -support		"bone_sup
	  -lower_in_perm	"bone_th
	  -upper_in_perm	1000
	  -value_in_range	"col_bone
/del bone123oi
/del bone_127

! Take off the surfoi layer and replace with "good" surfoi

	/copy sm_bone bone_oi
	/gobj bone_oi "maskoi_file
	/subtract_aims sm_bone bone_oi 
	  -output               sm_bone123
/del sm_bone
/del bone_oi

!!! After smoothening and subtract_aims, sm_bone123 has no OI bone. 

	/concat
	  -input1		sm_bone123
	  -input2		surfoi
	  -output		boneoi
	  -common_region_only	false
	  -add_not_overlay	false

/del sm_bone123

	/read implf "implf_file
	/concat
	  -input1		boneoi
	  -input2		implf
	  -output		thres
	  -common_region_only	false
	  -add_not_overlay	false
!!! region was common only!

!!!/del boneoi
/del implf

	/offset_set
	  -input		thres
	  -new_offset		"offset "offset "offset

	/write
	  -name 		thres 
	  -filename 		"thres_file
	  -compress_type        bin
	  -version_020          true

!!! At this point, surfoi still includes cortex

!	Create OI in TRAB 
!	-----------------

	/absolute_threshold
	  -input 		surfoi 	
	  -output		surfoit	
	  -lower_in_abs		1
	  -upper_in_abs		127
	  -value_in_range	127
	 	
	/gobj_maskaimpeel_ow 
	  -input_output		surfoit
	  -gobj_filename	"maskoit_file 
	  -peel_iter		0

	/bounding_box_cut surfoit surfoi_bb
	  -z_only false
	  -border 10 10 0

	/write surfoi_bb "surfoit_file

!	Create OI in CORT 
!	-----------------

 	/gobj_maskaimpeel_ow 
	  -input_output		surfoi
	  -gobj_filename	"maskoic_file 
	  -peel_iter		0

	/bounding_box_cut surfoi surfoi_bb
	  -z_only false
	  -border 10 10 0

	/write surfoi_bb "surfoic_file

!	Create PIB in TRAB (from boneoi; used to be from bonea)  	
!	------------------

	/copy boneoi trab_pib
	/ren  boneoi cort_pib

	/gobj_maskaimpeel_ow 
	  -input_output		trab_pib
	  -gobj_filename	"maskpit_file 
	  -peel_iter		0

	/bounding_box_cut trab_pib pibone
	  -z_only false
	  -border 10 10 0

	/write  pibone  "pibonet_file

!	Create PIB in CORT (from boneoi)  	
!	------------------

	/gobj_maskaimpeel_ow 
	  -input_output		cort_pib
	  -gobj_filename	"maskpic_file 
	  -peel_iter		0

	/bounding_box_cut cort_pib pibone
	  -z_only false
	  -border 10 10 0

	/write  pibone  "pibonec_file
..
$!
$!------------------------------------------------------------------------------
$!
$	ENDCOM:
$!
$!	remove older versions of files
$!	==============================
$!
$!	Used files:
$!	-----------
$   	gau_file     := 'FNAME'_GFILT.AIM
$   	bone_3_file  := 'FNAME'_BONE_3.AIM
$   	bone12_file  := 'FNAME'_BONE12.AIM
$	impld1_file  := 'FNAME'_IMPLD1.AIM
$	impld2_file  := 'FNAME'_IMPLD2.AIM
$	impld3_file  := 'FNAME'_IMPLD3.AIM
$	impld4_file  := 'FNAME'_IMPLD4.AIM
$	mask_1_file  := 'FNAME'_MASK_1.AIM
$	mask_2_file  := 'FNAME'_MASK_2.AIM
$	mask_3_file  := 'FNAME'_MASK_3.AIM
$   	implf_file   := 'FNAME'_IMPLF.AIM
$	impli_file   := 'FNAME'_IMPLI.AIM
$   	thres_file   := 'FNAME'_THRES_SUB.AIM
$	surfoi_file  := 'FNAME'_SURFOI.AIM
$	surfoit_file := 'FNAME'_SURFOIT.AIM
$	surfoic_file := 'FNAME'_SURFOIC.AIM
$	pibone_file  := 'FNAME'_PIBONE.AIM
$	pibonet_file := 'FNAME'_PIBONET.AIM
$	pibonec_file := 'FNAME'_PIBONEC.AIM
$	maskoi_file  := 'FNAME'_MASKOI.AIM
$	maskpi_file  := 'FNAME'_MASKPI.AIM
$	maskoic_file := 'FNAME'_MASKOIC.AIM
$	maskoit_file := 'FNAME'_MASKOIT.AIM
$	pibone_file  := 'FNAME'_PIBONE.AIM
$	mask_c_file  := 'FNAME'_MASK_C.AIM
$!
$	del_files = 1
$!
$		PURGE 'gau_file'
$		PURGE 'implf_file'
$		PURGE 'thres_file'
$		PURGE 'maskoi_file'
$!		PURGE 'maskpi_file'
$		PURGE 'surfoi_file'
$		PURGE 'surfoit_file'
$		PURGE 'surfoic_file'
$		PURGE 'maskoi_file'	
$		PURGE 'maskoit_file'
$		PURGE 'maskoic_file'
$!		PURGE 'pibone_file'
$		PURGE 'pibonet_file'
$		PURGE 'pibonec_file'
$!		PURGE 'temp_file'
$!
$	IF del_files .EQS. "1"
$	THEN
$!		DELETE/NOLOG/NOCONFIRM 'implf_file';*
$!		DELETE/NOLOG/NOCONFIRM 'impli_file';*
$!		DELETE/NOLOG/NOCONFIRM 'bone12_file';*
$		DELETE/NOLOG/NOCONFIRM 'bone_3_file';*
$		DELETE/NOLOG/NOCONFIRM 'mask_1_file';*
$		DELETE/NOLOG/NOCONFIRM 'mask_2_file';*
$		DELETE/NOLOG/NOCONFIRM 'mask_3_file';*
$!		DELETE/NOLOG/NOCONFIRM 'impld1_file';*
$!		DELETE/NOLOG/NOCONFIRM 'impld2_file';*
$!		DELETE/NOLOG/NOCONFIRM 'impld3_file';*
$		DELETE/NOLOG/NOCONFIRM 'impld4_file';*
$		DELETE/NOLOG/NOCONFIRM 'mask_c_file';*
$!		DELETE/NOLOG/NOCONFIRM 'temp_file';*
$	ENDIF
$!
$!------------------------------------------------------------------------------
$	EXIT
$!------------------------------------------------------------------------------
