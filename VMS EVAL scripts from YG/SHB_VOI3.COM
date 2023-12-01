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
$!  Two VOI are segmented, and then combined into a solid/transparent image
$!  The first and second segmented volumes (high dens) will be solid, the third transparent
$!  in the combined image. If there is an overlap between first and second
$!  input volumes: the solid volumes win over the transparent volume.
$!  NOTE: ipl_lower0 must be greater than ipl_lower1 & 2
$!
$! 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$!
$	GAU_FILE     :=  'DEV''DIR''FILENAME'_GFILT.AIM	
$!
$	SEG_FILE   :=  'DEV''DIR''_NAME'_SEG.AIM 	
$  
$  	MASK_FILE   :=  'DEV''DIR''_NAME'_MASK.AIM	
$ 
$ IF 'ipl_support1' .GE. 'ipl_support0'
$ THEN
$     ipl_support = ipl_support1
$ ELSE
$     ipl_support = ipl_support0
$ ENDIF
$!
$ ON ERROR THEN EXI!
$ sh sym ipl_support
$!
$! GOTO SMO
$ IPL_BATCH
!  
! 
! create .AIM file from ISQ
!
/db_scanco_activate true

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gau org gau
  -sigma       "ipl_sigma0
  -support     "ipl_support0
/del org

/thres gau seg_all
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0

/bounding_box_cut
  -input                     seg_all
  -output                    seg
  -z_only                    false
  -border                    1

/write seg     "ipl_segaim
   -compress  bin


! Masking the first region "0"
! ------------------------

/copy seg    seg_0
/gobj seg_0  "ipl_gobj1 "ipl_peel1 
/set  seg_0  40

! Masking the region "1"
! ------------------------
/copy seg    seg_1
/gobj seg_1  "ipl_gobj2 "ipl_peel1 
/set seg_1 100                  
! Masking the region "2"
! ------------------------
/copy seg    seg_2
/gobj seg_2  "ipl_gobj3 "ipl_peel1 
/set seg_2 150                  
                                 

! Merge  regions "0" & "1"  to full 
! -----------------------------------------
!/concat seg_1 seg_0 seg
!  -common_region_only        false
!  -add_not_overlay           false


/write seg "ipl_segaim

!Masking of all rergions
!-------------------------

/set seg 127 0           

/cl_nr_extract
  -input                     seg
  -output                    cl
  -min_number                20000
  -max_number                0
/ren cl seg

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
/write  mask_0 "mask_file 
! AT THIS POINT THE MASK CONSISTS OF THE ENTIRE OBJECT

! FOR FIGURE ONLY:
/read   seg "ipl_segaim
/gobj   seg "mask_file
/gobj   mask_0  "ipl_gobj1 "ipl_peel1
/copy   mask_0  mask_2c
/set    mask_2c 41 0
/concat mask_2c seg_3c  seg_all_0
   -common_region_only        false
   -add_not_overlay           false
/gobj   mask_1  "ipl_gobj2 "ipl_peel2
/copy   mask_1  mask_2c
/set    mask_2c 81 0
/concat mask_2c  seg_all_0 seg_all
  -common_region_only        false
  -add_not_overlay           false
/write  seg_all "seg_all_file
/del seg_3c
/del mask_2c
/del seg_all_0

/gobj  mask_0  "ipl_gobj1 "ipl_peel3
/bound mask_0 mask0 f 5
/ren   mask0 mask_0

/gobj  mask_1 "ipl_gobj2 "ipl_peel1
/bound mask_1 mask1 f 5
/ren   mask1 mask_1

/gobj  mask_2 "ipl_gobj3 "ipl_peel2
/bound mask_2 mask2 f 5
/ren   mask2 mask_2

/set mask_0 127 0
/set mask_1 127 0
/set mask_2 127 0

/write mask_0 "mask0_file
/write mask_1 "mask1_file
/write mask_2 "mask2_file



! Make GOBJs:
! -----------
/togobj_from_aim    mask_0  "mask0_gobj   0 0       
  -curvature_smooth         5
/togobj_from_aim    mask_1  "mask1_gobj   0 0       
  -curvature_smooth         5
/togobj_from_aim    mask_2  "mask2_gobj   0 0       
  -curvature_smooth         5


/del mask_0
/del mask_1
/del mask_2

! Make SEGs:
! ----------
/set   seg    127 0
/ren   seg    seg_0
/copy  seg_0  seg_1
/copy  seg_0  seg_2

/gobj  seg_0  "mask0_file
/gobj  seg_1  "mask1_file
/gobj  seg_2  "mask2_file

/bound seg_0  seg0 f 5
/write seg0  "seg_0_file
/bound seg_1  seg1 f 5
/write seg1  "seg_1_file
/bound seg_2  seg2 f 5
/write seg2  "seg_2_file


..
$! EXIT
$!
$!
$! --------------------------|
$! Morphometric calculations |
$! --------------------------|
$!
$ VOI_
$ SEG_FILE  = 
$ 
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
$!
$ VOI_1:
$!
$ SEG_FILE  = SEG_1_FILE
$ MASK_FILE = MASK1_FILE
$ GOBJ_FILE = MASK1_GOBJ
$ PEEL_ITER = 0       
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
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'SIDE1'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'SIDE1'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'SIDE1'.TXT
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
 WRITE OUTFILE "$ APPEND ''D3RESULT' ''D3RESULT_ALL'"
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
$! $ VOI_2:
$!
$ SEG_FILE  = SEG_2_FILE
$ MASK_FILE = MASK2_FILE
$ GOBJ_FILE = MASK2_GOBJ
$ PEEL_ITER = 0 
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
                                   
!/dt_object
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
$ UCT_LIST_2:
$! For the VOI 2:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_'M'.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_'M'.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_'M'.TXT
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
$!
$ ENDCOM:
$ purge 'gau_file'
$ purge 'ipl_aim'                              	   
$ PURGE 'IPL_AIM'
$ PURGE 'IPL_SEGAIM'
$ PURGE 'IPL_FNAME0'
$ PURGE 'IPL_FNAME1'
$ PURGE 'IPL_FNAME2'
$ PURGE 'IPL_FNAME3'
                                          



$ EXIT
