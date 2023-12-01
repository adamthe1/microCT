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
$!  Two VOI are segmented, and then combined.
$!  The first segmented volume is from highest density, the second is lowest;
$!  Low-dens gradient around hi-dens object is removed.
$!
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!	COMMANDFILE := SYS$SCRATCH:'FILENAME'.COM
$!
$	aim_file     :=  'DEV''DIR''FILENAME'.AIM
$	gau_file     :=  'DEV''DIR''FILENAME'_gfilt.AIM
$	corr_gobj    :=  'DEV''DIR''FILENAME'_CORR.GOBJ
$!	enam_file    :=  'DEV''DIR''FILENAME'_ENAM.AIM  !! ipl_fname0
$!	dent_file    :=  'DEV''DIR''FILENAME'_DENT.AIM  !! ipl_fname1
$	temp_file    :=  'DEV''DIR''FILENAME'_TEMP.AIM
$	out_mask     :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$! 
$	enamel_thres  =  ipl_lower0   !  calibrated at 210  !!
$	dentin_thres  =  ipl_lower2   !  calibrated at 420  !! 
$	decalc_upper  =  ipl_lower2 * 3 / 2
$	down_scale    =  ipl_sigma2
$	dilation_nr   =  ipl_support2
$	erosion_nr    =  dilation_nr
$!
$	val_enam      =  127
$	val_dent      =  90
$	val_deca      =  60
$!
$ ON ERROR THEN EXIT
$!
$!  Special: if you want to skip to a specific section:
$!   GOTO MASKING          
$!
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
!  -pos                       0 0 0
!  -dim                       -1 -1 -1
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

!..
!$ EXIT
!!! If you want to start from GFILT, comment out all the above

!/read gau "gau_file

/thres                
  -input                     gau
  -output                    whole_dent
  -lower_in_perm             "ipl_lower2
  -upper_in_perm             "ipl_lower0
  -value_in_range            127
  -unit	       		     "ipl_unit0

/sub_get              
  -input                     gau
  -output                    crown
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz
  -global_pos_flag           true
/del gau

/thres                
  -input                     crown
  -output                    cr_enam
  -lower_in_perm             "ipl_lower0
  -upper_in_perm             "ipl_upper0
  -value_in_range            127
  -unit	       		     "ipl_unit0

!!! ================================
! Add thres for low-calcified dentin if needed, here.
/del crown
/cl_nr_extract             
  -input                     cr_enam
  -output                    clean_enam
  -min_number                50000  ! was 50000
  -max_number                0
  -value_in_range            127
/ren clean_enam cr_enam

/cl whole_dent 
/sub_get              
  -input                     whole_dent
  -output                    cr_dent
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz
  -global_pos_flag           true

/subtr whole_dent cr_dent root_dent
/del whole_dent

/bounding_box_cut cr_dent dent
  -z_only false
  -border 5
/del cr_dent

/erosion
  -input                     dent
  -output                    ero
  -erode_distance            "erosion_nr
  -use_previous_margin       false
/del dent

/dilation
  -input                     ero
  -output                    cr_dent
  -dilate_distance           "dilation_nr
  -continuous_at_boundary    0
  -use_previous_margin       true
/del ero

/concat cr_dent root_dent dent
  -common_region_only false
  -add_not_overlay    false

/invert dent

!!! consider changing to another cl function !!!

/cl dent
/invert dent
/cl dent 
/set dent "val_dent
/set cr_enam "val_enam

/concat dent cr_enam seg 
  -common_region_only false
  -add_not_overlay    true

/write cr_enam "ipl_fname0
/write dent    "ipl_fname1
/write seg     "ipl_segaim
..
$!
$ GOTO ENDCOM
$ ENDCOM:
$ EXIT
