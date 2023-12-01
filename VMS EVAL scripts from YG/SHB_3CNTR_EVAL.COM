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
$!  The first segmented volume (high dens) will be solid, the second transparent
$!  in the combined image. If there is an overlap between first and second
$!  input volumes: the solid volume wins over the transparent volume.
$!  NOTE: ipl_lower0 must be greater than ipl_lower1
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

/seg_gauss org seg
  -sigma       "ipl_sigma0
  -support     "ipl_support0
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       127


/gobj
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

!/cl seg

/write  seg    "ipl_fname0
  -compress  bin

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support1
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org seg1
  -sigma       "ipl_sigma1
  -support     "ipl_support1
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -unit	       "ipl_unit1
  -value       127

/del org

/gobj
  -input_output              seg1
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

!!! Consider commenting out the CL command:
!/cl seg1

/bound seg1 seg_lo
  -z_only 		     false
  -border    		     5 
                                         
!Obsolete: /ero seg_lo seg1 4 0

/set seg_lo 60 0

/subtract seg_lo seg    seg1
/thres    seg1   seg_lo 60 60 127 5
/ren      seg_lo seg1
! So now, value 60 in 'seg1' is only from ipl_lower1 (~150) to ipl_lower0 (~210)
 
!/thres both seg_lo 60 60  127  5
!/del both
!/gauss_seg  seg_lo  seg1  1.2 2 300  1000  60

!/del seg_lo

/write  seg1    "ipl_fname1
  -compress  bin

/transparent_concat
  -input_solid               seg
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
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

!!!/cl ero 
/cl_nr_extract ero cl
  -min_number                3
  -max_number                0
  -value_in_range            127
  -topology                  26
/del ero

/dilation cl seg_lo 1
  -use_previous_margin       true
  -metric                    101
/del cl

!/set seg_lo 0 127
!/cl seg_lo
!/set seg_lo 0 127

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
