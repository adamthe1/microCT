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
$!  The first segmented volume (high dens) will be transparent, the second solid
$!  in the combined image. If there is an overlap between first and second
$!  input volume: the solid volume wins over the transparent volume.
$!  NOTE: ipl_lower0 must be greater than ipl_lower1
$!
$ ON ERROR THEN EXIT
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

/cl seg

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

/cl seg1

/bound seg1 seg_lo
  -z_only 		     false
  -border    		     5 
                                         
/dil seg_lo seg1 2 0
!/set seg1 60 0

/subtract  seg1 seg  both

! So now, value 60 in 'both' is only from ipl_lower1 (~150) to ipl_lower0 (~210)
 
!/thres both seg_lo 60 60  127  5
!/del both

/gauss_seg  both  seg1  1.2 2 300  1000  60
/del seg_lo

/write  seg1    "ipl_fname1
  -compress  bin

/transparent_concat
  -input_solid               seg1
  -input_transp              seg
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
..
$ EXIT
