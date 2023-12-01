$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$! 
$! 
$! Define mid-diaphyseal ring height at ~1 mm (Upper3)
$! Define thres for cortical bone (lower1) but lower values for mask (lower2). 
$! Variables (MISC): Last CL|#dilat_ero|Ring height (slice #)|Dims of box?|Ring pos (%)|Scale factor
$! DT spacing analyzes voids morphometry (DT object is for solid ring)
$! - also produces moment of inertia (MOI) file. $! Define mid-diaphyseal ring height at ~1 mm (last parameter in VOI in #slice)
$!
$! EVAL: UE:UCT_EVALUATION_V6.COM|UE:YG_MIDSHAFT_MASK_lo_thres.COM|UE:UCT_EVALUATION_V6_MOIRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_3DRESULT_APPEND.COM|UE:UCT_EVALUATION_V6_PRSUCT.COM 
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file       :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	seg_f_file     :=  'DEV''DIR''FILENAME'_FULL_SEG.AIM
$	seg_c_file     =    IPL_SEGAIM      			! Should be '_CORT_SEG.AIM'
$	seg_r_file     :=  'DEV''DIR''FILENAME'_RING_SEG.AIM	! After voids deletion
$	out_mask       :=  'DEV''DIR''FILENAME'_GOBJ.AIM
$!for testing:
$	seg_d_file     :=  'DEV''DIR''FILENAME'_dil_SEG.AIM	! After voids deletion
$	seg_e_file     :=  'DEV''DIR''FILENAME'_ero_seg.AIM
$! 
$	cl_last_rank  =  ipl_misc1_0
$	dilation_nr   =  ipl_misc1_1
$	erosion_nr    = 'dilation_nr' + 1
$	border	      =  dilation_nr * 2 + 1
$ 	ring_height   =  ipl_misc1_2  
$	dims_of_box   =  ipl_misc1_3 
$ 	ring_pc_pos   =  ipl_misc1_4  
$	down_scale    =  ipl_misc1_5
$	surf_peel     =  down_scale
$	redo_gfilt    =  ipl_misc1_6
$	sh sym dilation_nr
$!
$! ON ERROR THEN EXIT
$ IF ipl_misc1_7 .NES. "" THEN GOTO 'ipl_misc1_7'
$ GOTO SEG 
$! GOTO END_MASKING
$! GOTO ANALYSIS 
$!
$ SEG:
$ IF  F$SEARCH(gau_file) .NES. ""
$ THEN
$  IF 	redo_gfilt .EQS. "YES"  .OR.  redo_gfilt  .EQS. "Y"
$  THEN	
$       READ_ORG   =  "!!!   ***  Entire ISQ was used, new GFILT is generated  ***"
$       READ_GAU   =  "!!!   ***  New GFILT generated  *** "
$       KEEP_GAU   =  "!/del  gau "
$  ELSE 
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_ORG   =  "!/read org ''ipl_aim' "
$       KEEP_GAU   =  " /del  gau "
$	READ_GAU   =  " /read gau ''gau_file' "
$  ENDIF
$ ENDIF
$!
$ IF 	dims_of_box  .EQS. "N" .OR. dims_of_box  .EQS. "NO"   
$ THEN	
$       ipl_voix   = 0
$       ipl_voiy   = 0
$       ipl_voiz   = 0
$	ipl_voidx  = -1
$	ipl_voidy  = -1
$	ipl_voidz  = -1
$ ENDIF
$ IPL_BATCH
  
!
!   Segmentation
!

/db_scanco_activate true

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix  "ipl_voiy  "ipl_voiz 
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz      
!!! Important: use "ipl_voi...  here, only if white box is defined in the eval window
!!! Last variable defines if the box dimensions are used (Y/N)

"read_org
!/read  org "ipl_aim

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0                                           
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_lp  org gau                                                  
  -sigma                     "ipl_sigma0
  -support                   "ipl_support0

/write gau "gau_file
"read_gau

/gobj gau "ipl_gobj2

/threshold  gau  seg_hi_big
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0	

/bounding_box_cut seg_hi_big seg_hi
  -z_only  false
  -border  5 5 0  

/del seg_hi_big

/threshold  gau  seg_lo
  -low         "ipl_lower1  
  -upp	       "ipl_upper1
  -value       127
  -unit	       "ipl_unit1	

"keep_gau 
!/del gau

/bounding_box_cut seg_lo seg_lo2
  -z_only  false
  -border  0  

/del seg_lo

! cl to remove outer debris but not the epiphysis:
/cl_nr_extract             
  -input                     seg_lo2
  -output                    cl
  -min_number                20000
/del seg_lo2

/cl cl 
  -first_rank                1
  -last_rank                 "cl_last_rank

/bounding_box_cut cl seg_lo
  -z_only false
  -border  1 1 1  

/write seg_lo "seg_f_file

!----------------------------------------
! save full AIM in a minimum size volume:

/copy seg_lo box
/set box 127 127
/togobj box  "ipl_gobj0
/del box 
/gobj org "ipl_gobj0
/bound org org_bb
/write org_bb "ipl_aim
/del org
/del org_bb
/gobj gau "ipl_gobj0  
/bound gau gau_bb
/write gau_bb "gau_file
!----------------------------------------

! Instead of CL seg_hi, use seg_lo after CL as mask

/gobj seg_hi "seg_f_file
/bounding_box_cut seg_hi seg_bb
  -z_only false
  -border  1 1 1  
/ren   seg_bb   seg_hi

/write seg_hi "seg_c_file
/write seg_hi "out_mask
! will be used for masking only, with or without corr.
..
$ MASKING:
		!--------------------------|
		!  Masking of Total Volume |
		!--------------------------| 
$! If correction of outer mask is complete (_corr.gobj):
$ IF F$SEARCH(ipl_gobj2) .NES. ""
$ THEN
$ COPY 'ipl_gobj2' 'ipl_gobj0'
$ GOTO END_MASKING
$ ENDIF	
$!
$! Correction for broken bones (_blok.gobj):
$ IF F$SEARCH(ipl_gobj3) .NES. ""
$ THEN
$ IPL_BATCH
/read seg "seg_c_file
/gobj_to_aim "ipl_gobj3 corr  "ipl_peel3
/concat corr seg 	mask
/write  mask  "out_mask 
..
$ ENDIF	
$!
$ IPL_BATCH
/read seg_hi "out_mask
/read seg "seg_f_file    !!! Low thres, usually done with seg_c_file !!!
!!! Done with seg_hi/out_mask to avoid outer spickles.

! For high-res volumes, downscale before dil_ero and cl
/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because seg_hi was Gobj'ed with full.aim 
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

/concat ero seg_hi mask
  -common_region_only false
  -add_not_overlay    false

/togobj_from_aim  mask "ipl_gobj0
 -curvature_smooth   5

!/write mask "out_mask
..                      
$ END_MASKING:
$!----------------
$ IPL_BATCH
/read  full "seg_f_file
/gobj  full "ipl_gobj0
/write full "seg_f_file
..                      
$! EXIT
$! 
$!--------------------------------------------|
$!  Isolation of mid-diaphyseal cortical ring |
$!--------------------------------------------|
$!
$ pipe aix 'SEG_F_FILE' | search sys$pipe "!> dim" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> dim"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimz = f$element(2," ",dim_clean)
$ sh sym dimz
$ ipl_voiz = dimz  * ring_pc_pos / 100
$! Define 1 mm height for ring:
$! ring_height = ipl_misc1_2
$ sh sym ipl_voiz
$ sh sym ring_height  
$!----------------
$ IPL_BATCH
             
/read in "seg_c_file 
                          
/sub_get
  -input                     in
  -output                    ring
  -pos                        0  0 "ipl_voiz
  -dim                       -1 -1 "ring_height
  -global_pos_flag           false
/del in

!!! The outer gobj (ipl_gobj0) was created from high thres bone. 
!!! The Full seg is from low thres but Gobj with ipl_gobj0.

!/read mask "out_mask
/gobj_to_aim "ipl_gobj0  mask 
/write mask "out_mask

/concat  mask ring  mask_c
  -common_region_only        true
  -add_not_overlay           false

/togobj_from_aim mask_c "ipl_gobj1
 
/copy ring seg_c

!------------------|
! Make 'Ring' mask |
!------------------|

/inv  ring  "ipl_gobj1
/cl   ring  
/inv  ring  "ipl_gobj1

!!!  ring is now the cortical wall only w/o BM and pores
/writ ring  "seg_r_file 

/gobj seg_c "seg_r_file

/writ seg_c "seg_c_file
                     
..
$!----------------
$ ANALYSIS:
$ FULL:
$ IPL_BATCH
!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "seg_f_file  
/db_clear_eval seg
/db_scanco_activate true

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/vox_scanco_param
  -input                     seg

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
  -region_number             0
..
$ UCT_LIST_F:
$! For the entire femur:
$!
$! Generate RESULT list and append to PROJECT txt file:
$ D3RESULT	:= 'EVAL_DIR''EVAL_FNAME'_'EVAL_PROJECTT'_FULL.TXT
$ D3RESULT_ALL	:= 'EVAL_DIR''EVAL_FNAME'_3DRESULTS_'EVAL_PROJECTT'_FULL.TXT
$ D3RESULT_LOG	:= UCT_RESULTS:UCT_LIST_3DLOG_'EVAL_PROJECTT'_FULL.TXT
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
$! EXIT
$ CORT:
$ IPL_BATCH

!------------------------|
!  Morphometric analysis |
!------------------------|

/read seg "ipl_segaim  
/db_clear_eval seg
/db_scanco_activate true

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

! To obtain meaningful porosity volume, VOX is run in the RING mask:
! TV - BV = PORES VOLUME  
/voxgobj_scanco_param
  -input                     seg
  -gobj_filename             "seg_r_file
  -peel_iter                 0

/read org  "ipl_aim

! apparent density
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
  -region_number             0

! tissue (matrix) density of segmented volume
/voxgobj_scanco_param
  -input                     org
  -gobj_filename             "ipl_segaim
  -peel_iter                 2
  -region_number             1

..
$! EXIT
$ ON ERROR THEN CONTINUE
$ PURGE 'IPL_AIM'
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_segaim

/sup seg
  -supdim_numbers            4 4 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/moment2d_of_inertia
  -input                     seg
  -fileout_or_screentab      "ipl_fname0
  -turnangle_cw              0.000000
  -gobj_filename             "ipl_gobj1
  -peel_iter                 0

/db_set_mean_accur 
  -input                     seg 
  -region_number             1
  -param_code                4
  -min_number_pixels         6

..
$! EXIT
$!
$! REMOVE EXIT ABOVE, IF YOU SCAN MORE THAN E.G. 50 SLICES, AND YOU WANT TO
$! CALCULATE ALSO DIRECT MEASURES
$!
$! CONSIDER REMOVING VOIDS IN CORTICAL RING BEFORE DT
$!
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

!----------------------------------------------------------------------|
!  Remove voids in cortical bone before DT analysis by using ring_mask |
!----------------------------------------------------------------------|
/read seg "seg_r_file

! Cortical Thickness:
! -------------------
/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj1
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname2

/transparent_concat        
  -input_solid               out
  -input_transp              "seg_f_file
  -output                    th

/write th "ipl_fname1

..
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

!------------------------------------------------------------|
!  Analysis of cortical porosity using TRI (BV/TV is PoV/TV) |
!  Can be deleted as performed earlier as VOX !!!            |
!------------------------------------------------------------|
!--------------------------------------------------------------------------|
!  Analysis of cortical pores mean size using DT_Sp (Tb.Sp is Po diameter) |
!--------------------------------------------------------------------------|

/read seg "ipl_segaim

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "seg_r_file
  -peel_iter                 -1
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4

/transparent_concat        
  -input_solid               out
  -input_transp              "seg_r_file
  -output                    pores

/write pores "ipl_fname3
..
$ V1 == "@YGCOM:VERSION1.COM"
$ V1 'seg_f_file'
$ V1 'ipl_segaim'
$ V1 'seg_r_file'
$ V1 'out_mask'
$ V1 'ipl_fname1'
$ V1 'ipl_fname2'
$ V1 'ipl_fname3'
$ V1 'ipl_fname4'
$!
$ ORG_COM := 'EVAL_DIR''EVAL_FNAME'_EVAL_'EVAL_PROJECTT'.COM 
$ NEW_COM := 'EVAL_DIR''EVAL_FNAME'_CORT_'EVAL_PROJECTT'.COM 
$ RENAME/NOCONFIRM 'ORG_COM' 'NEW_COM'
$ EXIT
