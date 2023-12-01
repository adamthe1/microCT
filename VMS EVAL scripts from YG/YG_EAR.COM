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
$!  Combines 2 segmented volumes for middles ear ossicles and vestibulum.
$!  SEG.AIM is the combined file
$!  Needs 2 contours: 	_M.GOBJ that encompasses the ossicles   (ipl_gobj0)
$!			_V.GOBJ that encompasses the vestibulum	(ipl_gobj1)
$!
$!  UE:UCT_EVALUATION_V6.COM|UE:YG_EAR.COM
$	redo_gfilt    =  ipl_misc1_0
$! 
$   gau_file   := 'EVAL_DIR''EVAL_FNAME'_GFILT.AIM
$   temp_file  := 'EVAL_DIR''EVAL_FNAME'_TEMP.AIM
$!
$ IF  F$SEARCH(gau_file) .NES. ""
$ THEN
$  IF 	redo_gfilt .EQS. "YES"  .OR.  redo_gfilt  .EQS. "Y"
$  THEN	
$       READ_GAU   =  "!!!   ***  New GFILT generated  *** "
$  ELSE 
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  " /read gau ''gau_file' "
$  ENDIF
$ ENDIF
$!
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

!/write  org      	"ipl_aim
!/read org        	"ipl_aim
/sup org
  -supdim_numbers    	4 4 4
  -testoff_pixels       "ipl_support0
  -suppos_pixels_local  -1 -1 -1
  -subdim_pixels        -1 -1 -1

/gau org gau
  -sigma       		"ipl_sigma0
  -support     		"ipl_support0

/write   gau            "gau_file
"read_gau

/sup gau
  -supdim_numbers    	4 4 4
  -testoff_pixels       0
  -suppos_pixels_local  -1 -1 -1
  -subdim_pixels        -1 -1 -1

/thres   gau seg_m
  -low         		"ipl_lower0  
  -upp	       		"ipl_upper0
  -value       		127
  -unit	       		"ipl_unit0

/copy seg_m seg

/gobj
  -input_output         seg_m
  -gobj_filename        "ipl_gobj0
  -peel_iter            "ipl_peel0

/cl_extract
  -input                seg_m
  -output               cl
  -lo_vol_fract_in_perc 1
  -up_vol_fract_in_perc 100
  -value_in_range       100
/ren cl seg_m

/write  seg_m    	"ipl_fname0
  -compress  		bin

/thres   gau seg_v
  -low         		0  
  -upp	       		"ipl_lower0
  -value       		10
  -unit	       		"ipl_unit0

/del gau
/gobj_to_aim "ipl_gobj1 mask
/dil   mask dil 2
/write dil  "temp_file
/del dil
/del mask

/gobj
  -input_output         seg_v
  -gobj_filename        "temp_file
  -peel_iter            0

/cl_extract
  -input                seg_v
  -output               cl
  -lo_vol_fract_in_perc 10
  -up_vol_fract_in_perc 100
  -value_in_range       50
/ren cl seg_v

/write  seg_v    	"ipl_fname1
  -compress  		bin

/concat  seg_v  seg_m  ear                 
  -common_region_only        false
  -add_not_overlay           false
/del seg_m
/del seg_v

/transparent_concat
  -input_solid               ear
  -input_transp              seg
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
..
$  PURGE 'TEMP_FILE'
$  DEL/NOCONFIRM 'temp_file';*
$ EXIT
