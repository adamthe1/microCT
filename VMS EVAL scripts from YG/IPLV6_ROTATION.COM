$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!
$! Reformats ISQ to x or y cuts. 
$! Parameters: 0.000 90.000 90.000  for xz cuts
$!            90.000  0.000 90.000  for zy cuts
$!
$! Funny feature: turnangle in 2D is handed over as lower threshold! 
$! Positive direction for clockwise turns!
$!  
$!
$ IF (IPL_LOWER0 .EQS. "") .OR. (IPL_LOWER0 .EQ. 0)  
$ THEN 
$  TEMP = "/exa in geo"  !  acts as a placeholder
$ ELSE 
$  TEMP = "/exa in geo "+ -
	  "/turn2d in out1 -turnangle ""ipl_lower0  " + -
	  "-turnpoint_global_not_local false " + -
	  "-turnpoint -1 -1 " + -
	  "/rename out1 in"
$ ENDIF  
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  in
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

"temp

/turn3d in out
  -turnaxis_angles           "ipl_misc1_0 "ipl_misc1_1 "ipl_misc1_2
  -turnangle                 "ipl_misc1_3 

!  -turnaxis_angles           0.000 90.000 90.000  for xz cuts
!  -turnaxis_angles           90.000 0.000 90.000  for zy cuts

! comment out the following two lines if batch jobs are 
! crashing because of too little memory:
! commented out anyway for gray scale input. A.Laib
/bounding_box out outb
/rename outb out

/toisq_from_aim
  -aim_name                  out
  -isq_filename              "ipl_fname0
  -square_flag               true
  -original_position         false
..
$ EXIT
