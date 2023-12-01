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
$!  The first segmented volume will be solid, the second one transparent
$!  in the combined image. If there is an overlap between first and second
$!  input volume: the solid (low-dens) volume wins over the transparent volume.
$!
$   ipl_gauaim  := 'EVAL_DIR''EVAL_FNAME'_GFILT.AIM
$!  If there is some highly radio-opaque particles trapped in the material,
$!  it'll be shown as separate _ROP.AIM :
$   ipl_ropaim := 'EVAL_DIR''EVAL_FNAME'_ROP.AIM
$   thres_rop   = ipl_lower0 * 3
$   sh sym thres_rop
$   ipl_rlpaim := 'EVAL_DIR''EVAL_FNAME'_RLP.AIM
$   ipl_maskc  := 'EVAL_DIR''EVAL_FNAME'_MASKC.AIM
$   ipl_temp   := 'EVAL_DIR''EVAL_FNAME'_TEMP.AIM
$!
$ ! Definitions to create sub-directory for DICOM:
$  mkdir	:== @YGCOM:MKDIR.COM
$  PRJ_DIR	:=  DK0:[MICROCT.PROJECTS.'EVAL_PROJECTTT']
$  IF prj_dir .EQS. ""  THEN  MKDIR 'PRJ_DIR'
$  truncated  	= prj_dir - "]"
$  samp_dir     := 'truncated'.'EVAL_SAMPNAMET'] 
$  sh sym samp_dir
$  IF samp_dir .EQS. ""  THEN  MKDIR 'samp_dir'
$  samp_tr_dir  = samp_dir - "]" 
$  dicoma_dir := 'samp_tr_dir'.DICOM_A]
$  sh sym dicoma_dir
$  IF F$SEARCH(dicoma_dir) .EQS. "" THEN MKDIR 'dicoma_dir'
$  dcma_file  := 'DICOMA_DIR''EVAL_SAMPNO'
$  sh sym dcma_file
$  dicomb_dir := 'samp_tr_dir'.DICOM_B]
$  sh sym dicomb_dir
$  IF F$SEARCH(dicomb_dir) .EQS. "" THEN MKDIR 'dicomb_dir'
$  dcmb_file  := 'DICOMB_DIR''EVAL_SAMPNO'
$  sh sym dcmb_file 
$!
$ ON ERROR THEN CONTINUE
$ GOTO TEST
$!
$ SEG:
$ IF IPL_MISC1_0 .EQS. "NO" THEN GOTO ANALYSIS      
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

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
  -sigma       "ipl_sigma0
  -support     "ipl_support0
/del org

!!!
!/read  gau "ipl_gauaim
/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
/write gau "ipl_gauaim
!/read  gau "ipl_gauaim

/todicom_from_aim
  -aim_name                  gau
  -dicom_filename            "dcma_file
  -multifiles                true
  -global_slicename          false

! extract tube (sample holder): done with GOBJ
      
! extract hi_thres object:
/thres gau thres
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0

! isolate radio-opaque particles (rop):
/thres gau rop
  -low         "thres_rop  
  -upp	       "ipl_upper0
  -value       100
  -unit	       "ipl_unit0
/del gau
            
/ren thres seg

/cl seg 
/bound seg seg_hi
  -z_only 		     false
  -border    		     5 
/del seg
! Now seg_hi is the device without the adjacent plastic from sample holder. 
! voids and filaments are empty inside the object

! ipl_fname1 is for first object (high density, transparent on 3D): _SEG1.AIM
/write  seg_hi    "ipl_fname1
  -compress  bin

! Highlight ROP that are inside the object:
/gobj  rop "ipl_fname1
/bound rop rop_bb 
  -z_only 		     false
  -border    		     5
/ren rop_bb rop
/write rop "ipl_ropaim

! Since object is sealed on the outside, no need for dil_ero: 
/copy   seg_hi mask
/invert mask
/cl     mask
/invert mask
/write  mask "ipl_fname0

! Show all internal voids as second object (solid on 3D): _SEG2.AIM

$ TEST:
$ IPL_BATCH
/read mask   "ipl_fname0
/read seg_hi "ipl_fname1
/gobj seg_hi "ipl_fname0
!---                        

/subtract  mask seg_hi seg_lo

/sup seg_lo
  -supdim_numbers            4 4 1
  -testoff_pixels            2
 
/seg_gauss  seg_lo fil_bub 
  -sigma                     2
  -support                   2
  -lower_in_perm_aut_al      300
  -upper_in_perm_aut_al      1000
  -value_in_range            60
  -unit                      6

/cl_extract
  -input                     fil_bub
  -output                    filaments
  -lo_vol_fract_in_perc      1
  -up_vol_fract_in_perc      100
  -value_in_range            80

/write  filaments    "ipl_fname2
  -compress  bin

/concat  fil_bub filaments  seg_lo                 
  -common_region_only        false
  -add_not_overlay           false
! In seg_lo, filaments are "80" and bubbles are "60".
! Seg-hi is "clean" PU with filaments only (bubbles like PU)

/set filaments 127 0
/subtract  mask filaments seg_hi

/write seg_hi "ipl_fname1

/del mask

/concat  seg_lo  rop  lo_rop                 
  -common_region_only        false
  -add_not_overlay           false
/del rop
/del seg_lo

/transparent_concat
  -input_solid               lo_rop
  -input_transp              seg_hi
  -output                    out

/write  out    "ipl_segaim
  -compress  bin

/del seg_hi
/del lo_rop

/todicom_from_aim
  -aim_name                  out
  -dicom_filename            "dcmb_file
  -multifiles                true
  -global_slicename          false

..
$ ON ERROR THEN CONTINUE
$! 
$! Generate central mask (MASKC)
$!
$ pipe aix 'ipl_fname0' | search sys$pipe "!> dim" |  -
	(read sys$pipe dim_txt ;  defin/nolog/job dimlog &dim_txt)
$ dim_log = f$trnlnm("dimlog")
$ dim_log = dim_log - "!> dim"
$ dim_clean = f$edit(dim_log,"COMPRESS, TRIM")
$ sh sym dim_clean
$ dimx = f$element(0," ",dim_clean)
$ dimy = f$element(1," ",dim_clean)
$ dimz = f$element(2," ",dim_clean)
$!
$ pipe aix 'ipl_fname0' | search sys$pipe "!> pos" |  -
	(read sys$pipe pos_txt ;  defin/nolog/job poslog &pos_txt)
$ pos_log = f$trnlnm("poslog")
$ pos_log = pos_log - "!> pos"
$ pos_clean = f$edit(pos_log,"COMPRESS, TRIM")
$ sh sym pos_clean
$ posx = f$element(0," ",pos_clean)
$ posy = f$element(1," ",pos_clean)
$ posz = f$element(2," ",pos_clean)
$!
$ voix  = (dimx/5 *2) + posz
$ voidx =  dimx/5
$ voiz  = (dimz/5 *2) + posz
$ voidz =  dimz/5
$!
$ IPL_BATCH
/read mask "ipl_fname0
/sub mask maskc
  -pos                       "voix  -1  "voiz
  -dim                       "voidx -1  "voidz
  -global_pos_flag           false
/bound maskc maskc_bb 
  -z_only 		     false
  -border    		     0 5 0
/write maskc_bb "ipl_maskc

..
$ ANALYSIS:
$ IF eval_misc1_1  .EQS. "NO"  THEN GOTO DT_CENTER 
$ IPL_BATCH

!------------------------|
!  Morphometric analysis |
!------------------------|

! VOX on whole object (voids as background, TV = whole device = ipl_fname0)
/read seg  "ipl_fname1 

/db_clear_eval seg
/db_scanco_activate true   

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/voxgobj_scanco_param
  -input                     seg
  -gobj_filename             "ipl_fname0
  -peel_iter                 0
/del seg

/read   rop 	"ipl_ropaim
/read   pu  	"ipl_fname1
/set    rop 127 0
/set    pu  127 0
/subtr  pu  rop pu_only
/write  pu_only "ipl_temp

/del 	rop
/del 	pu

/read 	org  	"ipl_aim
/gobj   org  	"ipl_temp

! apparent density of entire PU material (excl. filaments and rop)
/voxgobj_scanco_param
  -input                     org     
  -gobj_filename             "ipl_temp
  -peel_iter                 0
  -region_number             0

! apparent density of central part only (excl. rop)
/gobj   pu_only "ipl_maskc
/write  pu_only "ipl_temp
/gobj   org  	"ipl_temp

/voxgobj_scanco_param
  -input                     org     
  -gobj_filename             "ipl_temp
  -peel_iter                 0
  -region_number             1

! tissue (matrix) density of segmented volume
!!!/voxgobj_scanco_param
!  -input                     org
!  -gobj_filename             "ipl_segaim
!  -peel_iter                 2
!  -region_number             1

/del org 
..
!!!
$ DT_CENTER:
$ IF IPL_MISC1_2 .EQS. "NO" THEN GOTO ENDCOM      
$ ON ERROR THEN CONTINUE 
$ IPL_BATCH


/db_scanco_activate true

!--------------------------------------------------|
!  Voids are removed from object before DT_Object  |
!  Analysis performed on central volume only       |
!--------------------------------------------------|

/read seg "ipl_maskc

/sup seg
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_maskc
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname4

/write out "ipl_fname3

..
$ ON ERROR THEN CONTINUE 
$ IPL_BATCH

/db_scanco_activate true
!---------------------------------------------------|
! Filaments are analyzed (spacing) in DT_background |
!              peel_iter = 100 um                   |
!---------------------------------------------------|

/read seg "ipl_fname1
! ipl_fname1 = mask - filaments

/invert seg
  -gobj_filename             "ipl_fname0
  -peel_iter                 4
/bound  seg seg_b
  -z_only 		     false
  -border    		     1 1 1

/invert seg_b
/ren seg_b seg

/sup seg
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/dt_background
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_fname0
  -peel_iter                 4
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname6

/write out "ipl_fname5
..
$! Tb.N not necessary:
$  GOTO ENDCOM
$!--------------------------|
$!  Tb.N of the voids only  |
$!    peel_iter = 100 um    |
$!--------------------------|
$ ON ERROR THEN CONTINUE
$ IPL_BATCH

/db_scanco_activate true

/read seg "ipl_fname2

/sup seg
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/dt_mat
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_fname0
  -peel_iter                 4
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000
  -histofile_or_screen       "ipl_fname7
..
$ ENDCOM:
$ COPY_FILES:
$  sh sym samp_dir
$  COPY 'IPL_SEGAIM'  'samp_dir''EVAL_SAMPNAMET'_SEG.AIM
$  COPY 'IPL_FNAME3'  'samp_dir''EVAL_SAMPNAMET'_PTH.AIM
$  COPY 'IPL_FNAME5'  'samp_dir''EVAL_SAMPNAMET'_FIL.AIM
$!
$ PURGE_FILES:
$  PURGE 'dcma_file'*.DCM
$  PURGE 'dcmb_file'*.DCM
$  PURGE 'ipl_fname1'
$  DEL/NOCONFIRM 'ipl_temp';*
$!
$ EXIT
