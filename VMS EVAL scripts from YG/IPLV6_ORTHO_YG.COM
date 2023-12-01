$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$! This script is for the analysis of periodontal bone on the pressure (P) and
$! tension (T) sides of the mesial (M) and distal (D) roots of M1.
$! Contours will be drawn at the lamina dura (LD) of the M and D roots (+_M/D.GOBJ)
$! and a triangle will define the 90 deg facing the T or P side of the root(s)
$! so there will be 3 triangles: +_MP.GOBJ; +_MT.GOBJ; +_DP.GOBJ
$! ipl_misc1_1 (variable 2) defines the number of pixels away from LD for VOI limit
$  DIL_NB = ipl_misc1_1
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM	
$!
$	ROOT0_NAME   = F$PARSE("''IPL_GOBJ0'",,,"NAME")
$	ROOT1_NAME   = F$PARSE("''IPL_GOBJ1'",,,"NAME")
$!
$! 0 is for M; 1 is for D root:
$	SEG_0_FILE   :=  'DEV''DIR''SIDE0_NAME'_SEG.AIM 	
$	SEG_1_FILE   :=  'DEV''DIR''SIDE1_NAME'_SEG.AIM  
$	MASK0_FILE   :=  'DEV''DIR''SIDE0_NAME'_MASK.AIM  	
$	MASK1_FILE   :=  'DEV''DIR''SIDE1_NAME'_MASK.AIM  
$	MASK0_GOBJ   :=  'DEV''DIR''SIDE0_NAME'_MASK.GOBJ  	
$	MASK1_GOBJ   :=  'DEV''DIR''SIDE1_NAME'_MASK.GOBJ 
$!		
$! GOTO VOI_1
$! GOTO UCT_LIST_1
$!
$ IF 	F$SEARCH(gau_file) .NES. ""    
$ THEN	
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  "/read gau ""gau_file "
$ ENDIF
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH

/db_scanco_activate true         

! create .AIM file from .ISQ

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/write org "ipl_aim

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                          
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss org gau
  -sigma		    "ipl_sigma0	
  -sup                      "ipl_support0

/del org

/write gau "gau_file

"read_gau
!/read  gau "gau_file

/thres gau seg_all 
  -low 			    "ipl_lower0
  -up			    "ipl_upper0		
  -value                    127
  -unit                     "ipl_unit0
/del gau

!consider saving gfilt only

/bounding_box_cut
  -input                     seg_all
  -output                    seg
  -z_only                    false
  -border                    1 1 1
/del seg_all

!!! 
/write seg "ipl_segaim

! Periodontal region "0"
! ----------------------

!/read seg_0 "ipl_segaim

/gobj_to_aim "ipl_gobj0 gobj   "ipl_peel0
/dilation    gobj 	dil
 -dilate_distance      "dil_nb
/subtract    dil        gobj   ring
/write       ring      "mask0_file
/copy   seg  seg0
/gobj 	     seg0      "mask0_file
 
/set    seg0   30

! Periodontal region "1"
! ----------------------

/gobj_to_aim "ipl_gobj1 gobj   "ipl_peel1
/dilation    gobj 	dil
 -dilate_distance      "dil_nb
/subtract    dil        gobj   ring
/write       ring      "mask1_file
/copy   seg  seg1
/gobj 	     seg1      "mask1_file
 
/set    seg1   60

! Merge regions "0" & "1" to full 
! -------------------------------

/concat seg0 seg1 seg01
  -common_region_only        false
  -add_not_overlay           true
 
/concat seg seg01 seg_colors
  -common_region_only        false
  -add_not_overlay           false       !!! change to true to reduce file size

/write seg_colors "ipl_segaim
..
$ GOTO  ANALYSIS







/concat mask seg mask_0
  -common_region_only        false
  -add_not_overlay           true
/del mask

/copy  mask_0 mask_1
 
/gobj  mask_0 "ipl_gobj0 "ipl_peel0
/gobj  mask_1 "ipl_gobj1 "ipl_peel1

/set mask_0 127 0
/set mask_1 127 0

/write mask_0 "mask0_file
/write mask_1 "mask1_file

! Make GOBJs:
! -----------
/togobj_from_aim    mask_0  "mask0_gobj   0 0       
  -curvature_smooth         5
/togobj_from_aim    mask_1  "mask1_gobj   0 0       
  -curvature_smooth         5

/del mask_0
/del mask_1

! Make SEGs:
! ----------
/set   seg    127 0
/ren   seg    seg_0
/copy  seg_0  seg_1

/gobj  seg_0  "mask0_file
/gobj  seg_1  "mask1_file

/write seg_0  "seg_0_file
/write seg_1  "seg_1_file

..
$! EXIT
$!
$ ANALYSIS:
$!
$ IF (ipl_misc1_0 .EQS. "N") .OR. (ipl_misc1_0 .EQS. "NO") THEN GOTO ENDCOM
$!
$! --------------------------|
$! Morphometric calculations |
$! --------------------------|
$!
$ VOI_0_SIDE_A:
$!
$ SEG_FILE  = SEG_0_FILE
$ MASK_FILE = MASK0_FILE
$ GOBJ_FILE = IPL_GOBJ0
$ PEEL_ITER = IPL_PEEL0
$ SIDE 	    = F$EXTRACT(8,10,side0_name) - "_"  
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/read mask "mask_file

/db_clear_eval seg 

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gobj_file
  -peel_iter                 "peel_iter
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gobj_file
  -peel_iter                 1
  -region_number             1

!!! TRI used for full calvarial thichness; Use MASK instaed of SEG.
  
/tri seg tri
  -gobj_filename             none   !!! instead of gobj_from_log for cort                    
  -peel_iter                 -1
  -ip_sigma                  0.000000
  -ip_support                0
  -ip_threshold              50
  -nr_ave_iter               2
  -t_dir_radius              2
  -epsilon                   1.200000
  -size_image                512 512
  -scale_image               0.700000
  -edges                     false
  -nr_views                  0
                                   
!!! Thickness of mask:             

/dt_object
  -input                     mask
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write out "ipl_fname0

 
!!! Sp of voids:

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write out "ipl_fname2              

..
$ UCT_LIST_0:
$! For the VOI 0:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'SIDE'.TXT
$!
$!------------------------------------------------------------------------------
$       COMMANDFILE := SYS$SCRATCH:ULIST_'FILENAME'.COM
$       SHOW SYMBOL COMMANDFILE
$!------------------------------------------------------------------------------
$       OPEN/WRITE OUTFILE 'COMMANDFILE'
$!------------------------------------------------------------------------------
$ WRITE OUTFILE "$! Reading out 3D result database and putting it into appended .txt files"
$ WRITE OUTFILE "$!"
$ WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_ALL'"") .EQS. """" "
$ WRITE OUTFILE "$ THEN"
$ WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_ALL'"
$ WRITE OUTFILE "$ ENDIF"
$ WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_LOG'"") .EQS. """" "
$ WRITE OUTFILE "$ THEN"
$ WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_LOG'"
$ WRITE OUTFILE "$ ENDIF"
$!
$ WRITE OUTFILE "$ UCT_LIST"
$ WRITE OUTFILE "UU:UCT_3D_LIST_NOHEAD.TXT"
$ WRITE OUTFILE "''D3RESULT'"
$ WRITE OUTFILE "0" ! DEFAULT UNIT
$ WRITE OUTFILE "''EVAL_MEASNO'"
$ WRITE OUTFILE "''EVAL_MEASNO'"
$!
$ WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_ALL'"
$ WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_LOG'"
$!
$ WRITE OUTFILE "$ DELETE ''D3RESULT';"
$ WRITE OUTFILE "$ EXIT"
$!
$!------------------------------------------------------------------------------
$       CLOSE OUTFILE
$!------------------------------------------------------------------------------
$!      SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$!
$!------------------------------------------------------------------------------
$ VOI_1:
$!
$ SEG_FILE  = SEG_1_FILE
$ MASK_FILE = MASK1_FILE
$ GOBJ_FILE = IPL_GOBJ1
$ PEEL_ITER = IPL_PEEL1
$ SIDE 	    = F$EXTRACT(8,10,side1_name) - "_"  
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/read mask "mask_file

/db_clear_eval seg 

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gobj_file
  -peel_iter                 "peel_iter
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "gobj_file
  -peel_iter                 1
  -region_number             1

!!! TRI used for full calvarial thichness; Use MASK instaed of SEG.
  
/tri seg tri
  -gobj_filename             none   !!! instead of gobj_from_log for cort                    
  -peel_iter                 -1
  -ip_sigma                  0.000000
  -ip_support                0
  -ip_threshold              50
  -nr_ave_iter               2
  -t_dir_radius              2
  -epsilon                   1.200000
  -size_image                512 512
  -scale_image               0.700000
  -edges                     false
  -nr_views                  0
                                   
!!! Thickness of mask:             

/dt_object
  -input                     mask
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname1

/write out "ipl_fname0

 
!!! Sp of voids:

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write out "ipl_fname2              

..
$ UCT_LIST_1:
$! For the VOI 1:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'SIDE'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'SIDE'.TXT
$!
$!------------------------------------------------------------------------------
$       COMMANDFILE := SYS$SCRATCH:ULIST_'FILENAME'.COM
$       SHOW SYMBOL COMMANDFILE
$!------------------------------------------------------------------------------
$       OPEN/WRITE OUTFILE 'COMMANDFILE'
$!------------------------------------------------------------------------------
$ WRITE OUTFILE "$! Reading out 3D result database and putting it into appended .txt files"
$ WRITE OUTFILE "$!"
$ WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_ALL'"") .EQS. """" "
$ WRITE OUTFILE "$ THEN"
$ WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_ALL'"
$ WRITE OUTFILE "$ ENDIF"
$ WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_LOG'"") .EQS. """" "
$ WRITE OUTFILE "$ THEN"
$ WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_LOG'"
$ WRITE OUTFILE "$ ENDIF"
$!
$ WRITE OUTFILE "$ UCT_LIST"
$ WRITE OUTFILE "UU:UCT_3D_LIST_NOHEAD.TXT"
$ WRITE OUTFILE "''D3RESULT'"
$ WRITE OUTFILE "0" ! DEFAULT UNIT
$ WRITE OUTFILE "''EVAL_MEASNO'"
$ WRITE OUTFILE "''EVAL_MEASNO'"
$!
$ WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_ALL'"
$ WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_LOG'"
$!
$ WRITE OUTFILE "$ DELETE ''D3RESULT';"
$ WRITE OUTFILE "$ EXIT"
$!
$!------------------------------------------------------------------------------
$       CLOSE OUTFILE
$!------------------------------------------------------------------------------
$!      SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$!
$!
$ ENDCOM:
$ EXIT
