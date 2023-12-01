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
! extract sub-region from ISQ
!

/isq_to_aim
  -aim_name      	org
  -isq_filename  	"ipl_isq
  -pos           	"ipl_voix "ipl_voiy "ipl_voiz
  -dim           	"ipl_voidx "ipl_voidy "ipl_voidz

/from_aim_to_isq       
  -aim_name             org
  -isq_filename         "ipl_fname0
  -square_flag          true    
  -original_position    true     
..
$ EXIT
