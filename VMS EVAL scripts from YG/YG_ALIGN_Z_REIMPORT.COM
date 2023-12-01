$!  Align in Z and reimport
$!
$!  author:     Martin Stauber
$!  created:    07-MAR-2014
$!
$!  version:    1.1
$!
$!  depends on:
$!      UE:UCT_EVALUATION_V6.COM
$!      UE:UCT_EVALUATION_V6_REIMPORT.COM
$!
$!  modifications:
$!  V1.0: MS 07-MAR-2014, created
$!  V1.1: MS 29-APR-2015, added square_flag as modifiable parameter
$!------------------------------------------------------------------------------
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file       :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	seg_file        =   IPL_SEGAIM 
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$	ipl_temp       :=  'DEV''DIR''FILENAME'_temp.AIM
$!
$! AFTER ROTATION:
$	FILENAME     = F$PARSE("''IPL_fname0'",,,"NAME")
$	DEV          = F$PARSE("''IPL_fname0'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_fname0'",,,"DIRECTORY")
$	rot_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$	rot_gobj       :=  'DEV''DIR''FILENAME'.GOBJ
$	ipl_temp       :=  'DEV''DIR''FILENAME'_temp.AIM
$! ipl_gobj0 = out_mask                                   
$!
$ IPL_BATCH

! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  in
  -isq_filename              "IPL_ISQ
  -pos                       0 0 0
  -dim                       -1 -1 -1
!  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
!  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/align_z
  -input                     in
  -output                    rot_isq
  -origin_point              "IPL_MISC1_0
  -z-axis_point              "IPL_MISC1_1
  -xz-plane_point            "IPL_MISC1_2
  -img_interpol_option       "IPL_MISC1_3

!/examine rot_isq geo
!/header_geo_set rot_isq
!  -off_new		     -1
!  -pos_new		     0
 
! Realign the Gobj/Mask as well (before writing the ISQ):
/convert_to_type  in box char
/set_value	  box 0 0 
/gobj_to_aim "ipl_gobj0 mask
/bounding  mask mask_org  f
/write     mask "out_mask
/concat box mask_org mask f t 

/align_z
  -input                     mask
  -output                    rot_mask
  -origin_point              "IPL_MISC1_0
  -z-axis_point              "IPL_MISC1_1
  -xz-plane_point            "IPL_MISC1_2
  -img_interpol_option       0

!/header_geo_set rot_mask
!  -off_new		     -1
!  -pos_new		     0

! New ISQ and mask in a smaller box
 
/bound rot_mask box f 
  -border		10
!!! Change the above borders to 4 or less is the resulting GOBJ is shifted 
/copy box rot_mask
/set_value	  box 127 127 
/write box "ipl_temp

/gobj rot_isq   "ipl_temp
/bound rot_isq  bb  f     
  -border		0 

/ren bb   rot_isq

!/gobj rot_mask  "ipl_temp
!/gobj rot_isq   "ipl_temp

/examine rot_mask geo
/header_geo_set rot_mask
  -off_new		     0
  -pos_new		     0
/examine rot_isq geo
/header_geo_set rot_isq
  -off_new		     0
  -pos_new		     0
           
! Optional: Turn3D (for Ossicles)
/turn3d rot_mask out 
  -turnaxis_angle	 0 90 90
  -turnangle		 90
/ren out rot_mask 
/header_geo_set rot_mask
  -off_new		     0
  -pos_new		     0
/turn3d rot_isq out 
  -turnaxis_angle	 0 90 90
  -turnangle		 90
/ren out rot_isq 
/header_geo_set rot_isq
  -off_new		     0
  -pos_new		     0
! ------------------------------


!No need to write the MASK.AIM as it cannot be reimported
/togobj rot_mask "rot_gobj   

/toisq_from_aim
  -aim_name                  rot_isq
  -isq_filename              "ipl_fname0
  -square_flag               "IPL_MISC1_4
  -original_position         false

..
$ EXIT
