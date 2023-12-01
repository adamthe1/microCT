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
$!       SIDE0_NAME   = F$PARSE("''IPL_GOBJ0'",,,"NAME")
$!	SIDE1_NAME   = F$PARSE("''IPL_GOBJ1'",,,"NAME")
$!
$!	SEG_0_FILE   :=  'DEV''DIR''SIDE0_NAME'_SEG.AIM 	
$!	SEG_1_FILE   :=  'DEV''DIR''SIDE1_NAME'_SEG.AIM  
$	SEG_all_FILE :=  'DEV''DIR''FILENAME'_SEG_ALL.AIM  
$	MASK0_FILE   :=  'DEV''DIR''SIDE0_NAME'_MASK.AIM  	
$	MASK1_FILE   :=  'DEV''DIR''SIDE1_NAME'_MASK.AIM  
$	MASK_FILE    :=  'DEV''DIR'TEST_MASK.AIM  
$	MASK0_GOBJ   :=  'DEV''DIR''SIDE0_NAME'_MASK.GOBJ  	
$	MASK1_GOBJ   :=  'DEV''DIR''SIDE1_NAME'_MASK.GOBJ 
     

$  		
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
/write org "ipl_aim
/del org
/write gau "gau_file
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


/cl_nr_extract
  -input                     seg
  -output                    cl
  -min_number                200
  -max_number                0
/ren cl seg

!/dilation
!  -input                     seg
!  -output                    dil1     escr
!  -dilate_distance           3

!/bounding_box_cut dil1 dil
!  -z_only false
!  -border 1
!/ren dil seg
/set seg 127

/write seg     "ipl_segaim
   -compress  bin 
/copy seg seg0
/gobj seg0 "ipl_gobj0 "ipl_peel0
/bound seg0 seg_0 false 5
/ren seg_0 seg0
/set seg0 127 0
/write seg0 "ipl_fname0
   -compress  bin 
/copy seg seg1
/gobj seg1 "ipl_gobj1 "ipl_peel0
/bound seg1 seg_1 false 5
/ren seg_1 seg1
/set seg1 127 0
/write seg1 "ipl_fname1
   -compress  bin 

! Masking of both regions
! -----------------------

!/cl_nr_extract
!  -input                     seg
!  -output                    cl
!  -min_number                100
!  -max_number                0
!/ren cl seg

/bounding_box_cut seg mask
  -z_only false
  -border 2


/set mask 30 0


!/concat mask seg mask0
!  -common_region_only        false
!  -add_not_overlay           true
!/ren mask0 mask
!/del mask0

/copy  mask  mask_0
/copy  mask mask_1
/write  mask "mask_file                                                                



/gobj  mask_0  "ipl_gobj0 "ipl_peel0
/bound mask_0 mask0 f 2
/ren   mask0 mask_0

/gobj  mask_1 "ipl_gobj1 "ipl_peel0
/bound mask_1 mask1 f 2
/ren   mask1 mask_1

/set mask_0 127 0
/set mask_1 127 0

/write mask_0 "mask0_file
/write mask_1 "mask1_file

! Make GOBJs:
! -----------
!/togobj_from_aim    mask_0  "mask0_gobj   0 0       
!  -curvature_smooth         5
!/togobj_from_aim    mask_1  "mask1_gobj   0 0       
!  -curvature_smooth         5
          
! Masking the first region "0"
! ------------------------
!/copy  mask_0  mask_1
!/write  mask_0 "mask_file 






! AT THIS POINT THE MASK CONSISTS OF THE ENTIRE OBJECT

..
$! EXIT
$!
$!
$! --------------------------|
$! Morphometric calculations |
$! --------------------------|
$!
$ VOI_0:
$!
$ SEG_FILE  = IPL_FNAME0
$! GOBJ_FILE = MASK0_FILE
$ PEEL_ITER = 0
$! SIDE 	    = F$EXTRACT(8,10,side0_name) - "_"
$!
$ IPL_BATCH

/db_scanco_activate true  

/read seg  "seg_file
/gobj seg  "ipl_gobj0

/db_clear_eval               seg

/vox_scanco_param
  -input                     seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 0
  -region_number             0


/read org  "ipl_aim


! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 0
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org 
  -gobj_filename             seg
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
                                   
!!! Thickness :             

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write out "ipl_fname2

 
!!! Sp of voids:

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname5

/write out "ipl_fname4                    

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen      "ipl_fname6

 ..
$ UCT_LIST_0:
$! For the VOI 0:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_DAMAGE.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_DAMAGE.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_DAMAGE.TXT
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
$! VOI_1:
$!     
$ SEG_FILE  = IPL_FNAME1
$!GOBJ_FILE = MASK1_FILE
$ PEEL_ITER = 0
$! SIDE 	    = F$EXTRACT(8,10,side1_name) - "_" 
$!
$ IPL_BATCH
/db_scanco_activate true  

/read seg  "seg_file
/gobj seg  "ipl_gobj1




/db_clear_eval             seg


 

/vox_scanco_param
  -input                   seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "peel_iter
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             seg
  -peel_iter                 1
  -region_number             1

  
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
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname3

/write out "ipl_fname2

 
!!! Sp of voids:

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname5

/write out "ipl_fname4              

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname6

..
$ UCT_LIST_1:
$! For the VOI 1:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_CONTROL.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_CONTROL.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_CONTROL.TXT
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
$!-----------------------------------------------------------------------
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
$ PURGE 'IPL_FNAME4'
$ PURGE 'IPL_FNAME5'
$ EXIT
                                          



$ EXIT
