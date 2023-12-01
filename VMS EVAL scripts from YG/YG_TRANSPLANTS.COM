$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!  Typical application: Cort/Trab. bone shown within transparent full bone.
$!
$!  Segmentation with gauss filter and thresholding.
$!  Two VOI are segmented, and then combined into a solid/transparent image
$!  The first segmented volume will be solid and undergo MORPH.
$!  The second one transparent in the combined image. If there is an overlap between first and second
$!  input volume: the solid volume wins over the transparent volume.
$!
$!  This script can take TWO contours: 
$!  the 'normal' c0001234.gobj AND optionally, c0001234_F.gobj
$!  The second object is then created with the bigger gobj file, and is
$!  concatenated transparently.
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_temp       :=  'DEV''DIR''FILENAME'_GFILT_temp.AIM
$	gau_file       :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	seg_file        =   IPL_SEGAIM 
$	seg_c_file     :=  'DEV''DIR''FILENAME'_C_SEG.AIM
$	seg_t_file     :=  'DEV''DIR''FILENAME'_T_SEG.AIM
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$	gobj_outer     :=  'DEV''DIR''FILENAME'_outer.GOBJ
$	gobj_t	       :=  'DEV''DIR''FILENAME'_T.GOBJ
$	gobj_c         :=  'DEV''DIR''FILENAME'_C.GOBJ
$	mask_pcc       :=  'DEV''DIR''FILENAME'_mask_pcc.AIM
$	seg_pcc	       :=  'DEV''DIR''FILENAME'_seg_pcc.AIM
$	fig_pcc	       :=  'DEV''DIR''FILENAME'_seg_pcc_fig.AIM
$!for testing:
$	temp_file     :=  'DEV''DIR''FILENAME'_TEMP.AIM	! After voids deletion
$	seg_e_file     :=  'DEV''DIR''FILENAME'_ero_seg.AIM
$! 
$	cl_last_rank  =  ipl_misc1_0
$! cl to remove outer debris:
$	cl_min_nb     :==  2000 
$	dilation_nr   =  15
$	erosion_nr    = 'dilation_nr' + 1
$	border	      =  dilation_nr * 2 + 1
$	down_scale    =  2
$	surf_peel     =  down_scale
$	dims_of_box   =  NO 
$	redo_gfilt    =  NO
$	sh sym dilation_nr
$	sh sym redo_gfilt
$	sh sym dims_of_box
$!
$ ON ERROR THEN EXIT
$!  GOTO END_MASKING
$!  GOTO STEP2
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

!/isq_to_aim
!  -aim_name                  org
!  -isq_filename              "ipl_isq
!  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
!  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

!/write  org    "ipl_aim
!  -compress  bin
/read org "ipl_aim

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            2
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss org gau
  -sigma       		"ipl_sigma0
  -support     		"ipl_support0

/threshold  gau  seg_lo
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -value       127
  -unit	       "ipl_unit1	

/threshold  gau  seg_hi
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0
	
/gauss_seg org seg_for_mask
  -sigma       		1.2
  -support     		2
  -lower_in_perm_aut_al	"ipl_lower1

/del org

! processing of cort and trab seg:
/cl_nr_extract
  -input                     seg_lo
  -output                    cl_trab
  -min_number                10
/write cl_trab "seg_t_file

/cl_nr_extract
  -input                     seg_hi
  -output                    cl_cort
  -min_number                10
/write cl_cort "seg_c_file

! processing of seg for mask only:
/cl_nr_extract
  -input                     seg_for_mask
  -output                    cl_for_mask
  -min_number                "cl_min_nb

/ren cl_for_mask seg_lo                 
! For high-res volumes, downscale before dil_ero and cl
/scale_elsize  seg_lo sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because seg_lo has no Gobj yet. 
/set dil 0 127
/cl  dil                                                                          
/set dil 0 127

/erosion
  -input                     dil                                            
  -output                    sca
  -erode_distance            "erosion_nr
  -use_previous_margin       true

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale                                    
  -integrate		     false

/set ero 50 0
/concat ero cl_cort mask
  -common_region_only false
  -add_not_overlay    false

/cl mask 
/togobj_from_aim  mask "gobj_outer
 -curvature_smooth   5              

/write mask "out_mask
..
$ END_MASKING:
$ IPL_BATCH
/read seg_c "seg_c_file
!/read seg_t "seg_t_file
/bound seg_c fill false 5

/inv fill "gobj_outer 1 
/cl  fill 
/write fill "temp_file
/scale_elsize  fill sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           5

/erosion
  -input                     dil                                            
  -output                    sca
  -erode_distance            6
  -use_previous_margin       true

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale                                    
  -integrate		     false

/concat ero fill mask
  -common_region_only false
  -add_not_overlay    false

! Additional dilat_ero_dilat of the inner contour:

/dilation
  -input                     mask
  -output                    dil
  -dilate_distance           1

/erosion
  -input                     dil                                            
  -output                    ero
  -erode_distance            2
  -use_previous_margin       true

/dilation
  -input                     ero
  -output                    mask
  -dilate_distance           1

/togobj_from_aim  mask "gobj_t
 -curvature_smooth   5              

!/gobj_to_aim  "gobj_outer mask_out
/read mask_out "out_mask

/subtract mask_out mask mask_c

/togobj_from_aim  mask_c "gobj_c
 -curvature_smooth   5   
..
$! Generating all masks:
$ STEP2:
$! exit
$ IPL_BATCH
! seg_c was generated with high thres, seg_t with low thres.

! CORT seg file:
/read cort "seg_c_file
/gobj cort "gobj_c 
/writ cort "seg_c_file

! TRAB seg file:
/read trab "seg_t_file
/gobj trab "gobj_t
/writ trab "seg_t_file

!Percent cortical coverage mask and seg:
/gobj_to_aim "gobj_outer mask_out
/erosion     mask_out ero  1
/subtract    mask_out ero  mask_pcc
/write       mask_pcc "mask_pcc

!/gobj_to_aim "gobj_c  gobj_c
!/gobj        gobj_c   "mask_pcc
!/dil 	     gobj_c   dil      2
!/ero	     dil      seg_pcc  2
!/write       seg_pcc   "seg_pcc
/set 	     cort     50 0
/concat	     mask_out cort fig
  -common_region_only false
  -add_not_overlay    false
/write 	     fig      "fig_pcc

 
..
$exit


/gobj
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0












/write  seg    "ipl_fname0
  -compress  bin

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support1
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org seg1
  -sigma       "ipl_sigma1
  -support     "ipl_support1
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -unit	       "ipl_unit1
  -value       127

/gobj
  -input_output              seg1
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1

/write  seg1    "ipl_fname1
  -compress  bin

/transparent_concat
  -input_solid               seg
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
..
$ IF ipl_misc1_0 .eqs. "0" .OR. ipl_misc1_0 .eqs. "NO" .OR. ipl_misc1_0 .eqs. "N"
$ THEN 
$	WRITE SYS$OUTPUT "	*** No CL was performed ***"
$	GOTO ENDCOM
$ ENDIF
$!
$ CL_NR:
$ IF  ipl_misc1_0 .GT. 6 
$ THEN 
$!
$   WRITE SYS$OUTPUT "	*** CL_NR was performed to clear out objects < ''ipl_misc1_0' voxels ***"
$   IPL_BATCH
/read seg   "ipl_fname0
/read seg1  "ipl_fname1
/cl_nr_extract
  -input                     seg
  -output                    cl
  -min_number                "ipl_misc1_0
                 
/transparent_concat
  -input_solid               cl
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
/write  cl     "ipl_fname0
  -compress  bin
..
$   GOTO ENDCOM
$ ENDIF
$ CL:
$ IF  ipl_misc1_0 .GE. 1 
$ THEN
$!
$   WRITE SYS$OUTPUT "	*** CL was performed to clear out objects < rank ''ipl_misc1_0' ***"
$   IPL_BATCH
/read seg   "ipl_fname0
/read seg1  "ipl_fname1

/cl_ow_rank_extract
  -input_output              seg
  -first_rank                1
  -last_rank                 "ipl_misc1_0
  -connect_boundary          false

/transparent_concat
  -input_solid               seg
  -input_transp              seg1
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
/write  seg    "ipl_fname0
  -compress  bin
..
$   GOTO ENDCOM
$ ENDIF
$ ENDCOM:
$ IPL_BATCH

/db_scanco_activate 	     true

/read  seg    "ipl_fname0
  -compress  bin

/gobj_maskaimpeel_ow
  -input_output              seg
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

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
  -gobj_filename             "ipl_fname0
  -peel_iter                 2
  -region_number 	     1
..
$ UCT_LIST:
$! For the VOI1 (Seg1):
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_BV.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_ALL_'EVAL_PROJECTT'_BV.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_BV.TXT
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
$       DELETE/NOLOG/NOCONFIRM 'COMMANDFILE';*
$!------------------------------------------------------------------------------
$! PURGE 'ipl_segaim'
$ PURGE 'ipl_aim'
$ PURGE 'ipl_fname0'
$ EXIT
