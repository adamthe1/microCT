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
$!  input volume: the solid volume wins over the transparent volume.
$!
$! Calculation of sequential threshold values (decreasing order):
$ thres0 = ipl_lower0
$ thres1 = ('ipl_lower0' +  'ipl_lower1') / 2
$ thres2 = ipl_lower1
$ thres3 = ('ipl_lower1' +  'ipl_lower2') / 2
$ thres4 = ipl_lower2
$ thres5 = ('ipl_lower2' +  'ipl_lower3') / 2
$ thres6 = ipl_lower3
$ thres7 = 'ipl_lower3' -  ('thres6' - 'ipl_lower3')
$!
$ sh sym thres0
$ sh sym thres1
$ sh sym thres2
$ sh sym thres3
$ sh sym thres4
$ sh sym thres5
$ sh sym thres6
$ sh sym thres7
$!
$! Create sub-directory for DICOM:
$  mkdir		:== @YGCOM:MKDIR.COM
$  truncated  = ipl_dir - "]"
$  dicoma_dir := 'truncated'.DICOM_A]
$  IF F$SEARCH(dicoma_dir) .EQS. "" THEN MKDIR 'DICOMA_DIR'
$  dcma_file  := 'DICOMA_DIR''IPL_FNAME'
$  sh sym dcma_file
$  dicomb_dir := 'truncated'.DICOM_B]
$  IF F$SEARCH(dicomb_dir) .EQS. "" THEN MKDIR 'DICOMB_DIR'
$  dcmb_file  := 'DICOMB_DIR''IPL_FNAME'
$  sh sym dcmb_file
$!
$ mesh_name :=  'IPL_DIR''IPL_FNAME' 
$ mesh_name2 :=  'IPL_DIR''IPL_FNAME'_2
$ mesh_name4 :=  'IPL_DIR''IPL_FNAME'_4               
$ mesh_name6 :=  'IPL_DIR''IPL_FNAME'_6
$ sh sym mesh_name
$ sh sym mesh_name
$ ! EXIT
$!
$ ON ERROR THEN EXIT
$ IPL_BATCH
  
! 
! extract VOI from ISQ
!

/isq_to_aim
  -aim_name                  org
  -isq_filename              "ipl_isq
  -pos                       "ipl_voix "ipl_voiy "ipl_voiz
  -dim                       "ipl_voidx "ipl_voidy "ipl_voidz

/sup org
  -supdim_numbers            4 4 1
  -testoff_pixels            "ipl_support0
  -suppos_pixels_local       -1 -1 -1
  -subdim_pixels             -1 -1 -1

/todicom_from_aim
  -aim_name                  org
  -dicom_filename            "dcma_file
  -multifiles                true
  -global_slicename          false

/gauss org gau
  -sigma       "ipl_sigma0
  -support     "ipl_support0
/del org

/gobj
  -input_output              gau
  -gobj_filename             "ipl_gobj0
  -peel_iter                 "ipl_peel0

/threshold        
  -input       gau
  -output      seg7
  -low         "thres7 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       10
/write seg7 "ipl_fname7

/threshold        
  -input       gau
  -output      seg6
  -low         "thres6 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       20

/threshold        
  -input       gau
  -output      seg5
  -low         "thres5 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       40

/threshold        
  -input       gau
  -output      seg4
  -low         "thres4 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       60

/threshold        
  -input       gau
  -output      seg3
  -low         "thres3 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       80

/threshold        
  -input       gau
  -output      seg2
  -low         "thres2 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       100

/threshold        
  -input       gau
  -output      seg1
  -low         "thres1 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       120

/threshold        
  -input       gau
  -output      seg0
  -low         "thres0 
  -upp	       "ipl_upper0
  -unit	       "ipl_unit0
  -value       127

/concat                  
  -input1                    seg7
  -input2                    seg6
  -output                    seg67
  -common_region_only        false
  -add_not_overlay           false

/concat                  
  -input1                    seg67
  -input2                    seg5
  -output                    seg567
  -common_region_only        false
  -add_not_overlay           false

/concat                  
  -input1                    seg567
  -input2                    seg4
  -output                    seg4567
  -common_region_only        false
  -add_not_overlay           false

/concat                  
  -input1                    seg4567
  -input2                    seg3
  -output                    seg34567
  -common_region_only        false
  -add_not_overlay           false

/concat                  
  -input1                    seg34567
  -input2                    seg2
  -output                    seg234567
  -common_region_only        false
  -add_not_overlay           false

/concat                  
  -input1                    seg234567
  -input2                    seg1
  -output                    seg1234567
  -common_region_only        false
  -add_not_overlay           false

/concat                  
  -input1                    seg1234567
  -input2                    seg0
  -output                    seg
  -common_region_only        false
  -add_not_overlay           false

/write  seg  "ipl_segaim
  -compress  bin

/copy seg7 seg
/set seg 127 0

/bound seg seg_bb
  -z_only                    false
  -border                    5

/todicom_from_aim
  -aim_name                  seg_bb
  -dicom_filename            "dcmb_file
  -multifiles                true
  -global_slicename          false

!/scale seg_bb sca
  -down_scale                2
  -up_scale                  1
  -integrate                 false

!/mesh sca
  -mesh_file_name            "mesh_name2
  -output_format             abaqus   

/scale seg_bb sca
  -down_scale                8
  -up_scale                  1
  -integrate                 false

/mesh sca
  -mesh_file_name            "mesh_name4
  -output_format             abaqus   

/scale seg_bb sca
  -down_scale                6
  -up_scale                  1
  -integrate                 false

/mesh sca
  -mesh_file_name            "mesh_name6
  -output_format             abaqus   

..
$ EXIT
