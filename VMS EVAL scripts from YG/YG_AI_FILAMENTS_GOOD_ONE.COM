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
$   chek_gobj   := 'EVAL_DIR''EVAL_FNAME'_CHEK.GOBJ
$   chek_mask   := 'EVAL_DIR''EVAL_FNAME'_CHEK.AIM
$!   CHEK_GOBJ is defined or drawn manually before EVAL. 
$!             This is an outer contour 
$! If there is some highly radio-opaque particles trapped in the material,
$! it'll be shown as separate _ROP.AIM :
$   ipl_ropaim := 'EVAL_DIR''EVAL_FNAME'_ROP.AIM
$   thres_rop   = ipl_lower0 * 3
$   sh sym thres_rop
$! To allow for fluctuations in the RO of the PU, a lower thres is defined:
$   thres_pu    = ipl_lower0 - 10
$   ipl_maskf  := 'EVAL_DIR''EVAL_FNAME'_MASKF.AIM
$   ipl_temp   := 'EVAL_DIR''EVAL_FNAME'_TEMP.AIM
$!                                                   
$! Definitions to create sub-directory for DICOM:
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
$! GOTO END_MASKING
$! GOTO DT_BACKGROUND
$!
$ SEG:
$ IF IPL_MISC1_0 .EQS. "NO" THEN GOTO ANALYSIS      
$!
$ IF 	F$SEARCH(ipl_gauaim) .NES. ""    
$ THEN	
$	IPL_ISQ   :=  IGNORE.ISQ
$	READ_GAU   =  "/read gau ""ipl_gauaim "
$ ELSE 
$       READ_GAU   =  "!!! New GFILT generated"
$ ENDIF
$!
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
    
!!! Gauss filtration is done separately for the filaments/voids and PU
!!! Here we do for PU (sig=2), after filament is used as mask on ORG
!!!      and new GAUSS_SEG is done to obtain voids. 
/gauss org gau
  -sigma       "ipl_sigma0
  -support     "ipl_support0
/del org

/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0
/write gau "ipl_gauaim

/todicom_from_aim
  -aim_name                  gau
  -dicom_filename            "dcma_file
  -multifiles                true
  -global_slicename          false

"read_gau
! If CORR.GOBJ is present...
/gobj gau 
  -gobj_filename             "ipl_gobj1
  -peel_iter                 "ipl_peel1
      
! extract hi_thres object:
/thres gau filaments
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -value       127
  -unit	       "ipl_unit0

! thres_pu = ipl_lower0 - 10
/thres gau seg
  -low         "thres_pu  
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
! In case there are no ROP, bound_box will result in an empty
! volume and all will fail...
/write rop "ipl_ropaim

/cl seg 
/bound seg seg_hi
  -z_only 		     false
  -border    		     5 
/del seg
! Now seg_hi is the device without the adjacent plastic from sample holder. 
! For voids and filaments (empty inside the object) use filaments

! Since object is sealed on the outside, no need for Ero_dil 
/copy   seg_hi mask
/set    mask   0 127
/cl     mask
/set    mask   0 127
/write  mask   "ipl_fname0  

/gobj  rop "ipl_fname0
/write rop "ipl_ropaim
/del   rop

! ipl_fname1 is for first object (high density, transparent on 3D): _SEG1.AIM
/gobj   seg_hi "ipl_fname0
/write  seg_hi "ipl_fname1
  -compress  bin    

! In case another implant is present in the frame, we can use ipl_fname0
! eventhough it is based on thers_pu.
! Reminder: filaments if the PU with threshold suitable for filaments
/gobj  filaments "ipl_fname0
/bound filaments bb
  -z_only 		     false
  -border    		     5 
/ren bb filaments

/write filaments "ipl_fname2
! Here filaments is the inverted image (filaments are 0, PU is 127)
..
$! EXIT
$ STEP_02:
$ IF F$SEARCH(chek_gobj) .NES. "" 
$ THEN 
$     GOTO CHECK
$ ELSE
$     GOTO NOCHECK
$ ENDIF
$!-------------
$ CHECK:
$! March 2020: This part seems erroneous. The outer border of the mask = seg_hi 
$! The threshold for seg_hi is 90 but for filaments it is 100
$! So after the set 0 and gobj it may create a thin shell around filaments
$! This is way I added peel_iter = 2
$!
$ WRITE SYS$OUTPUT " *** Performing GOBJ of the filaments with CHEK.GOBJ ***"
$ IPL_BATCH
/read filaments "ipl_fname2
/gobj_to_aim "chek_gobj mask
/ero mask ero 2
/read     seg_hi "ipl_fname1
/add_aims ero    seg_hi mask                            
/set      mask   127 0
/write    mask "ipl_fname0
/set filaments 0 127
/gobj     filaments  "ipl_fname0  2
/del   mask
/del   seg_hi
/del   ero 
! Here we only have filaments and bubbles. Each filament is about 30%.
/cl_extract
  -input                     filaments
  -output                    fil
  -lo_vol_fract_in_perc      20
  -up_vol_fract_in_perc      100
  -value_in_range            127

/bound fil bb
  -z_only 		     false
  -border    		     5 
/ren bb fil

/seg_gauss  fil filaments 
  -sigma                     2                               
  -support                   2
  -lower_in_perm_aut_al      300
  -upper_in_perm_aut_al      1000
  -value_in_range            80
  -unit                      6
 
/write  filaments    "ipl_fname2
  -compress  bin
..
$ GOTO END_MASKING
$!-------------
$!
$ NOCHECK:
$ WRITE SYS$OUTPUT " *** Performing CL of the filaments (no CHEK.GOBJ)  ***"
$ IPL_BATCH
/read filaments  "ipl_fname2
/set  filaments 0 127
/gobj filaments  "ipl_fname0  2

!/cl   filaments 2 10 
! No need for the cl_rank as we removed the background with gobj

! Here we only have filaments and bubbles. Each filament is about 30%.
/cl_extract
  -input                     filaments
  -output                    fil
  -lo_vol_fract_in_perc      20
  -up_vol_fract_in_perc      100
  -value_in_range            127

/seg_gauss  fil filaments 
  -sigma                     2
  -support                   2
  -lower_in_perm_aut_al      300
  -upper_in_perm_aut_al      1000
  -value_in_range            80
  -unit                      6
 
/write  filaments    "ipl_fname2
  -compress  bin
!!! At this stage, filaments is like a mask of the filaments including air and
!!! cracks in the midth of the filamnents
..
$!-------------
$ !EXIT
$ END_MASKING: 
$ IPL_BATCH

!!! Here on Nov 2018 I added a dilation 4 to include all voids around
!!! the filaments; however, this also added radiographic artefacts
!!! from the PU material to the actual voids. I therefore limited the 
!!! definition of the voids to the volume of the filaments (excl. the
!!! PU material). Last update May 1st 2019. 

! Segmentation of air around filaments (high thresh used for filaments)
! --------------------------------------------------------------------
/read  filaments "ipl_fname2
/dil   filaments  dil "ipl_support2
/write dil        "ipl_temp
/del   dil
/read  org "ipl_aim
/gobj  org "ipl_temp
/bound org bb
  -z_only 		     false
  -border    		     5 
/ren bb org
/sup org
  -supdim_numbers            2 1 4
  -testoff_pixels            "ipl_support2
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1
    
/gauss_seg org air 
  -sigma                     "ipl_sigma2
  -support                   "ipl_support2
  -lower_in_perm_aut_al      "ipl_lower2
  -upper_in_perm_aut_al      "ipl_upper2
  -value_in_range            15 
  -unit                      "ipl_unit2
/del   org

/concat  filaments air filandair f f
/del     filaments
/del     air

/gobj  filandair "ipl_fname2
/bound filandair bb
  -z_only 		     false
  -border    		     5 
/ren bb filandair

/write filandair "ipl_fname2
  -compress  bin
!!! fname2 consists at the filaments with a value of 80 and air at 15.
!!! Air is segmented using ipl_upper2 value

! Segmentation of bubbles in PU (low thresh used in seg_hi)
! ---------------------------------------------------------
/read   seg_hi    "ipl_fname1
/read   mask      "ipl_fname0
                    
/subtract  mask seg_hi seg_low
/gobj seg_low "ipl_fname0                                                   
  -peel_iter		     4	
/set seg_low 60 0

/concat  seg_low filandair  seg_fab                 
  -common_region_only        false
  -add_not_overlay           false
/del seg_low

! In seg_fab, filaments are "80", Air/cracks are "15" and bubbles are "60".
! Now we want to use filandair to make a clean PU/seg1:

/set filandair 127 0
/subtract  mask filandair seg_hi
/write seg_hi "ipl_fname1

! Seg_hi is "clean" PU without filaments and air (bubbles like PU)

/del filandair
/del mask

! Highlight ROP that are inside the object:
/read  rop "ipl_ropaim

/concat  rop  seg_fab   fab_rop                 
  -common_region_only        false
  -add_not_overlay           false
/del rop
/del seg_fab
                                      
/transparent_concat
  -input_solid               fab_rop
  -input_transp              seg_hi
  -output                    out

/write  out    "ipl_segaim
  -compress  bin
!/set out 127 0
!/write  out    "ipl_fname0

/del seg_hi
/del fab_rop

!/todicom_from_aim
!  -aim_name                  out
!  -dicom_filename            "dcmb_file
!  -multifiles                true
!  -global_slicename          false

..
$ !!!!!!!!!!!!!!!!!!!!!!!!!!
$ !EXIT
$! From here I removed the central fifth of the PU (March 2020)
$ ANALYSIS:
$ IF eval_misc1_1  .EQS. "NO"  THEN GOTO DT_CENTER 
$ IPL_BATCH

!------------------------|
!  Morphometric analysis |
!------------------------|

! VOX on whole object (voids as background, TV = whole device = ipl_fname0)

/read  filandair "ipl_fname2
/thres filandair  fil
  -lower_in_perm_aut_al      80
  -upper_in_perm_aut_al      80
  -value_in_range            127 
  -unit			     5 
/set   filandair 127 0
/write filandair "ipl_maskf   
/write fil 	 "ipl_temp

/db_clear_eval fil
/db_scanco_activate true   

! uncomment if the script shall be started from terminal, 
! without clicking on 'Start 3D evaluation' ever for that measurement
!/db_calib_unit_fill seg

/voxgobj_scanco_param
  -input                     fil
  -gobj_filename             "ipl_maskf
  -peel_iter                 0

/read 	org  	"ipl_aim

! apparent density of filaments and air/cracks
/voxgobj_scanco_param
  -input                     org     
  -gobj_filename             "ipl_maskf
  -peel_iter                 1
  -region_number             0  

! apparent density of filaments without air/cracks
/voxgobj_scanco_param
  -input                     org     
  -gobj_filename             "ipl_temp
  -peel_iter                 1
  -region_number             1  

!!! May 1st, 2019: I added above a segmentation of the air in the midth of the
!!! filaments. Here the Mat Dens of filaments excludes these voids. 
..
$!!!
$! GOTO ENDCOM
$ DT_FIL:
$ IF IPL_MISC1_2 .EQS. "NO" THEN GOTO ENDCOM      
$ ON ERROR THEN CONTINUE 
$ IPL_BATCH


/db_scanco_activate true
                              
!---------------------------------------------------------|
!  In DT_Object we analyze the filament+air as one object |
!---------------------------------------------------------|

/read seg "ipl_maskf

/sup seg
  -supdim_numbers            2 2 1
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/dt_object
  -input                     seg
  -output                    out
  -gobj_filename             "ipl_gobj0
  -peel_iter                 0
  -roi_radius_factor         10000.000000
  -ridge_epsilon             0.900000
  -assign_epsilon            1.800000                                       
  -histofile_or_screen       "ipl_fname4

/write out "ipl_fname3

..
$ ON ERROR THEN CONTINUE 
$!GOTO ENDCOM
$ DT_BACKGROUND:
$ IPL_BATCH

/db_scanco_activate true
!------------------------------------------------------------|
! Voids in Filaments are analyzed (spacing) in DT_background |
!------------------------------------------------------------|

!/read seg "ipl_temp
! ipl_temp = thres 15 from ipl_fname2 (filaments)
! Can't use the above if analysis jumps straight to here

/read  filandair "ipl_fname2
/thres filandair  fil
  -lower_in_perm_aut_al      80
  -upper_in_perm_aut_al      80
  -value_in_range            127 
  -unit			     5 

/sup fil
  -supdim_numbers            1 1 4
  -testoff_pixels            0 0 0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/dt_background
  -input                     fil
  -output                    out
  -gobj_filename             "ipl_maskf
  -peel_iter                 0
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
  -supdim_numbers            2 2 4
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
$  PURGE 'ipl_fname0'
$  PURGE 'EVAL_DIR'
$  DEL/NOCONFIRM 'ipl_temp';*
$  DEL/NOCONFIRM 'chek_mask';*
$!
$  PURGE 'ipl_gauaim'  
$  PURGE 'chek_gobj'  
$  PURGE 'ipl_ropaim'
$  PURGE 'ipl_maskc'
$!                                                   
$ EXIT
