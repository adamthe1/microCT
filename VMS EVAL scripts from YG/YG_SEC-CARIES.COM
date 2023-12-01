$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM	
$	MASK_FILE    :=  'DEV''DIR''FILENAME'_TMASK.AIM 
$	SIDE0_NAME   = F$PARSE("''IPL_GOBJ0'",,,"NAME")
$	SIDE1_NAME   = F$PARSE("''IPL_GOBJ1'",,,"NAME")
$!
$	SEG_0_FILE   :=  'DEV''DIR''SIDE0_NAME'_SEG.AIM 	
$	SEG_1_FILE   :=  'DEV''DIR''SIDE1_NAME'_SEG.AIM  
$	MASK0_FILE   :=  'DEV''DIR''SIDE0_NAME'_MASK.AIM  	
$	MASK1_FILE   :=  'DEV''DIR''SIDE1_NAME'_MASK.AIM  
$	MASK0_GOBJ   :=  'DEV''DIR''SIDE0_NAME'_MASK.GOBJ  	
$	MASK1_GOBJ   :=  'DEV''DIR''SIDE1_NAME'_MASK.GOBJ 
$!		
$! GOTO VOI_0
$! GOTO UCT_LIST_1
$!
$ v1   :== @YGCOM:version1.COM
$ V1       'IPL_ORIG_ISQ' 
$ IPL_ISQ = IPL_ORIG_ISQ 
$!
$	redo_gfilt    =  ipl_misc1_1
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

/bounding_box_cut
  -input                     seg_all
  -output                    seg
  -z_only                    false
  -border                    1
 
/write seg "ipl_segaim

/thres gau seg_fill 
  -low 			    "ipl_lower1
  -up			    "ipl_upper1		
  -value                    127
  -unit                     "ipl_unit1
/del gau

/bounding_box_cut
  -input                     seg_fill
  -output                    seg_f
  -z_only                    false
  -border                    1
 
/write seg_f "seg_0_file

! Masking full tooth
! ------------------

/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dilp1
  -dilate_distance           "dilation_nr

/del sca

! For broken bones, the VOI box cuts at a clean ring (for masking)
/bounding_box_cut dilp1 dil
  -z_only true
  -border 0

/del dilp1

/set  dil 0 127
/cl   dil
/set  dil 0 127

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/bounding_box_cut  ero sca
  -z_only false
  -border 2

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false

/concat ero seg mask
  -common_region_only false
  -add_not_overlay    false

/write mask "out_mask 

! Making mask rings:
! ------------------

/copy seg_0   seg_1

! Filling "0"
! -----------

/gobj seg_0  "ipl_gobj0 "ipl_peel0 
/boun seg_0 f 5

/scale_elsize  seg_0 sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil_r1
  -dilate_distance           "dil_ring_1

/dilation
  -input                     dil_r1
  -output                    dil_r2
  -dilate_distance           "dil_ring_2

/subtract dil_r2 dil_r1 r2b
/scale_elsize  r2b r2 
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false
/gobj r2 "out_mask
/set  r2 2 0

/subtract dil_r1 sca r1b
/scale_elsize  r1b r1 
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false
/gobj r1 "out_mask
/set  r1 1 0

! depth from surface:
/scale_elsize  mask sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/erosion
  -input                     sca
  -output                    ero_d1
  -erode_distance            "ero_depth1

/erosion
  -input                     ero_d1
  -output                    ero_d2
  -erode_distance            "ero_depth2

/subtract ero_d1 ero_d2 d2b
/scale_elsize  d2b d2 
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false
/set  d2 3 0

/subtract sca    ero_d1 d1b
/scale_elsize  d1b d1 
  -down_scale                1
  -up_scale                  "down_scale
  -integrate		     false
/set  d1 6 0

! New map:   	surface--------	+1   +2
		filling   | +3   4    5
		filling   | +6   7    8

/concat r1 r2 out
  -common_region_only        false
  -add_not_overlay           true
/concat out d1 temp
  -common_region_only        false
  -add_not_overlay           true
/concat temp d2 out
  -common_region_only        false
  -add_not_overlay           true
/thres out r1d1		4 4  127
  -unit			     5   
/thres out r2d1		5 5  127
  -unit			     5
/thres out r1d2		7 7  127
  -unit			     5
/thres out r2d2		8 8  127
  -unit			     5

! Generate SEG with all colors for QC:
/write out " 




!/write seg_l "cal_l   ! no need; will be displayed in full seg.aim 

! Calvarial region "1"
! --------------------

!/read seg_r "cal_full

/copy seg    seg_1
/gobj seg_1  "ipl_gobj1 "ipl_peel1 
/set  seg_1  80

!/write seg_r "cal_r  ! no need; will be displayed in full seg.aim 


! Merge calvarial regions "0" & "1" to full 
! -----------------------------------------

/concat seg seg_0 seg_f0
  -common_region_only        false
  -add_not_overlay           false
 
/concat seg_f0 seg_1 seg
  -common_region_only        false
  -add_not_overlay           false

/write seg "ipl_segaim


! Masking of both regions
! -----------------------

/set seg 127 0           
/dilation
  -input                     seg
  -output                    dil1
  -dilate_distance           6

/bounding_box_cut dil1 dil
  -z_only false
  -border 1

/del dil1

/set dil 0 127
 
/cl dil
  -first_rank                1
  -last_rank                 1
  -connect_boundary          false
  -value_in_range            127

/set dil 0 127

/erosion
  -input                     dil
  -output                    ero
  -erode_distance            7
  -use_previous_margin       true

/del dil

/bounding_box_cut ero mask
  -z_only false
  -border 2
/del ero

/set mask 30 0
/set seg  70 0

/concat mask seg mask_0
  -common_region_only        false
  -add_not_overlay           true
/del mask

/copy  mask_0  mask_1
/writ  mask_0 "mask_file 

/gobj  mask_0  "ipl_gobj0 "ipl_peel0
/bound mask_0 mask0 f 5
/ren   mask0 mask_0

/gobj  mask_1 "ipl_gobj1 "ipl_peel1
/bound mask_1 mask1 f 5
/ren   mask1 mask_1

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

/bound seg_0  seg0 f 5
/write seg0  "seg_0_file
/bound seg_1  seg1 f 5
/write seg1  "seg_1_file

..
$! EXIT
$!
$ IF (ipl_misc1_0 .EQS. "F") .OR. (ipl_misc1_0 .EQS. "NO") THEN GOTO ENDCOM
$!
$! --------------------------|
$! Morphometric calculations |
$! --------------------------|
$!
$ VOI_0:
$!
$ SEG_FILE  = SEG_0_FILE
$ MASK_FILE = MASK0_FILE
$ GOBJ_FILE = MASK0_GOBJ
$ PEEL_ITER = 0
$ SIDE 	    = F$EXTRACT(8,10,side0_name) - "_"  
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/read mask "mask_file
/gobj seg  "mask_file

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

!!! TRI used for seg calvarial bone only (with voids). 
  
/tri seg tri
  -gobj_filename             gobj_from_log                      
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
$ GOBJ_FILE = MASK1_GOBJ
$ PEEL_ITER = 0
$ SIDE 	    = F$EXTRACT(8,10,side1_name) - "_"  
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/read mask "mask_file
/gobj seg  "mask_file

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

!!! TRI used for seg calvarial bone:
  
/tri seg tri
  -gobj_filename             gobj_from_log                    
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
$ purge 'gsu_file'
$ purge 'ipl_aim'
$ EXIT
