$!
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
$!  The first segmented volume (high dens) will be solid, the second transparent
$!  in the combined image. If there is an overlap between first and second
$!  input volumes: the solid volume wins over the transparent volume.
$!  NOTE: ipl_lower0 must be greater than ipl_lower1
$!                                              
$! 
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")             
$       MASK_FILE    :=    'DEV''DIR''FILENAME'_MASK.AIM      
$       ORG_GOBJ     :=    'DEV''DIR''FILENAME'_ORG.GOBJ
$      
$ sh sym org_gobj
$!  	
$  IF 'ipl_support1' .GE. 'ipl_support0'
$  THEN
$     ipl_support = ipl_support1
$  ELSE
$     ipl_support = ipl_support0
$  ENDIF
$  sh sym ipl_support
$  ON ERROR THEN EXIT
$!
$ file = F$SEARCH(org_gobj)
$ sh sym file
$  IF F$SEARCH(org_gobj) .EQS. ""
$  THEN
$     COPY 'ipl_gobj0' 'org_gobj'
$ sh sym ipl_gobj0
$     IPL_BATCH 
! Smoothing of GOBJ:
/gobj_to_aim  "ipl_gobj0 mask
/dil mask dil5 5 
/ero dil5 ero5 5
/dil ero5 mask 5
/togobj mask "ipl_gobj0
 
..
$  ENDIF                                                                   
$! GOTO ANALYSIS
$ IPL_BATCH  	                                                  
!
! write VOI to disk (as AIM)
! ----------------------------------------   


/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz
/write org  "ipl_aim
   -compress  bin   

/gobj org "ipl_gobj0 0
/bound org org_bb
  -z_only 		     false
  -border                    0
/ren org_bb org

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org seg
  -sigma       "ipl_sigma0
  -support     "ipl_support0
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -unit	       "ipl_unit1
  -value       127 
 
/seg_gauss org seg1
  -sigma       "ipl_sigma1
  -support     "ipl_support1
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -unit	       "ipl_unit1
  -value       127                                       

/del org

/gobj seg  "ipl_gobj0 "ipl_peel0
/gobj seg1 "ipl_gobj0 "ipl_peel0
                                        
! seg & seg0 are particles. Seg1 is bone. 

/dil seg seg0 2
/ero seg0 seg2 2
/ren seg2 seg0
/set seg0 60  0
/set seg1 40  0

/concat  
  -input1              seg1
  -input2              seg0
  -output              out
  -common_region_only  true
  -add_not_overlay     false
  -make_edge           false
                 
/thres out bone   40 40 
  -value          127 
  -unit  	  5    	
/del out 
/erosion_dilat_variable    
  -input                bone
  -output               clean_bone
  -erode_distance       1
  -dilate_distance      1
  -open_not_close       true
  -continuous_at_boundary  0
/ren   clean_bone bone            
/gobj  bone "ipl_gobj0 "ipl_peel0

/write bone "ipl_fname1
  -compress  bin
/set bone 40 0
! So now, value 40 in 'bone' is only from ipl_lower1 (~160) to ipl_lower0
!(~280) - the dilated volume of the particles and the ring of gradient. 

/ren seg0 part
/set part 60 0

/gobj  part   "ipl_gobj0 "ipl_peel0 
/write part   "ipl_fname0
   -compress  bin

/concat part bone out
  -common_region_only     false
  -add_not_overlay        false 

/write  out    "ipl_segaim
  -compress    bin

! Generate a ring mask on the surface of the particles and use it as a GOBJ for
! the bone implant contact (bic_mask)


!/set  part  127 0
!/dil  part  part_dil 1
!/subtract part_dil part bic_mask
!/write bic_mask "ipl_fname3  
!   -compress   bin    

!/gobj bone "ipl_fname3 0 
!/ren bone bic
!/set bic  100 0
	              
!/write bic "ipl_fname2  
!   -compress   bin    

!/concat out bic all
!  -common_region_only     false
!  -add_not_overlay        false  

/write all     "ipl_segaim
   -compress   bin
/del out
!/copy all temp
!/set temp 127 0
!/gobj temp "ipl_gobj0 "ipl_peel0 
!/write temp    "ipl_fname4
!   -compress    bin


..
$ ANALYSIS:
$! Analysis of the bone implant suface region:
$!----------------------------------------------------------------
$!
 !SEG_FILE = ipl_fname2 
$ sh sym seg_file
$ IPL_BATCH
!/db_scanco_activate 	     true

!/read  seg    "seg_file
!  -compress  bin

!/db_clear_eval               seg   

!/vox_scanco_param
!  -input                     seg
                                   
! apparent density 
!/read org "ipl_aim
!/voxgobj_scanco_param
!  -input                     org
!  -gobj_filename             "ipl_gobj0
!  -peel_iter                 "ipl_peel0
!  -region_number 	     0

! tissue (matrix) density of segmented volume             
!/voxgobj_scanco_param
!  -input                     org
!  -gobj_filename             "seg_file
!  -peel_iter                 1
!  -region_number 	     1

!/del org 

!/sup seg                                
!  -supdim_numbers            2 2 1
!  -testoff_pixels            0 0 0
!  -suppos_pixels_local       -1 -1 -1
!  -subdim_pixels             -1 -1 -1

!/tri seg tri                      
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -ip_sigma                  0.000000
!  -ip_support                0
!  -ip_threshold              50
!  -nr_ave_iter               2
!  -t_dir_radius              2
!  -epsilon                   1.200000
!  -size_image                512 512
!  -scale_image               0.700000
!  -edges                     false

..
$ UCT_LIST_OI:
$! OI for the BIC region:
$!
$! Generate RESULT list and append to PROJECT txt file:
$! D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_BIC.TXT
$! D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_BIC.TXT
$! D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_BIC.TXT
$!
$!------------------------------------------------------------------------------
$       COMMANDFILE := SYS$SCRATCH:ULIST_'FILENAME'.COM
$       SHOW SYMBOL COMMANDFILE
$!------------------------------------------------------------------------------
$       OPEN/WRITE OUTFILE 'COMMANDFILE'
$!------------------------------------------------------------------------------
$! WRITE OUTFILE "$! Reading out 3D result database and putting it into appended .txt files"
$! WRITE OUTFILE "$!"
$! WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_ALL'"") .EQS. """" "
$! WRITE OUTFILE "$ THEN"
$! WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_ALL'"
$! WRITE OUTFILE "$ ENDIF"
$! WRITE OUTFILE "$ IF F$SEARCH(""''D3RESULT_LOG'"") .EQS. """" "
$! WRITE OUTFILE "$ THEN"
$! WRITE OUTFILE "$   COPY UU:UCT_3D_LIST_HEADER.TXT ''D3RESULT_LOG'"
$! WRITE OUTFILE "$ ENDIF"
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
$     SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$! Analysis of the particles region:
$! ----------------------------------------------------------- 
$ ON ERROR THEN CONTINUE
$ SEG_FILE = ipl_fname0
$ IPL_BATCH

/db_scanco_activate 	     true

/read  seg    "seg_file
  -compress  bin

/db_clear_eval               seg   

/vox_scanco_param
  -input                     seg
                                   
! apparent density 
/read org "ipl_aim
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number 	     0

! tissue (matrix) density of segmented volume             
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "seg_file
  -peel_iter                 1
  -region_number 	     1

/del org 

/sup seg                                
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

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

..
$ ON ERROR THEN CONTINUE
$ SEG_FILE = ipl_fname0
$ IPL_BATCH

/db_scanco_activate true

/read seg "seg_file

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate true

!/read seg "seg_file

!/dt_background
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname5

!/write  out    "ipl_fname4
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate true

!/read seg "seg_file

!/dt_mat
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname6

..
$ UCT_LIST_P:
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_P.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_P.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_P.TXT
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
$       SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$! Analysis of the new bone:
$!--------------------------------------------------------------------
$ ON ERROR THEN CONTINUE
$ SEG_FILE = ipl_fname1
$ IPL_BATCH

/db_scanco_activate 	     true

/read  seg    "seg_file
  

/db_clear_eval               seg   

/vox_scanco_param
  -input                     seg 

! apparent density 
/read org "ipl_aim
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number 	     0
                                     
! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "seg_file
  -peel_iter                 1
  -region_number 	     1

/del org 

/sup seg                                
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

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
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "seg_file

/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate         true

!/read seg                   "seg_file

!/dt_object
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate true

!/read seg "seg_file

!/dt_background
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname5

!/write  out    "ipl_fname4
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate true

!/read seg "seg_file

!/dt_mat
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname6    

..
$ UCT_LIST_B:
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_B.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_B.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_B.TXT
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
$       SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$! Analysis of Bone+Particles (ALL)
$!------------------------------------------------------------------------
$ ON ERROR THEN CONTINUE
$ SEG_FILE = ipl_fname4
$ IPL_BATCH

/db_scanco_activate 	     true

/read  seg                   "seg_file
 

/db_clear_eval               seg   

/vox_scanco_param
  -input                     seg
                                 
                                   
! apparent density 
/read org "ipl_aim
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number 	     0

! tissue (matrix) density of segmented volume             
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "seg_file
  -peel_iter                 1
  -region_number 	     1

/del org 

/sup seg                                
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

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

..
$ ON ERROR THEN CONTINUE 
$ IPL_BATCH

/db_scanco_activate true

/read seg "seg_file
!/set seg 127 0
/connectivity
  -in_out                    seg
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

!/db_scanco_activate true

!/read seg "seg_file
!/set seg 127 0
!/dt_object
!  -input                     seg
!  -output                    out
!  -gobj_filename             gobj_from_log
!  -peel_iter                 -1
!  -roi_radius_factor         10000.000000
!  -ridge_epsilon             0.900000
!  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname3

!/write  out    "ipl_fname2

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "seg_file
!/set seg 127 0 

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             gobj_from_log
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
!  -histofile_or_screen       "ipl_fname5

!/write  out    "ipl_fname4
..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "seg_file
!/set seg 127 0

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
$ UCT_LIST_A:
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_A.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_A.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_A.TXT
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
$       SET NOVERIFY
$       @'COMMANDFILE'
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';
$!------------------------------------------------------------------------------
$ PURGE 'IPL_AIM'
$ PURGE 'IPL_SEGAIM'
$ PURGE 'IPL_FNAME0'
$ PURGE 'IPL_FNAME1'
$ PURGE 'IPL_FNAME2'
$ PURGE 'IPL_FNAME3'
$ EXIT

