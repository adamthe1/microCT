import os
import sys

import credentials
import network
import profiles


def does_file_exist_in_hierarchy(virtualpath: str, connection) -> bool:
    try:
        token = network.get_sns_token(connection, [('read', virtualpath)], hierarchy='auto-parent')
        return True
    except:
        return False


commandfile = sys.argv[1]

uct_list_exe_filename = os.environ['SCANCO_UCT_LIST_EXE']
uct_list_exe_filename = uct_list_exe_filename.strip('"')
SWAP_admin_console_exe = os.environ['SCANCO_SWAPCONSOLEADMIN_EXE']
SWAP_admin_console_exe = SWAP_admin_console_exe.strip('"')

profile_name = os.environ['SNS_PROFILE_NAME']
credentials_name = os.environ['SNS_CREDENTIALS_NAME']
profile = profiles.get_network_profile_by_name(profile_name)
if profile is None:
    raise Exception(f"No network profile found with name '{profile_name}'")
credential = credentials.get_credential_by_target_name(credentials_name)
if credential is None:
    raise Exception(f"No credential found with name '{credentials_name}'")
(_, password) = credential
host = profile.host
port = profile.port
username = profile.username
if (username is None or username == '') and 'SNS_INLINE_USERNAME' in os.environ:
    username = os.environ['SNS_INLINE_USERNAME']
connection = network.Connection(host, port, network.basic_authentication(f"{username}:{password}"))
project_serial = os.environ['SNS_OVERRIDE_PROJECT_SERIAL']

templates_path = f'@sns/project/{project_serial}/templates/'

# template search: 1) shortname 2) standard 3) V6-default
# first line is 'header', and second line must contain data, other lines will be ignored

eval_sheet = os.environ['EVAL_SHEET2']
if eval_sheet != "":
    template = f'{templates_path}{eval_sheet}.csv'
else:    
    eval_shortnamet = os.environ['EVAL_SHORTNAMET']
    template = f'{templates_path}prs_csv_{eval_shortnamet}.csv'

if not does_file_exist_in_hierarchy(template, connection):
    # Use standard E3 file
    template = f'{templates_path}prs_csv_standard.csv'
    if not does_file_exist_in_hierarchy(template, connection):
        # Use default file (V6)
        template = network.sns_translate_logical(connection, "UCT_3D_LIST_SHEET")

dir = os.environ['EVAL_DIR']
fname = os.environ['EVAL_FNAME']
shortnamet = os.environ['EVAL_SHORTNAMET']
e3x = os.environ['EVAL_E3X']
mgroup = os.environ['EVAL_MGROUP']
egroup = os.environ['EVAL_EGROUP']
mgroupnt = os.environ['EVAL_MGROUPNT']
egroupnt = os.environ['EVAL_EGROUPNT']
region = os.environ['EVAL_REGION']
version = os.environ['EVAL_VERSION']
uct_results = os.environ['UCT_RESULTS']
measno = os.environ['EVAL_MEASNO']
 
resultdir = f'{uct_results}{mgroup}_{mgroupnt}/{egroup}_{egroupnt}/' # with trailing / to make valid virtual path
#tmpfile1 = f'@sns/project/{project_serial}/evalscript/prerequisites/temp.txt'
#tmpfile2 = f'delete_me.tmp'
#tmpfile3 = f'{resultdir}delete_me.tmp'

if (int(egroup)==0):
     d3result = f'{dir}{fname}_{shortnamet}.csv'
     d3result_all = f'{dir}{fname}_{shortnamet}_summary.csv'
else:
     d3result = f'{dir}{fname}_e{egroup}_{shortnamet}.csv'
     d3result_all = f'{dir}{fname}_e{egroup}_{shortnamet}_summary.csv'

d3result_log = f'{resultdir}M{int(mgroup):04}_E{int(egroup):04}_{shortnamet}.csv'



# Reading out 3D result database and putting it into appended .txt files"
with open(commandfile, "at") as commandfile_fp:
    ## create mgroup/egroup folders by copy/delete tempfile
    #print(f'"{SWAP_admin_console_exe}" get-file {tmpfile1} {tmpfile2} --hierarchy auto-parent', file=commandfile_fp)
    #print(f'"{SWAP_admin_console_exe}" put-file {tmpfile2} {tmpfile3}', file=commandfile_fp)
    #print(f'"{SWAP_admin_console_exe}" delete-file {tmpfile3}', file=commandfile_fp)
    # create mgroup/egroup folder
    print(f'"{SWAP_admin_console_exe}" create-folder {resultdir}', file=commandfile_fp)
    # append results
    print(f'"{uct_list_exe_filename}" -t={template} -o={d3result}     -m={mgroup} -e={egroup} -r=1 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result}     -m={mgroup} -e={egroup} -r=2 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result}     -m={mgroup} -e={egroup} -r=3 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result}     -m={mgroup} -e={egroup} -r=4 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result}     -m={mgroup} -e={egroup} -r=5 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_all} -m={mgroup} -e={egroup} -r=1 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_all} -m={mgroup} -e={egroup} -r=2 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_all} -m={mgroup} -e={egroup} -r=3 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_all} -m={mgroup} -e={egroup} -r=4 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_all} -m={mgroup} -e={egroup} -r=5 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_log} -m={mgroup} -e={egroup} -r=1 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_log} -m={mgroup} -e={egroup} -r=2 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_log} -m={mgroup} -e={egroup} -r=3 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_log} -m={mgroup} -e={egroup} -r=4 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)
    print(f'"{uct_list_exe_filename}" -t={template} -a={d3result_log} -m={mgroup} -e={egroup} -r=5 -v={version} -e3x={e3x} -u=0 {measno}', file=commandfile_fp)