$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!  Segmentation with gauss filter and thresholding.
$!  Two VOI are segmented, and then combined into a solid/transparent image
$!  The first segmented volume will be solid, the second one transparent
$!  in the combined image. If there is an overlap between first and second
$!  input volume: the solid volume wins over the transparent volume.
$!
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!	COMMANDFILE := SYS$SCRATCH:'FILENAME'.COM
$!
$	aim_file     :=  'DEV''DIR''FILENAME'.AIM
$	gau_file     :=  'DEV''DIR''FILENAME'_gfilt.AIM
$!	isq_file     :=  'DEV''DIR''FILENAME'.ISQ       !! ipl_isq
$!	seg_file     :=  'DEV''DIR''FILENAME'_SEG.AIM   !! ipl_segaim
$!	root_gobj    :=  'DEV''DIR''FILENAME'_D.GOBJ    !! ipl_gobj1
$	corr_gobj    :=  'DEV''DIR''FILENAME'_CORR.GOBJ
$!	pulp_file    :=  'DEV''DIR''FILENAME'_PULP.AIM  !! ipl_fname0
$!	dent_file    :=  'DEV''DIR''FILENAME'_DENT.AIM  !! ipl_fname1
$	temp_file    :=  'DEV''DIR''FILENAME'_TEMP.AIM
$	out_mask     :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$	int_mask     :=  'DEV''DIR''FILENAME'_inv5.AIM
$	geo_file     :=  'DEV''DIR''FILENAME'_GEO.AIM
$! 
$	ball_thres    =  240
$! 
$	dentin_thres  =  ipl_lower0   !  calibrated at 220  !!
$	gauseg_thres  =  ipl_lower1   !  calibrated at 600  !! 
$	calcif_thres  =  160
$	down_scale    =  ipl_support2
$	dilation_nr   =  ipl_lower2
$	erosion_nr    =  dilation_nr + 2
$!
$	val_pulp      =  60
$	pulp_parts    =  3     !  must be corrected if more 
$	val_calc      =  90
$	val_mask      =  120
$!
$ sh sym outmask
$ ON ERROR THEN EXIT
$!
$!  Special: if you want to skip to a specific section:
$!   GOTO MASKING          !!!!!!!!!!!!!!!!!!!!!!!!!!!
$!
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

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

/gau org gau
  -sigma                     "ipl_sigma0
  -support                   "ipl_support0

/write gau "gau_file

!!! If you want to start from GFILT, comment out all the above
!/read gau "gau_file

/del aim

/thres                
  -input                     gau
  -output                    seg
  -lower_in_perm             "ipl_lower0
  -upper_in_perm             "ipl_upper0
  -value_in_range            127
  -unit	       		     "ipl_unit0

!if gobj to isolate one root:
/gobj
  -input_output              seg
  -gobj_filename             "ipl_gobj0  
  -peel_iter                 "ipl_peel0

!!! ================================
!!! Geometric landmarks segmentation
!!! ================================

!/thres                
  -input                     gau
  -output                    ball
  -lower_in_perm             "ball_thres
  -upper_in_perm             1000
  -value_in_range            127

!/cl_rank_extract  
  -input                     ball
  -output                    geo
  -first_rank                2
  -last_rank                 4
  -connect_boundary          false
  -value_in_range            127

!/del ball
!/bound geo geo_bb false 2
!/write geo_bb "geo_file

!!! ================================
/del gau

!!! Light smoothening:

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support1
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_seg                 
  -input                     seg
  -output                    seg2
  -sigma                     "ipl_sigma1
  -support                   "ipl_support1
  -lower_in_perm             "ipl_lower1
  -upper_in_perm             1000
  -value_in_range            127

/del seg
/bound seg2 seg_sm
  -z_only 		     false
  -border    		     0 
/cl seg_sm 
/write seg_sm "ipl_fname1
/write seg_sm "temp_file
..
$!	  
$!	 .-----------------.
$!	 | Gobj Correction |
$!	 `-----------------'
$!
$ 	ON ERROR THEN EXIT
$ IF F$SEARCH("''corr_gobj'") .NES. ""
$ THEN 
$	GOTO CORR
$ ELSE 
$	GOTO MASKING
$ ENDIF
$!
$ CORR:
$ IPL_BATCH	

/gobj_to_aim
  -gobj_filename             "corr_gobj
  -output                    corr
  -peel_iter                 0

/read thres "temp_file

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
$!
$ MASKING:
$!
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
  -erode_distance            "erosion_nr
  -use_previous_margin       false

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

/togobj_from_aim  mask "ipl_gobj1
 -curvature_smooth   5

/write mask "out_mask
..
$!
$ PULP_DENTIN:
$!
$ IPL_BATCH

!!! Mask may contain voids on ext surf on dentin  (skipped for now)
!!! --------------------------------------------
!!! We need to subtract dentin without corr (seg_file) from mask

/read seg "ipl_fname1
!/gobj_to_aim "ipl_gobj1 mask
/read mask "out_mask

/subtract_aim
  -input1                    mask
  -input2                    seg
  -output                    pulp

! Remove voids in dentin not connected to pulp:

/bound pulp pulp1

! Optional, for voids on dentin external surf:
/gobj  pulp1  "ipl_gobj1
  -peel_iter  3

/sup pulp1 
  -supdim_numbers            4 4 1

/cl26_rank_extract  
  -input                     pulp1
  -output                    pulp
  -first_rank                1
  -last_rank                 "pulp_parts
  -connect_boundary          false
  -value_in_range            127 
/del pulp1

/write pulp "ipl_fname0

/subtract_aim
  -input1                    mask
  -input2                    pulp
  -output                    seg

/write seg "ipl_fname1

/set mask "val_mask 0
/set pulp "val_pulp 0

/concat mask pulp all
  -common_region_only false
  -add_not_overlay    false

/write all "ipl_segaim

!!!/vox_scanco_param pulp
..
$!
$ GOTO ENDCOM
$ ENDCOM:
$ EXIT
