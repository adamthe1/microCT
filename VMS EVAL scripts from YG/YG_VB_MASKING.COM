$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) Andres Laib, IBT/ETH Zürich
$!     _/_/_/  _/        _/_/_/_/                         Scanco Medical
$!        
$!  IPL Batch Scanco
$!
$!
$!  Trabecular bone analysis in 2 subregions.
$!
$	FILENAME     = F$PARSE("''IPL_ISQ'",,,"NAME")
$	DEV          = F$PARSE("''IPL_ISQ'",,,"DEVICE")
$	DIR          = F$PARSE("''IPL_ISQ'",,,"DIRECTORY")
$	gau_file     :=  'DEV''DIR''FILENAME'_GFILT.AIM
$	inn_mask     :=  'DEV''DIR''FILENAME'_MASK_T.AIM
$	out_mask     :=  'DEV''DIR''FILENAME'_MASK_C.AIM
$	IPL_GOBJ_T   :=  'DEV''DIR''FILENAME'_T.GOBJ
$	IPL_GOBJ_O   :=  'DEV''DIR''FILENAME'_O.GOBJ   ! O for outer, not zero
$	IPL_GOBJ_M   :=  'DEV''DIR''FILENAME'_M.GOBJ
$	IPL_GOBJ_E   :=  'DEV''DIR''FILENAME'_E.GOBJ
$!
$! 
$	thres_mask    =  'ipl_lower0' + 10
$	dilation_nr   =  20
$	erosion_nr    =  'dilation_nr' + 1
$	down_scale    =  2
$	dims_of_box   =  NO 
$	redo_gfilt    =  NO
$	sh sym dilation_nr
$	sh sym redo_gfilt
$	sh sym dims_of_box
$!
$ GOTO NEXT
$	run_auto_mask =  ipl_misc1_0
$	dilation_nr   =  ipl_misc1_1
$	erosion_nr    =  'dilation_nr' + 1
$	border	      =  dilation_nr * 2 + 1
$	down_scale    =  ipl_misc1_2
$	redo_gfilt    =  ipl_misc1_3
$	sh sym dilation_nr 
$!
$ NEXT:
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
$ ON ERROR THEN EXIT
$ IPL_BATCH

/db_scanco_activate true

! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

!
! write VOI to disk (as AIM)
!
/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/gauss_lp org gau
  -sigma       		     "ipl_sigma0
  -support     		     "ipl_support0

/write gau "ipl_aim
/del org

/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/bounding_box_cut
  -input                     gau
  -output                    out
  -z_only                    false
  -border                    0 0 0

/del gau

/thres out seg
  -low         		     "ipl_lower0  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/write  seg    "ipl_segaim
  -compress  bin

/thres out seg_hi
  -low         		     "thres_mask  
  -upp	       		     "ipl_upper0
  -value       		     127
  -unit	       		     "ipl_unit0

/del out
/write  seg_hi    "inn_mask
  -compress  bin

! processing of seg for mask only:

! First make an outer mask (with low thres seg):
/scale_elsize  seg sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because this will cut the dilated surface before ero... 
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
/concat ero seg mask
  -common_region_only false
  -add_not_overlay    false
 
/togobj_from_aim  mask "ipl_gobj_o
 -curvature_smooth   5              

/write mask "out_mask
                            
! Now use the outer mask to separate the inner background (with hi thres seg):

/inv seg_hi 
 -gobj_filename  "out_mask
/ren seg_hi seg_inv

! To delete small bubles in the primary spongiosa: 
/cl  seg_inv

/scale_elsize  seg_inv sca
  -down_scale                "down_scale
  -up_scale                  1
  -integrate		     false

/dilation
  -input                     sca
  -output                    dil
  -dilate_distance           "dilation_nr

/del sca

! Can't use inv because this will cut the dilated surface before ero... 
/set dil 0 127
/cl  dil                                                                          
/set dil 0 127

! For this ero, use the same nr as dilation for acuracy. 
! Peel_iter will be used at analysis
/erosion
  -input                     dil                                            
  -output                    sca
  -erode_distance            "dilation_nr
  -use_previous_margin       true

/scale_elsize  sca ero
  -down_scale                1
  -up_scale                  "down_scale                                    
  -integrate		     false

/set ero 50 0
/concat ero seg_inv mask
  -common_region_only false
  -add_not_overlay    false
 
/togobj_from_aim  mask "ipl_gobj_t
  -min_elements       200
  -max_elements       0      
  -curvature_smooth   5              

/write mask "inn_mask
                            
..
$ EXIT
