$!===========================================
$! DUAL THRESHOLD SCRIPT
$! adapted from original script by Helen Buie
$! 07-Jul-2008 Andres Laib, Scanco Medical AG
$!===========================================
$!
$! Needs IPL V5.07b or newer for correct boundary and dim handling. AL.
$!
$! Modified: 	25-SEP-2008: peel the trab. contour already, so 'final' contour can be
$! 	 	checked in the eval program. AL
$!		inserted write commands, exit ipl, enter again, so larger files can 
$!		be processed. AL
$!
$! -----------------
$! Define Parameters
$! -----------------
$
$! First distance: expected largest cortical pore that needs to be closed to get
$! closed outside surface.
$! too small: outer contour goes INTO bone. Bad.
$! too large: first few and last few slices might show boundary artefact.
$!  most probably, those first and last slices will be 'stolen' by the Gauss filter
$!  of the histo-morpho eval, anyway... Use support 2 because of this, even if Gauss sigma
$!  is only 0.7 or 0.8 
$  dilate1    = ipl_misc1_0
$  erode1     = ipl_misc1_0
$
$! Second distance: dilation of the marrow volume: how much the trabeculae have to be
$! 'crushed' to 'disappear, thus for the marrow to get 'solid'
$! Thus: radius (half thickness) of largest trab. that emerges from cortex that shall be
$! counted as trab and not belong to cortex compartement. 
$! too small: endocortical contour follows thicker trab., thus puts them into cortical compart.
$! too large: first few and last few slices might show boundary artefact. 
$!  most probably, those first and last slices will be 'stolen' by the Gauss filter
$!  of the histo-morpho eval, anyway... Use support 2 because of this, even if Gauss sigma
$!  is only 0.7 or 0.8 
$!  
$  dilate2    = ipl_misc1_1
$  erode2     = ipl_misc1_1
$! helper variable, for median filter in the end:
$  erode2inc  = ipl_misc1_1 + 1
$
$! Minimal cortical thickness: 
$  minimal_cort_thick = ipl_misc1_2
$!
$! pores are first eroded --> pores with diameter less than 2*exclude_pore_dist
$! are discarded to define the trab. region, are thus included in 'cortical region'
$! Only very small values suggested for this parameter.
$! too large: trab. region gets counted as cortical region. BAD. 
$  exclude_pore_dist  = ipl_misc1_3
$!
$! shrink trab. boundary to get contour (instead of peel_iter in subsequent morpho eval): 
$  trab_peel_iter     = ipl_misc1_4	
$!
$! make inner cortical contour a bit 'bigger', thus leave gap between
$! previously calculated trab. boundary and inner cortical contour.
$  cort_trab_gap      = ipl_misc1_5
$!
$! --> total gap between cortical and trab.contour is thus ipl_misc1_4 + ipl_misc1_5
$!
$! to ensure an empty frame around object, so cl of background is taking
$! the outside of the bone as biggest, connected piece:
$  double_support = 2*ipl_support0
$
$  ORIGAIM_FILENAME      =  ipl_aim 
$
$! These files are created to check the results:
$! -------------------------------------------------------------------
$  BONEGOBJ_FILENAME  =  ipl_fname0
$  TRABGOBJ_FILENAME  =  ipl_fname1
$  CORTGOBJ_FILENAME  =  ipl_fname2
$! Needed helper files:
$  UNPEELED_TRABGOBJ  =  ipl_fname1 - f$parse(ipl_fname1,,,"VERSION") - ".GOBJ" + "_NOPEEL.GOBJ"
$  INVTRAB_FILENAME   =  ipl_fname1 - f$parse(ipl_fname1,,,"VERSION") - ".GOBJ" + "_INV.AIM"
$
$! Turn on or off the aim file writing in the script
$! -------------------------------------------------------------------
$  BONEMASK_FILENAME   =  ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_MASK.AIM"
$  TRABMASK_FILENAME   =  ipl_fname1 - f$parse(ipl_fname1,,,"VERSION") - ".GOBJ" + "_MASK.AIM"
$  CORTMASK_FILENAME   =  ipl_fname2 - f$parse(ipl_fname2,,,"VERSION") - ".GOBJ" + "_MASK.AIM"
$
$
$! Intermediate Helper files to allow larger file processing. 
$! turn off deletion at the end of this script to debug if wished.
$  help1 = ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_HELP1.AIM"
$  help2 = ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_HELP2.AIM"
$  help3 = ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_HELP3.AIM"
$  help4 = ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_HELP4.AIM"
$  help5 = ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_HELP5.AIM"
$  help6 = ipl_fname0 - f$parse(ipl_fname0,,,"VERSION") - ".GOBJ" + "_HELP6.AIM"
$
$
$! -------------------------------------------------------------------
$! BREAKDOWN OF THE SCRIPT
$! Step 1 creates a mask of the bone. 
$! Step 2 creates a mask of the trabecular region.
$! Step 3 creates a mask of the cortical region.
$! -------------------------------------------------------------------
$
$
$!=========================================
$! STEP 1: Extract the periosteal surface
$!=========================================
$
$ STEP1:
$
$ ipl_batch

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

!/read
!  	-name			org
!	-filename		"origaim_filename

! add some boundary in x and y to make sure bone is isolated
! and biggest background piece is connected slicewise AROUND the bone,
/bounding_box_cut
  -input                     org
  -output                    box
  -z_only                    false
  -border                    "double_support "double_support "ipl_support0

! border in z put into offset then. Will be mirrored later.
/offset_add box
  -add_offset                0 0 "ipl_support0

/rename box org

! aim file written with offset in header, but not mirrored yet
/write org "origaim_filename

! mirror out slices that will be stolen in gauss now:
/fill_offset_mirror org

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org S1_seg
  -sigma       "ipl_sigma0
  -support     "ipl_support0
  -low         "ipl_lower0  
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       127

/delete org

! only extract main bone
/cl_ow_rank_extract
  -input_output              S1_seg
  -first_rank		     1
  -last_rank		     1

/write  S1_seg "help1
..
$ ipl_batch
/read S1_seg "help1


! dilate the bone to close off holes in the cortex
/dilation
        -input                  S1_seg
        -output                 S1_dilate
        -dilate_distance        "dilate1
  	-continuous_at_boundary    0 0 1
! image now bigger by 'dilate1' distance

/write  S1_dilate "help2
..
$ ipl_batch
/read S1_dilate "help2

!invert the image so the bone is black, background is white
/set_value
	-input	                S1_dilate
	-value_object	          0
	-value_background	127

! extract the region around the bone (gets rid of bone interior)
/cl_slicewise_extractow
  -input_output              S1_dilate
  -lo_vol_fract_in_perc      40.000000
  -up_vol_fract_in_perc      100.000000
  -value_in_range            127

! invert the image back to normal
/set_value
	-input	                S1_dilate
	-value_object	          0
	-value_background	127


! erode back dilated bone volume (also gets rid of noise in background)
/erosion
        -input                  S1_dilate
        -output                 S1_erode
        -erode_distance         "erode1
	-use_previous_margin    true
! -use_previous saves memory.

/delete S1_dilate

/examine S1_erode geometry

/togobj_from_aim
  -input                     S1_erode
  -gobj_filename             "bonegobj_filename
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1

!/write
!	-name			S1_erode
!	-filename	        "bonemask_filename


!Exit IPL and restart
..
$
$
$
$!=========================================
$! STEP 2: Extract the endosteal surface
$!=========================================
$
$ STEP2:
$
$ ipl_batch

/read
  	-name			org
	-filename		"origaim_filename

/exa org geometry

! mirror out slices that will be 'stolen' in gauss now:
/fill_offset_mirror org

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support1
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/seg_gauss org S2_seg
  -sigma       "ipl_sigma1
  -support     "ipl_support1
  -low         "ipl_lower1
  -upp	       "ipl_upper1
  -unit	       "ipl_unit1
  -value	127

/delete org

! MUST have same dim. Cannot use gobj_to_aim.

/copy S2_seg step1

! set all solid:

/set_value step1 
	-value_object	        127
	-value_background	127

/gobj_maskaimpeel_ow
  -input_output              step1
  -gobj_filename             "bonegobj_filename
  -peel_iter                 "minimal_cort_thick

! invert the periosteal surface mask (so bone is black, background is white)
/set_value
	-input	                step1
	-value_object	          0
	-value_background	127

! by adding the aims we get outside of bone white plus trabeculae white
/add_aims
	-input1			S2_seg
	-input2			step1
	-output			S2_masked
/delete step1

! invert so only marrow cavities are white (outside and cortex and trab. themselves black)
/set_value
	-input	                S2_masked
	-value_object	          0
	-value_background	127

/exa S2_masked geo

/write S2_masked "help3
..
$ ipl_batch

/read S2_masked "help3

! Discard thin marrow cavities --> discard cortical canals!
/open 
  -input                     S2_masked
  -output                    S2_masked_open
  -open_distance             "exclude_pore_dist

/rename S2_masked_open S2_masked

! extract all marrow cavities that are connected. Must be in 3D!
! i.e.: throw away non-connected marrow spaces, e.g. isolated pores in cortex

/cl_ow_rank_extract
        -input_output  		S2_masked
	-first_rank		1
	-last_rank		2

/exa S2_masked geo

/write S2_masked "help4
..
$ ipl_batch

/read S2_masked "help4

! this joins the marrow cavities together
/dilation
        -input                  S2_masked
        -output                 S2_dilate
        -dilate_distance        "dilate2
  	-continuous_at_boundary    0 0 1
/delete S2_masked

/examine S2_dilate geometry

! 'trab' bone and whole outside white again
/set_value
	-input	                S2_dilate
	-value_object	          0
	-value_background	127

! extract the region around the marrow
! i.e. throw away not-connected bone pieces on inside
/cl_slicewise_extractow
  -input_output              S2_dilate
  -lo_vol_fract_in_perc      40.000000
  -up_vol_fract_in_perc      100.000000
  -value_in_range            127

!invert image so now the inside (trab) region is white, background is black
/set_value
	-input	                S2_dilate
	-value_object	          0
	-value_background	127

/exa S2_dilate geo

! add (subtract) offset, otherwise it gets 'stolen' in write operation
! needed for subsequent median fiddling
/offset_add
  -input                     S2_dilate
  -add_offset                -1 -1 -1 

/write S2_dilate "help5
..
$ ipl_batch

/read S2_dilate "help5

! needed for subsequent median fiddling
/offset_add
  -input                     S2_dilate
  -add_offset                1 1 1

! now erode it back
/erosion
        -input                  S2_dilate
        -output                 S2_erode
        -erode_distance         "erode2
  	-use_previous_margin    true
! -use_previous saves memory.

/delete S2_dilate
/examine S2_erode geometry

! S2_erode has a large offset of erode_dist+2
! most of it will be lost in write operation of help.aim
! set a pixel-wide border, for median afterwards

! add (subtract) offset 1, otherwise it gets 'stolen' in write operation
! needed for subsequent median fiddling
/offset_add
  -input                     S2_erode
  -add_offset                -1 -1 -1 


/write S2_erode "help6
..
$ ipl_batch

/read S2_erode "help6

! needed for subsequent median fiddling
/offset_add
  -input                     S2_erode
  -add_offset                1 1 1

! mirror out 1 'missing' slices
/fill_offset_mirror S2_erode

/median_filter
        -input                  S2_erode
        -output                 S2_median2
        -support                1

! this write operation always necessary!
/togobj_from_aim
  -input                     S2_median2
  -gobj_filename             "unpeeled_trabgobj
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1

/gobj_maskaimpeel_ow
  -input_output              S2_median2
  -gobj_filename             "unpeeled_trabgobj
  -peel_iter                 "trab_peel_iter 

/togobj_from_aim
  -input                     S2_median2
  -gobj_filename             "trabgobj_filename
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1

!/write
!	-name			S2_median2
!	-filename	        "trabmask_filename

!Exit IPL and restart
..
$
$
$
$
$!=========================================
$! GENERATE CORTICAL MASK WITH BOUNDARY
$!=========================================
$
$ STEP3: 
$
$ ipl_batch

/gobj_to_aim
  -gobj_filename             "bonegobj_filename
  -output                    all
  -peel_iter                 0

! Cannot use gobj_to_aim, must have same dim as 'all'
/copy all trab
/set_value trab 
	-value_object	        127
	-value_background	127
/gobj_maskaimpeel_ow
  -input_output              trab
  -gobj_filename             "unpeeled_trabgobj
  -peel_iter                 0

/set_value
	-input	                trab
	-value_object	          0
	-value_background	127

/write trab "invtrab_filename
/delete trab

/gobj_maskaimpeel_ow
	-input_output		all
	-gobj_filename		"invtrab_filename
	-peel_iter		"cort_trab_gap

/togobj_from_aim
  -input                     all
  -gobj_filename             "cortgobj_filename
  -min_elements              0
  -max_elements              0
  -curvature_smooth          1

!/write
!	-name			all
!	-filename		"cortmask_filename

..
$!
$! if no deletion of helper files is wished, uncomment this line:
$! exit  
$!
$! Clean up most current version of helper files if wished:
$!
$  WRITE SYS$OUTPUT "Deleting helper files ''help1' etc."
$  TEMP_FILE = F$SEARCH(HELP1)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$  TEMP_FILE = F$SEARCH(HELP2)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$  TEMP_FILE = F$SEARCH(HELP3)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$  TEMP_FILE = F$SEARCH(HELP4)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$  TEMP_FILE = F$SEARCH(HELP5)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$  TEMP_FILE = F$SEARCH(HELP6)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$  TEMP_FILE = F$SEARCH(INVTRAB_FILENAME)
$  DELETE/NOCONFIRM 'TEMP_FILE' 
$!
$ EXIT
