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
$!  The first and second segmented volumes (high dens) will be solid, the third transparent
$!  in the combined image. If there is an overlap between first and second
$!  input volumes: the solid volumes win over the transparent volume.
$!  NOTE: ipl_lower0 must be greater than ipl_lower1 & 2
$!
$ ON ERROR THEN EXIT
$ IF 'ipl_support1' .GE. 'ipl_support0'
$ THEN
$     ipl_support = ipl_support1
$ ELSE
$     ipl_support = ipl_support0
$ ENDIF
$ sh sym ipl_support
$!
$! GOTO SMO
$ IPL_BATCH
!  
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
  -testoff_pixels            "ipl_support
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gau org gau
  -sigma       "ipl_sigma0
  -support     "ipl_support0
/del org

/thres gau seg
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0

/gobj
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

!/cl seg

/write  seg    "ipl_fname0
  -compress  bin

/thres gau seg1
  -low         "ipl_lower1  
  -upp	       "ipl_lower0
  -value       110
  -unit	       "ipl_unit1

/gobj
  -input_output              seg1
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/write  seg1   "ipl_fname1
  -compress  bin

/thres gau seg2
  -low         "ipl_lower2  
  -upp	       "ipl_lower1
  -value       90
  -unit	       "ipl_unit2
/del gau

/gobj
  -input_output              seg2
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/write  seg2    "ipl_fname2
  -compress  bin

!!! Consider commenting out the CL command:
!/cl seg1

/transparent_concat
  -input_solid               seg1
  -input_transp              seg2
  -output                    out

/concat seg out all
  -common_region_only        false
  -add_not_overlay           true

/write  all    "ipl_segaim
  -compress  bin
..
$ SMO:
$! Optional: Smoothing out the low-density object:
$!
$ IF ipl_misc1_0 .EQS. "YES" .OR. ipl_misc1_0 .EQS. "Y" 
$ THEN
$    IPL_BATCH

/read seg_lo "ipl_fname1

/erosion seg_lo ero 1
  -use_previous_margin       false
  -metric                    101

/cl ero 

/dilation ero seg_lo 1
  -use_previous_margin       true
  -metric                    101

/set seg_lo 0 127
/cl seg_lo
/set seg_lo 0 127

!/erosion seg_lo ero 5
!  -use_previous_margin       false
!  -metric                    101

!/dilation ero  seg_lo 5
!  -use_previous_margin       true
!  -metric                    101
/ren seg_lo seg1

/write seg1 "ipl_fname1
  -compress  bin

/read  seg "ipl_fname0

!!! Consider if you want to CL the solid object:
!/cl seg 

/transparent_concat
  -input_solid               seg
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
..
$ ENDIF
$ EXIT
