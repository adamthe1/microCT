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
$	redo_gfilt    =  ipl_misc1_0
$! 
$ IF  F$SEARCH(ipl_fname0) .NES. ""
$ THEN
$  IF 	redo_gfilt .EQS. "YES"  .OR.  redo_gfilt  .EQS. "Y"
$  THEN	
$       READ_GAU   =  "!!!   ***  New GFILT generated  *** "
$  ELSE 
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  " /read gau ''ipl_fname0' "
$  ENDIF
$ ENDIF
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

/write   gau            "ipl_fname0
"read_gau

/sup gau
  -supdim_numbers    	4 4 4
  -testoff_pixels       0
  -suppos_pixels_local  -1 -1 -1
  -subdim_pixels        -1 -1 -1

/thres   gau seg
  -low         		"ipl_lower0  
  -upp	       		"ipl_upper0
  -value       		127
  -unit	       		"ipl_unit0

/gobj
  -input_output         seg
  -gobj_filename        "ipl_gobj0
  -peel_iter            "ipl_peel0

/write  seg    		"ipl_segaim
  -compress  		bin

..
$ EXIT
