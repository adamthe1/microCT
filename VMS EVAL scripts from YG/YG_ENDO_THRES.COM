$!------------------------------------------------------------------------------
$!	YG_ENDO_THRES.COM
$!	Image processing on ISQ/Gfilt for visualization of RC 
$!------------------------------------------------------------------------------
$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$!	Output: *_F_MASK.AIM
$!		*_D_THRES.AIM	  (Thresholded image of dentin)
$!		*_P_THRES.AIM     (Thresholded image of pulp)
$!		*_F_THRES.AIM     (Thresholded image of both)
$!		and 3 masks for apical, mid-root and coronal analyses
$!
$	stepto 		= "POSITION_01" 
$	keep_files 	= 0 
$!                         
$!------------------------------------------------------------------------------
$!      Define Log & Sym
$!      ================
$	gaus_file     :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	dent_file     :=  'DEV''DIR''FILENAME'_DENT.AIM
$!	pulp_file     :=  'DEV''DIR''FILENAME'_PULP.AIM
$!	thre_file     :=  'DEV''DIR''FILENAME'_SEG.AIM
$	mask_file     :=  'DEV''DIR''FILENAME'_F_MASK.AIM
$!	api_mask      :=  'DEV''DIR''FILENAME'_A_MASK.AIM
$!	mid_mask      :=  'DEV''DIR''FILENAME'_M_MASK.AIM
$	cor_mask      :=  'DEV''DIR''FILENAME'_C_MASK.AIM
$!
$	isq_file      =  IPL_ISQ
$	gau_file      =  IPL_AIM
$	seg_file      =  IPL_SEGAIM
$!	gau_file     :=  'DEV''DIR''FILENAME'_gfilt.AIM
$!	isq_file     :=  'DEV''DIR''FILENAME'.ISQ
$!	seg_file     :=  'DEV''DIR''FILENAME'_SEG.AIM
$	corr_gobj    :=  'DEV''DIR''FILENAME'_CORR.GOBJ
$	pulp_file    :=  'DEV''DIR''FILENAME'_PULP.AIM
$	temp_file    :=  'DEV''DIR''FILENAME'_TEMP.AIM
$	out_mask     :=  'DEV''DIR''FILENAME'_F_MASK.AIM
$	int_mask     :=  'DEV''DIR''FILENAME'_inv5.AIM
$!	geo_file     :=  'DEV''DIR''FILENAME'_GEO.AIM
$!
$	dentin_thres  =  ipl_lower0
$	calcif_thres  =  ipl_lower1
$	gauseg_thres  =  600   !  calibrated at 600
$	down_scale    =  3
$	dilation_nr   =  3
$	erosion_nr    =  4
$!	border	      =  22    !  must be at least 2*dilat_nr 
$!	cut_edge_nr   =  0
$	cut_edge_nr   =  -2    !  neg value to cut in xyz axes
$	cl_pulp       =  1
$!
$	val_pulp      =  120
$	val_dent      =  -1
$	val_mask      =  127
$!
$! 1mm = 50 vox (at 20um resolution)
$!	segment_dim   = 100
$!	api_start     =  50
$!	mid_start     = 150
$!	cor_start     = 250
$!------------------------------------------------------------------------------
$ 	ON ERROR THEN EXIT
$   
$!
$ GOTO 'stepto'
$ POSITION_01:
$ IPL_BATCH
 
! extract VOI from ISQ

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz
 
/sup org
  -supdim_numbers            4 4 2
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gau org gau
  -sigma                     "ipl_sigma0
  -support                   "ipl_support0

/write gau "gau_file
!/read gau "gau_file

! Dentin segmentation :
! -------------------

/thres                
  -input                     gau
  -output                    thres
  -lower_in_perm             "dentin_thres
  -upper_in_perm             1000
  -value_in_range            127

/del gau

!!! ================================

/cl_ow_rank_extract  
  -input_output              thres
  -first_rank                1
  -last_rank                 1
  -connect_boundary          false
  -value_in_range            127

/bounding_box_cut          
  -input                     thres
  -output                    seg_bb
  -z_only                    false
  -border                    5 5 5
/del thres

!!! New: same smoothening for entire tooth
/gauss_seg                 
  -input                     seg_bb
  -output                    seg
  -sigma                     1.2
  -support                   1
  -lower_in_perm             "gauseg_thres
  -upper_in_perm             1000
  -value_in_range            127

!--------------------------------------------------------------------
!!! Strong smoothening for the root vs light smoothening at the apex:
!!! Removed from script
!--------------------------------------------------------------------


/write seg "seg_file
/write seg "temp_file

!!! seg_file is used in the final concat for the mask
!!! temp_file is used for masking processing

..
$!	  
$!	 .-----------------.
$!	 | Gobj Correction |
$!	 `-----------------'
$!
$ 	ON ERROR THEN EXIT
$ IF F$SEARCH("''corr_gobj'") .NES. ""
$ THEN
$   	ipl_scanco_prog := $um:ipl_scanco_m.exe
$!
$ 	ipl_scanco_prog

/gobj_to_aim
  -gobj_filename             "corr_gobj
  -output                    corr
  -peel_iter                 0

/read seg "temp_file

/bound seg thres
  -z_only 		     false
  -border    		     0  0  0 

/examine thres geo

/concat                    
  -input1                    thres
  -input2                    corr
  -output                    comm
  -common_region_only        true
  -add_not_overlay           true

/concat                    
  -input1                    comm
  -input2                    thres
  -output                    seg
  -common_region_only        false
  -add_not_overlay           true

! Both concat are needed to preserve original aim size
/del thres
/del corr
/del comm

/examine seg geo

/write seg "temp_file

..
$ ENDIF
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH

/read seg "temp_file

! For high-res volumes, downscale before dil_ero and cl
/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dilp1
  -dilate_distance           "dilation_nr

/del sca

! For open teeth, the VOI box cut at a clean ring (for masking)
/bounding_box_cut dilp1 dil
  -z_only true
  -border 0

/del dilp1

/set  dil 0 127
/cl   dil
/set  dil 0 127

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/bounding_box_cut  ero sca
  -z_only false
  -border 2

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false

/concat ero seg mask
  -common_region_only false
  -add_not_overlay    true

!!! Now we need the dentin without corr (seg_file)
!!! Mask may contain voids on ext surf of dentin so check colors
!!! Extract Pulp, and remove external and internal voids:

/read seg "seg_file
/set  mask 60 0
/set  seg 127 0

/concat mask seg out
  -common_region_only false
  -add_not_overlay    true

/absolute_threshold        
  -input                     out
  -output                    pulp
  -lower_in_abs              60
  -upper_in_abs              60
  -grayscale_or_scaledvalues grayscale
  -value_in_range            127

! Remove ext voids:

/bound pulp pulp1

/cl26_rank_extract  
  -input                     pulp1
  -output                    pulp
  -first_rank                1
  -last_rank                 "pulp_parts
  -connect_boundary          false
  -value_in_range            127 
/del pulp1

/write pulp "pulp_file

/concat pulp seg mask_b
  -common_region_only false
  -add_not_overlay    true

/del seg
/set mask_b 127 0

! Remove int voids:

/bounding_box_cut mask_b mask false 0

/del mask_b

/set mask 0 127 

/cl_ow_rank_extract  
  -input_output              mask
  -first_rank                1
  -last_rank                 1
  -connect_boundary          false
  -value_in_range            127 

/set mask 0 "val_mask
 
/bounding_box_cut mask mask_bb
  -z_only false
  -border  0 0 0 

/del mask

/write mask_bb "out_mask
  -compress  bin

/set mask_bb "val_dent 0
/set pulp    "val_pulp 0

/concat mask_bb pulp all
  -common_region_only false
  -add_not_overlay    false

/write all "seg_file

!/db_scanco_activate true
!/vox_scanco_param pulp

..
$!
$ GOTO ENDCOM
$ ENDCOM:
$ ON ERROR THEN CONTINUE
$!
$	PURGE 'SEG_FILE'
$	PURGE 'PULP_FILE'
$	PURGE 'MASK_FILE'
$	delete/noconfirm 'TEMP_FILE';*
$!
$! Pre or Post scan?
$! If POST scan:
$  IF (ipl_misc1_0 .EQS. "Y") .OR. (ipl_misc1_0 .EQS. "YES") 
$  THEN   
$	PST_PULP    := 'DEV''DIR''FILENAME'_PST_PULP.AIM	
$	PST_MASK    = mask_file	
$	sh sym pst_pulp
$    	RENAME/noconfirm 'pulp_file' 'pst_pulp'
$  ELSE
$! If PRE scan:
$	PRE_PULP    := 'DEV''DIR''FILENAME'_PRE_PULP.AIM	
$	sh sym pre_pulp
$    	RENAME/noconfirm 'pulp_file' 'pre_pulp'
$  ENDIF
$!
$!------------------------------------------------------------------------------
$!
$ MATCHING:
$  IF (ipl_MISC1_0 .EQS. "Y") .OR. (ipl_MISC1_0 .EQS. "YES") 
$  THEN   
$	write sys$output " "
$	write sys$output "    ***** PRE-POST MATCHING WILL NOW BE PERFORMED *****"
$	write sys$output " "
$       PRE_MEAS     = IPL_MISC1_1	     
$       LENGTH       = F$LOCATE("]",IPL_ISQ) - 8
$       DIR_SAMP     = F$EXTRACT(0,LENGTH,IPL_ISQ)
$	PRE_PULP     = F$SEARCH("''DIR_SAMP'*''PRE_MEAS']*_PULP.AIM")	
$	PRE_PULP     = PRE_PULP - F$PARSE("''PRE_PULP'",,,"VERSION")	
$	PRE_MASK     = F$SEARCH("''DIR_SAMP'*''PRE_MEAS']*_F_MASK.AIM")
$	DIF_MASK     :=  'DEV''DIR''FILENAME'_DIF_MASK.AIM
$	R_ENDO       :=  'DEV''DIR'R_ENDO.AIM   ! canal with transp dentin
$	R_PULP       :=  'DEV''DIR'R_PULP.AIM   ! canal only
$	R_MASK       :=  'DEV''DIR'R_MASK.AIM   ! mask
$    IF F$SEARCH(pre_pulp) .EQS. ""
$    THEN   
$	write sys$output "    ***** COULD NOT FIND ''PRE_SEG' *****"
$	EXIT
$    ENDIF
$  ELSE
$	write sys$output "    ***** PRE-POST MATCHING WILL NOT BE PERFORMED *****"
$ 	EXIT
$  ENDIF
$!
$ 	SH SYM PRE_PULP
$ 	SH SYM PRE_MASK
$	sh sym pst_pulp
$	sh sym pst_mask
$	SH SYM DIF_MASK
$	SH SYM R_ENDO
$	SH SYM R_PULP
$	SH SYM R_MASK
$!
$!!! Calculate discrepancy between pre and post scans:
$    root_calc_reg  'pre_mask' 'pst_mask' 'dif_mask'
$!
$!!! Correct 3D position of POST scan (2nd input must be same as in calc_reg):
$    root_apply_reg 'pst_pulp' 'pst_mask'
$! This generates a rectified ..._pst_pulp_reg.aim
$! 
!!!!!!!!!!!!!!!! Ask scanco if I can correct the pre instead of the post.
!!!!!!!!!!!!!!!! Ask if dentine has to be transparent (-1)
$!
$!!! Match pre and post images:
$! For entire tooth (one canal):
$  root_apply_match 'pre_pulp' 'pst_pulp' 'R_PULP'
$!
$! Visualize matched canals in the original (pre) MASK:
$ IPL_BATCH
/read pre  "pre_pulp
/read pst  "pst_pulp
/set  pre  40 0
/set  pst  80 0
/concat pst pre canal
  -common_region_only        false
  -add_not_overlay           true
/read mask "pre_mask
/transparent canal mask all
/write all "r_endo
..
$  EXIT
