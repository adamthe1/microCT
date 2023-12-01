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
$!  The segmented volume is saved compressed to file.
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH 

! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name      	org
  -isq_filename  	"ipl_isq
  -pos           	"ipl_voix "ipl_voiy "ipl_voiz
  -dim           	"ipl_voidx "ipl_voidy "ipl_voidz

/write  org      	"ipl_aim

/sup org
  -supdim_numbers    	4 4 1
  -testoff_pixels       "ipl_support0
  -suppos_pixels_local  -1 -1 -1
  -subdim_pixels        -1 -1 -1

/seg_gauss org seg
  -sigma       		"ipl_sigma0
  -support     		"ipl_support0
  -low         		"ipl_lower0  
  -upp	       		"ipl_upper0
  -unit	       		"ipl_unit0
  -value       		127

/bound seg seg1 true
                 


!/gobj
!  -input_output         seg
!  -gobj_filename        "ipl_gobj0
!  -peel_iter            "ipl_peel0

/write  seg1    	 "ipl_segaim
  -compress  		bin

..
$ EXIT
