$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Z�rich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!
$! UE:UCT_EVALUATION_V6.COM|UE:YG_FLIP_TURN2D_import.COM|UE:UCT_EVALUATION_V6_REIMPORT.COM
!  Set variables (misc): flip axis | flip angle (with .0) | CW turnangle in 2D | Bound_box (Y/N)
!  Flip angle 90.0 for slices from up to down (-90.0 for opposite)
!  Enter first Letter of imported ISQ Filename in ext1 and ext2 of the File keyword
$! 
$! Reformats ISQ to x, y or z cuts. 
$! Parameters: 0.000 90.000 90.000  for xz cuts
$!            90.000  0.000 90.000  for zy cuts
$!
$! Optional: turnangle in 2D can be set in variables
$! Positive direction for clockwise turns!
$!  
$!
$ IF (IPL_MISC1_2 .EQS. "") .OR. (IPL_MISC1_2 .EQS. "0") .OR. (IPL_MISC1_2 .EQS. "0.0") 
$ THEN 
$  TEMP = "/exa in geo"  !  acts as a placeholder
$ ELSE 
$  TEMP = "/exa in geo "+ -
	  "/turn2d in out1 -turnangle ""ipl_misc1_2  " + -
	  "-turnpoint_global_not_local false " + -
	  "-turnpoint -1 -1 " + -
	  "/rename out1 in"
$ ENDIF  
$!
$ IF IPL_MISC1_0 .EQS. "X" THEN AXIS = "0.000 90.000 90.000"  
$ IF IPL_MISC1_0 .EQS. "Y" THEN AXIS = "90.000 0.000 90.000" 
$ IF IPL_MISC1_0 .EQS. "Z" THEN AXIS = "90.000 90.000 0.000" 
$ IF AXIS 	 .EQS. ""  THEN AXIS = "0.000 90.000 90.000" 
$!
$ IF IPL_MISC1_4 .EQS. "Y" 
$ THEN 
$   BOUND_BOX = "/bounding_box out outb " + -
		"/rename outb out "
$ ELSE 
$   BOUND_BOX = "/rename out outb " + -
		"/rename outb out "
$ ENDIF  
$!
$ ON ERROR THEN EXIT
$ IF ipl_misc1_3 .EQS. "Y" THEN GOTO FLIP_GOBJ
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
  -turnaxis_angles           "axis
  -turnangle                 "ipl_misc1_1 

! comment out the following two lines if batch jobs are 
! crashing because of too little memory:
! commented out anyway for gray scale input. A.Laib
"bound_box

/toisq_from_aim
  -aim_name                  out
  -isq_filename              "ipl_fname0
  -square_flag               true
  -original_position         false
..
$ EXIT
$ FLIP_GOBJ:
$ 
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
  -turnaxis_angles           "axis
  -turnangle                 "ipl_misc1_1 

! comment out the following two lines if batch jobs are 
! crashing because of too little memory:
! commented out anyway for gray scale input. A.Laib
!"bound_box

/toisq_from_aim
  -aim_name                  out
  -isq_filename              "ipl_fname0
  -square_flag               true
  -original_position         true
!!! I'm trying true for the gobj...
/del out

/norm_max in norm 
  -max			auto
  -type_out		char
/del in

/set norm 0 0 
/gobj_to_aim 
  -gobj_filename	"ipl_gobj0
  -output		mask
  -peel_iter		"ipl_peel0
/concat mask norm mask2 f t
/del norm
/del mask
/turn3d mask2 mask
  -turnaxis_angles           "axis
  -turnangle                 "ipl_misc1_1 
/togobj_from_aim mask   "ipl_gobj1
  -min_elements		0
  -max_elements		0
  -curvature_smooth	5

..
$EXIT
