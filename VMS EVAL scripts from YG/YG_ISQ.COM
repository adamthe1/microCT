$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! Generate new ISQ after white box
$!
$! Optional: turnangle in 2D can be set in variables
$! Positive direction for clockwise turns!
$!
$ IF (IPL_MISC1_3 .EQS. "") .OR. (IPL_MISC1_3 .EQS. "0") .OR. (IPL_MISC1_3 .EQS. "0.0") 
$ THEN 
$  TEMP = "/exa org geo"  !  acts as a placeholder
$ ELSE 
$  TEMP = "/exa org geo "+ -
	  "/turn2d org out1 -turnangle ""ipl_misc1_3  " + -
	  "-turnpoint_global_not_local false " + -
	  "-turnpoint -1 -1 " + -
	  "/rename out1 org"
$ ENDIF 
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

"temp

/from_aim_to_isq       
  -aim_name             org
  -isq_filename         "ipl_fname0
  -square_flag          true    
  -original_position    "ipl_misc1_2     
..
$ EXIT
