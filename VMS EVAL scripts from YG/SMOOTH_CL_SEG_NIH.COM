$! Define here if you want to remove small speckles. Define here 
$! the minimum size of small elements to be kept (0 to cancel):
$ cl_min	=  50
$ IF P1 .EQS. "" 
$ THEN 
$	SAY ""
$	SAY "		Define P1 as name of SEG file: DK..:...SEG.AIM"
$	SAY "		Define P2 as corresponding GOBJ file"
$	SAY ""
$	EXIT
$ ENDIF
$!-----
$! 	seg_name     = F$SEARCH("*seg.aim;*")
$! 
$	FILENAME     = F$PARSE(P1,,,"NAME")
$! 	FILENAME     = F$EXTRACT(0,8,filename)
$	DEV          = F$PARSE(P1,,,"DEVICE")
$	DIR          = F$PARSE(P1,,,"DIRECTORY")
$	seg_file     = P1
$	seg_sm_file  :=  'DEV''DIR''FILENAME'_SM.AIM
$	MSK_sm_file  :=  'DEV''DIR''FILENAME'_MASK_SM.AIM
$	sh sym seg_sm_file
$	sh sym seg_file
$!
$ IPL_BATCH 

/gobj_to_aim
  -gobj_filename             "P2
  -output                    gobj

/seg_gauss
  -input                     gobj
  -output                    g_sm
  -sigma                     2
  -support                   2
  -lower_in_perm_aut_al      400
  -upper_in_perm_aut_al      100000
  -value_in_range            127
  -unit                      6

/write g_sm "msk_sm_file

/read in "seg_file
/gobj in "mask_sm_file

/cl_nr_extract
  -input                     in
  -output                    cl
  -min_number                "cl_min
  -max_number                0
  -value_in_range            127

/bounding_box_cut
  -input                     cl
  -output                    out
  -z_only                    false
  -border                    5 5 0

/seg_gauss
  -input                     out
  -output                    seg
  -sigma                     2
  -support                   2
  -lower_in_perm_aut_al      350
  -upper_in_perm_aut_al      100000
  -value_in_range            127
  -unit                      6

/write seg "seg_sm_file
..
$ ENDCOM:
$ DEL/noconfirm 'msk_sm_file';*
$ EXIT
