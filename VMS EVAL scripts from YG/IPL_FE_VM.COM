$!      
$!         _/_/_/  _/_/_/    _/        
$!          _/    _/    _/  _/           Image Processing Language  
$!         _/    _/_/_/    _/ 
$!        _/    _/        _/             (c) SCANCO Medical
$!     _/_/_/  _/        _/_/_/_/            Bert v. Rietbergen, TUE, NL
$!        
$!
$!
$!  IPL FEM-Batch Scanco
$!
$ FILENAME = F$PARSE("''P1'",,,"NAME") - "_SEG" ! remove _SEG if possible
$ DEV      = F$PARSE("''P1'",,,"DEVICE")
$ DIR      = F$PARSE("''P1'",,,"DIRECTORY")
$!
$ FE_FILES   :== 'DEV''DIR''FILENAME'   ! without extension
$ FE_PROBLEM :== 33			! high friction in z
$ FE_PAR_NO  :== 42			! von Mises eq. stress
$!
$ DEFINE   SEG_FILE 	  'P1'
$ DEFINE   FE_SEG 	  'FE_FILES'"_FE_SEG.AIM"
$ DEFINE   FE_PAR 	  'FE_FILES'"_FE_PAR_"'FE_PAR_NO'".AIM"
$ DEFINE   FE_MASK 	  'FE_FILES'"_FE_CLMASK.AIM"
$!
$!
$!
$ IF F$SEARCH("FE_SEG") .NES. "" THEN GOTO FE_SOLVE
$!
$ ON ERROR THEN EXIT
$ IPLFE_BATCH

/read
  -name                      in
  -filename                  seg_file

!!!! for 1 object (value 127) only
!---------------------------------

/cl_ow_rank_extract
  -input_output              in
  -first_rank                1
  -last_rank                 1
  -connect_boundary          false
  -value_in_range            127

!!!! for multi-value object (IPL /concat by user)
!------------------------------------------------

!/cl_rank_extract
!  -input                     in
!  -output                    cl
!  -first_rank                1
!  -last_rank                 1
!  -connect_boundary          false
!  -value_in_range            127
!
!/write
!  -name                      cl
!  -filename                  fe_mask
!  -compress_type             bin
!
!/gobj_maskaimpeel_ow
!  -input_output              in
!  -gobj_filename             fe_mask
!  -peel_iter                 0
!
!!!! end multi-value object

/bounding_box_cut
  -input                     in
  -output                    out
  -z_only                    false
  -border                    0 0 0

/write
  -name                      out
  -filename                  fe_seg
  -compress_type             bin

..
$!
$ FE_SOLVE:
$ IPLFE_BATCH

/read
  -name                      in
  -filename                  fe_seg

/fe_solve3
  -in                        in
  -fea_file_name             "fe_files
  -problem_nr                "fe_problem
  -scale_factor              1.000000E+00
  -output_option             1
  -tolerance_force           1.000000E-03
  -tolerance_displ           1.000000E-03
  -max_nr_iter               10000
  -restart_option            1
  -comp_val_mat_001            127
  -Ymodulus_mat_001            1.000000E+04
  -Poissonr_mat_001            3.000000E-01
  -comp_val_mat_002            0
  -Ymodulus_mat_002            1.000000E+04
  -Poissonr_mat_002            3.000000E-01
  -comp_val_mat_003            0
  -Ymodulus_mat_003            1.000000E+04
  -Poissonr_mat_003            3.000000E-01

/fe_post
  -post_file_name            "fe_files
  -output                    con
  -variable_nr               "fe_par_no
  -loadcase_nr               1
  -output_option             1
  -interpol_option           1

/write
  -name                      con
  -filename                  fe_par

..
$ EXIT
