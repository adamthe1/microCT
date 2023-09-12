#---------------------------------------------------------------------
#	        uct_evaluation_v7_reimport.py
#
# Revision history:
#
# V1.0   07-DEC-2021    Implementation. sw
# V1.1   02-NOV-2022    Bug fix for no reimport case. sw
#
#---------------------------------------------------------------------



import os
import sys

import network
import random
import string

commandfile = sys.argv[1]

SWAP_admin_console_exe = os.environ['SCANCO_SWAPCONSOLEADMIN_EXE']
SWAP_admin_console_exe = SWAP_admin_console_exe.strip('"')

scanco_uct_import_exe = os.environ['SCANCO_UCT_IMPORT_EXE']
scanco_uct_import_exe = scanco_uct_import_exe.strip('"')


letterList = 'abcdefghijklmnopqrstuvwxyz'
default_letter_no = 17
letter_no = default_letter_no

eval_isq       = os.environ['EVAL_ISQ']
eval_dir       = os.environ['EVAL_DIR']
eval_fname     = os.environ['EVAL_FNAME']
eval_sampno    = os.environ['EVAL_SAMPNO']
eval_shortname = os.environ['EVAL_SHORTNAME']
eval_opere     = os.environ['EVAL_OPERE']
scratch_dir    = os.environ['SYS$SCRATCH']

#Take default letter R. If an ISQ already starts with R use next letter etc
while letterList[letter_no] == eval_isq[0].lower():
   letter_no = letter_no + 1
   if letter_no == 26:
      letter_no = 0
   if letter_no == default_letter_no:
      with open(commandfile, "at") as commandfile_fp:
         print(f'ECHO ERROR: NO VALID FIRST LETTER FOUND. EXIT',file=commandfile_fp)
      exit()

new_isq = letterList[letter_no] + eval_fname[1:] + '.isq'
new_isq_local = scratch_dir + new_isq
tmp_isq = eval_dir + eval_fname + '_temp.isq'
tmp_isq_local = scratch_dir + eval_fname + '_temp.isq'

#
# ! Check if misc1_* parameter 'reimport' exists
#

misc_id = 0
reimport_flag = 0

for misc_id in range(20):
   misc_var = 'EVAL_MISC1_' + str(misc_id)
   if misc_var in os.environ:
      misc_var_trans = os.environ[misc_var]
      if misc_var_trans.lower() == 'reimport':
         reimport_flag = 1
         
         
         
if reimport_flag == 1:
   with open(commandfile, "at") as commandfile_fp:
      print(f'ECHO Reimport starts here...',file=commandfile_fp)
      print(f'"{SWAP_admin_console_exe}" get-file {tmp_isq} {new_isq_local}', file=commandfile_fp)
      #print(f'rename {tmp_isq_local} {new_isq}',file=commandfile_fp)
      #print(f'ECHO "{SWAP_admin_console_exe}" move-files {tmp_isq} {new_isq}', file=commandfile_fp)
      #print(f'"{SWAP_admin_console_exe}" move-files {tmp_isq} {new_isq}', file=commandfile_fp)
      print(f'"{scanco_uct_import_exe}" -i={new_isq_local} -s={eval_sampno} -t="{eval_shortname}" -n=N -r=Y -c=0 -o={eval_opere}', file=commandfile_fp)
      #delete temp files
      print(f'del {new_isq_local}',file=commandfile_fp)
      #print(f'"{SWAP_admin_console_exe}" delete-file {tmp_isq}', file=commandfile_fp)
      
else:
   with open(commandfile, "at") as commandfile_fp:
      print(f'REM',file=commandfile_fp)
      print(f'REM No misc parameter set to start reimport',file=commandfile_fp)
      print(f'REM',file=commandfile_fp)




##with open(commandfile, "at") as commandfile_fp:
##  print (f'Number of arguments:', len(sys.argv), 'arguments.',file=commandfile_fp)
##  print (f'Argument List:', str(sys.argv),file=commandfile_fp)

# def does_file_exist_in_hierarchy(virtualpath: str, connection) -> bool:
    # try:
        # token = network.get_sns_token(connection, [('read', virtualpath)], hierarchy='auto-parent')
        # return True
    # except:
        # return False
        

# project serial for ipl_file        
# host = os.environ['SNS_INLINE_PROFILE_HOST']
# port = os.environ['SNS_INLINE_PROFILE_HTTPS_PORT']
# password = os.environ['SNS_INLINE_PASSWORD']
# if 'SNS_INLINE_USERNAME' not in os.environ and 'SNS_INLINE_PROFILE_USERNAME' in os.environ:
    # username = os.environ['SNS_INLINE_PROFILE_USERNAME']
# else:
    # username = os.environ['SNS_INLINE_USERNAME']
# connection = network.Connection(host, port, network.basic_authentication(f"{username}:{password}"))
# project_serial = os.environ['SNS_OVERRIDE_PROJECT_SERIAL']

# ipl_file = f'@sns/project/{project_serial}/evalscript/iplv7_cvt_dicom.ipl'

# ipl_exe_filename = os.environ['SCANCO_IPL_EVAL_EXE']
# ipl_exe_filename = ipl_exe_filename.strip('"')



# startfile  = os.environ['EVAL_STARTFILE']
# fname0     = os.environ['EVAL_FNAME0']
# fname0orig = os.environ['EVAL_FNAME0']
# scale      = os.environ['EVAL_SCALE']
# sformat    = os.environ['EVAL_FORMAT']
# norm       = os.environ['EVAL_NORM']
# no_z       = os.environ['EVAL_NO_Z']
# voix       = os.environ['EVAL_VOIX']
# voiy       = os.environ['EVAL_VOIY']
# voiz       = os.environ['EVAL_VOIZ']
# voidx      = os.environ['EVAL_VOIDX']
# voidy      = os.environ['EVAL_VOIDY']
# voidz      = os.environ['EVAL_VOIDZ']
# quality    = os.environ['EVAL_QUALITY']
# misc1_3    = os.environ['EVAL_MISC1_3']


# scratch_dir = os.environ['SYS$SCRATCH']
# with open(commandfile, "at") as commandfile_fp:
  # print(f'ECHO SYS$SCRATCH: {scratch_dir}',file=commandfile_fp)
  
  

# if misc1_3.upper() != 'NONE':
  # with open(commandfile, "at") as commandfile_fp:
     # random_dir = ''.join(random.SystemRandom().choice(string.ascii_uppercase + string.digits) for _ in range(16))
     # cvt_dir = scratch_dir + 'cvt'
     
     # if not os.path.exists(cvt_dir):
         # os.mkdir(cvt_dir)
           
     # temp_dir = scratch_dir + 'cvt\\' + random_dir
     # temp_dir_dir = scratch_dir + 'cvt\\' + random_dir + '.dir'
     # os.mkdir(temp_dir)

     # temp_fname0 = fname0.replace(os.environ['EVAL_DIR'],'')
     # fname0 = temp_dir + '\\' + temp_fname0
     # zip_fname_local = fname0 + '_dcm.zip'

     # if misc1_3.upper() == 'MEASUREMENT':
        # zip_fname_remote = fname0orig + '_dcm.zip'
     # else:
        # export_dir   = os.environ['UCT_EXPORT']
        # zip_fname_remote = export_dir + temp_fname0 + '_dcm.zip'
        
     # temp_dir_cvt = temp_dir + '\\*.dcm'
     
     # with open(commandfile, "at") as commandfile_fp:
        # #overwrite ipl_fname0 (local temp file) for ipl script
        # print(f'set ipl_fname0={fname0}', file=commandfile_fp)


# with open(commandfile, "at") as commandfile_fp:               
        # print(f'"{ipl_exe_filename}" /execute {ipl_file} ..', file=commandfile_fp)



# if misc1_3.upper() != 'NONE':
  # with open(commandfile, "at") as commandfile_fp:
      # print(f'powershell Compress-Archive {temp_dir_cvt} {zip_fname_local}',file=commandfile_fp)
      # print(f'del/Q {temp_dir_cvt}',file=commandfile_fp)
      # print(f'"{SWAP_admin_console_exe}" put-file {zip_fname_local} {zip_fname_remote}', file=commandfile_fp)
# ##          print(f'del/Q {zip_fname_local}',file=commandfile_fp)
      # print(f'rmdir/Q/S {temp_dir}',file=commandfile_fp)
  
