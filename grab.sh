#!/bin/sh

# LICENSE: WTFPLv2
# Don't trust google! You may do with this shit what the fuck do you want.

# Used binaries:
# sh cat sed grep od wc mv ln rm [ printf touch sleep cut
# wget/fetch
# sha1/sha1sum

# main script scheme
# 
#             init
#               V
#    read default conf file
#               V
#    get conf path from args
#               V
#    read got conf file path
#               V
#          parse args
#               V
#         validate args
#               V
#    ------------------------
#           V              V     
#         parser       search
#           V              V
#   ----------------    query
#    V            V        V
#   download  export    print
#    V            V    search
#   query      query  results
#    V            V
#   download& export
#   rename      file
#   files       list

# should initialize hardcoded variables defaults and logic variables
#
# args:
# output:
# side effect: defines variables
init() {
  g_version="Danbooru v7sh grabber v0.10.17 for Danbooru API v1.13.0";
# const
  c_anonymous_tag_limit="2";      # API const
  c_registred_tag_limit="6";      # API const
# logic
  l_engine="danbooru";             # "danbooru"
  l_mode="search";                 # "search" "download"
  l_search_mode="simple"           # "simple" "deep"
  l_search_order="count";          # "count" "name" "date"
  l_search_reverse_order="false";  # "false" "true"
  l_download_mode="onedir";        # "onedir" "onedir:symlinks" "samedir" "samedir:symlinks"
  l_download_page_size="100";      # 100 1..100..*
  l_download_page_offset="1";      # 1 1..
  l_verbose_level="3";             # 3 0..4
  l_validate_values="true";        # "true" "false"
  l_write_conf="false";            # "false" "true"
  l_fail_delay="10";               # 10 0..
  l_noadd="false";                 # auto add tags to actualize
  l_tag_limit="0";                 # defined in parse_args
  l_download_extensions_allow="";  # downloading extensions
  l_download_extensions_deny="";   # downloading extensions
  l_download_tag_limit_bypass="false";   #
  if in_system "wget"; then
    l_downloader="wget";
  elif in_system "fetch"; then
    l_downloader="fetch";
  elif in_system "curl"; then
    l_downloader="curl";
  else
    return 1;
  fi;
  if in_system "sha1sum"; then
    l_hasher="sha1sum";
  elif in_system "sha1"; then
    l_hasher="sha1";
  else
    return 2;
  fi;
# path
  p_exec_dir="$(dir_realpath "$0")";
  p_danbooru_url="http://danbooru.donmai.us";
  p_storage_dir="${p_exec_dir}/storage";
  p_storage_big_dir="${p_storage_dir}/files";
  p_temp_dir="${p_exec_dir}/tmp";
  p_conf_file="${HOME}/.config/danbooru-grab.conf";
  p_db_file="${p_storage_dir}/.tags";
# string
  s_auth_string="";
  s_auth_login="";
  s_auth_password_hash=""; #
  s_auth_password_salt="choujin-steiner--<password>--";
  s_tags="";
  s_rename_string="file:md5";
  s_export_format="file:url";
# args
  arg_tmp_password="false";
  return 0;
};

# should test if specified binary name at present in system
#
# args: binaryname
# output: binarypath
# side effect:
in_system() {
(
  program_name="${1-}";
  case "${PATH}" in
    (*[!:]:) PATH="${PATH}:"; ;;
  esac;
  IFS=":";
  for part_of_path in ${PATH}; do
    part_of_path="${part_of_path:-"."}";
    guess_path="${part_of_path}/${program_name}";
    if [ -f "${guess_path}" ] && [ -x "${guess_path}" ]; then
      return 0;
    fi;
  done;
  return 1;
)
};

# should return canonicalised absolute directory pathname
#
# args: binaryname
# output: binarypath
# side effect:
dir_realpath() {
(
  given_path="${1-}";
  if [ ! -d "${given_path}" ]; then
    given_path="${given_path%/*}"
  fi;
  if [ ! "${given_path}" ]; then
    given_path=".";
  fi;
  if [ ! -d "${given_path}" ]; then
    return 1;
  fi;
  cd "${given_path}";
  printf "%s" "${PWD}";
  return 0;
)
};

# should return directory name from given path
#
# args: path
# output: dirname
# side effect:
dirname() {
(
  path="${1-}";
  printf "%s" "${path%/*}";
  return 0;
)
};

# should do urlencoding
#
# args: string
# output: encoded string
# side effect:
urlencode() {
(
  IFS="";
  read -r input;
  printf "%s" "${input}" | od -t x1 -v | 
    sed 's/^[0-9]*//g;s/[[:space:]]\{1,\}/%/g;s/[%]*$//g;' | 
    while read -r line; do 
      printf "%s" "${line}"; 
    done;
  return 0;
)
};

# should return date and time in YYYYmmddHHMM.SS format
#
# args: unformated time
# output: formated time
# side effect:
dateformat() {
(
  date="${1-}";
  out="$(printf "%s" "${date}" | sed '
    s/^[a-zA-Z]*[[:space:]]*\([a-zA-Z]*\)[[:space:]]*\([0-9]*\)[[:space:]]*\([0-9]*\):\([0-9]*\):\([0-9]*\)[[:space:]]*[0-9+-]*[[:space:]]*\([0-9]*\)/\6\1\2\3\4.\5/g;
    s/Jan/01/g;s/Feb/02/g;s/Mar/03/g;s/Apr/04/g;s/May/05/g;s/Jun/06/g;s/Jul/07/g;s/Aug/08/g;s/Sep/09/g;s/Oct/10/g;s/Nov/11/g;s/Dec/12/g;')";
  printf "%s" "${out}";
  return 0;
)
};

# should print message, if message_level is lesser or equal l_verbose_level
#
# args: message_level message
# output:
# side effect: prints messge to cerr
notify() {
(
  print_level="${1-}";
  shift;
  message="$@";
  verbose_level="${l_verbose_level}";
  out=2;
  if [ "${print_level}" -le "${verbose_level}" ]; then
    case "${print_level}" in
      (0) out=1; ;;
      (1) message="Error: ${message}" ;;
      (2) ;;
      (3) message="Warning: ${message}" ;;
      (4) message="Debug: ${message}" ;;
    esac;
    message="$(printf "%s" "${message}" | sed 's/%/%%/g;')";
    printf "${message}" 1>&$out;
  fi;
  return 0;
)
};

# should make password hash from password and salt
#
# args: password password_salt
# output: hashed password
# side effect:
password_hash() {
(
  password_salt="${1-}";
  password="$(printf "%s" "${2-}" | sed 's,/,\\/,g;s,&,\\&,g;')";
  salted_pass="$(printf "%s" "${password_salt}" | sed "s/<password>/${password}/g;")";
  case "${l_hasher}" in
    ("sha1")
      out="$(printf "%s" "${salted_pass}" | sha1 | sed 's/[^a-f0-9]//g;')";
    ;;
    ("sha1sum")
      out="$(printf "%s" "${salted_pass}" | sha1sum | sed 's/[^a-f0-9]//g;')";
    ;;
  esac;
  printf "%s" "${out}";
  return 0;
)
};

# should parse grabber arguments
#
# args:
# output:
# side effect: redefines global variables
parse_args() {
  if [ "${1-}" = "get_conf" ]; then
    shift;
    while [ "${1-}" ]; do
      case "${1-}" in
        ("-c"|"--config") p_conf_file="${2-}"; [ "${2-}" ] && { shift; }; ;; 
      esac;
      shift;
    done;
    return 0;
  fi;
  shift;
  if [ ! "${1-}" ]; then
    set -- "--help";
  fi;
  s_tags="";
  while [ "${1-}" ]; do
    case "${1-}" in
      ("-?"|"-h"|"-help"|"--help") return 1; ;;
      ("-9") return 2; ;;
      ("-w"|"--write-config") l_write_conf="true"; ;;
      ("-d"|"--download") l_mode="download"; ;;
      ("-a"|"--actualize") l_mode="actualize"; ;;
      ("-an"|"--actualize-no-checks") l_mode="actualize-no-checks"; ;;
      ("-s"|"--search") l_action="search"; ;;
      ("-sr"|"--search-reverse") l_search_reverse_order="true"; ;;
      ("-n"|"--no-checks") l_validate_values="false"; ;;
      ("-v"|"--verbosity") l_verbose_level="$(printf "%d" "${2-}" 2>/dev/null)"; [ "${2-}" ] && { shift; } ; ;;
      ("-td"|"--tempdir") p_temp_dir="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-dm"|"--download-mode") l_download_mode="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-dea"|"--download-extensions-allow") l_download_extensions_allow="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-ded"|"--download-extensions-deny") l_download_extensions_deny="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-def"|"--download-export-format") s_export_format="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-dpo"|"--download-page-offset") l_download_page_offset="$(printf "%d" "${2-}" 2>/dev/null)"; [ "${2-}" ] && { shift; }; ;;
      ("-dps"|"--download-page-size") l_download_page_size="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-dsd"|"--download-storage-dir") p_storage_dir="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-dsn"|"--download-samedir") p_storage_big_dir="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-dfn"|"--download-file-name") s_rename_string="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-sm"|"--search-mode") l_search_mode="${2-}";  [ "${2-}" ] && { shift; }; ;;
      ("-so"|"--search-order") l_search_order="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-u"|"--username") s_auth_login="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-p"|"--password") tmp_password="${2-}"; arg_tmp_password="true"; [ "${2-}" ] && { shift; }; ;;
      ("-ps"|"--password-salt") s_auth_password_salt="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-url"|"--url") p_danbooru_url="${2-}"; [ "${2-}" ] && { shift; }; ;;
      ("-fd"|"--fail-delay") l_fail_delay="$(printf "%d" "${2-}" 2>/dev/null)"; [ "${2-}" ] && { shift; }; ;;
      (*) s_tags="${s_tags} ${1-}"; arg_s_tags="true"; ;;
    esac;
    shift;
  done;
  if [ "${arg_tmp_password}" = "true" ]; then
    s_auth_password_hash="$(password_hash "${s_auth_password_salt}" "${tmp_password}")";
  fi;
  if [ "${s_auth_login}" ] && [ "${s_auth_password_hash}" ]; then
    s_auth_string="&login=${s_auth_login}&password_hash=${s_auth_password_hash}";
  fi;
  if [ "${s_auth_string}" ]; then
    l_tag_limit="${c_registred_tag_limit}";
  else
    l_tag_limit="${c_anonymous_tag_limit}";
  fi;
  unset tmp_password;
  return 0;
};

# should print help message
#
# args:
# output:
# side effect: prints help message
help() {
(
  msg="\
${g_version}
USAGE: '$0' [OPTIONS] <TAGS>

  -h   --help
               Displays this help message.
  -c   --config                    <FILEPATH>
               Danbooru grabber configuration file.
               Default: '${p_conf_file}'
  -w   --write-config
               Write specified options to configuration file.
  -v   --verbosity
               Verbosity level. 
               Default: '${l_verbose_level}'
               0    search and export results
               1    + errors
               2    + progress display messages.
               3    + warning messages.
               4    + debug information
  -td --tempdir                    <DIRPATH>
               Directory for temp files.
               Default: '${p_temp_dir}'
  -d   --download
               Downloads images related to specified tags.
  -a   --actualize
               Actualizes tags contents according to ${p_db_file} file.
  -an  --actualize-no-checks
               Actualizes tags contents according to ${p_db_file} file, but do
               not check if such tags exists.
  -dm  --download-mode         <onedir|samedir|onedir:symlinks|samedir:symlinks>
               Download mechanism type. 
               Default: '${l_download_mode}'
               onedir            images for each specified tag will be saved to 
                                 seperated directories.
               samedir           all images for all specified tags will be saved
                                 in one directory, specified in samedir-name
                                 option.
               onedir:symlinks   same as onedir, but for each tag of each image
                                 will be created symlinks in other directories.
               samedir:symlinks  same as samedir, but for each tag of each image
                                 will be created symlinks in other directories.
               export            do not download, just print links in -def 
                                 specified format.
  -dea --download-extensions-allow <LIST>
               If specified, download only specified extensions.
               Default: '${l_download_extensions_allow}'
               Group into list using coma (,).
  -ded --download-extensions-deny  <LIST>
               If specified, do not download specified extensions.
               Default: '${l_download_extensions_deny}'
               Group into list using coma (,).
  -def --download-export-format    <FORMAT>
               Format of export output.
               Default: '${s_export_format}'
               file:url          file url
               file:preview_url  file preview image url
               file:sample_url   file sample image url
               file:tags         file tags
               file:md5          file md5 hash
               file:count        file number
               file:id           file id
               file:parent_id    file parent id
               file:source       file source url
  -dpo --download-page-offset      <1..>
               From which page begin grabbing.
               Default: '${l_download_page_offset}'
  -dps --download-page-size        <1..100>
               Amount of images per page. According to danbooru API v1.13.0 must
               be in 1.100 range, but in fact, with -n option, can be over 1000.
               Default: '${l_download_page_size}'
  -dsd --download-storage-dir      <DIRPATH>
               Directory to which all images will be saved.
               Default: '${p_storage_dir}'
  -dsn --download-samedir          <DIRPATH>
               Directory to which images will be saved if samedir download-type 
               specified.
               Default: '${p_storage_big_dir}'
  -dfn --download-file-name        <FORMAT>
               Filename scheme to which file will be renamed. 
               Default: '${s_rename_string}'
               file:count   file number
               file:id      file id
               file:height  file height
               file:width   file width
               file:tags    file tags
               file:md5     file md5 hash
               Filename will be automaticly trimmed to 255 symbols including
               automaticly adding extension.
  -s   --search
               Search in tags.
  -sm --search-mode                <simple|deep>
               Search mechanism type.
               Default: '${l_search_mode}'
               simple      Gets a little outdated number of images, but faster.
               deep        Gets actual number of images, but slower.
  -so  --search-order              <name|count|date>
               Search sort order.
               date
               count
               name
               Default: '${l_search_order}'
  -sr  --searh-reverse
               Reverse search order.
  -u   --username                  <USERNAME>
               Danbooru account username.
  -p   --password                  <PASSWORD>
               Danbooru account password.
  -ps  --password-salt             <PASSWORD SALT>
               Actual password salt. '<password>' will be replaced with actual
               password.
               Default: '${s_auth_password_salt}'
  -url --url                       <URL>
               Danbooru URL.
               Default: '${p_danbooru_url}'
  -fd  --fail-delay                <0..>
               Delay in seconds to wait on query fail before try again.
               Default: '${l_fail_delay}'
  -n   --no-checks
               Do not perform any values checks before sending to server. Most
               likely useless and even dangerous, if you do not understand what
               are you doing.
               Default: '${l_validate_values}'

  Options are overriding in that order:
  Hardcoded defaults -> Default config -> -c Specified config 
  -> Command-line options

  You also can combine tags through their intersection using ' ' (space) and 
  specify multiple tags for batch process using ',' (coma).

  by Cirno for Cirnos";
  notify 0 "${msg}\n";
  return 0;
)
};

# should print additional help message
#
# args:
# output:
# side effect: prints help message
help_atai() {
(
  data="\
6596587595311206559774424559934310788713755787758675220854486989612417858983208\
4187568447997417797922878013695859239776125799593357670215888758213323176576734\
0336755676885982469867634093175555587573486759624075136866683296877866340679813\
767558979796330697977133477982312097689987961341";
  notify 0 "$(printf "%s\n" "${data}" | sed "s/[$(printf "%s" "${data}" | sed 's/.*7\([6-8]\)87\(.\).*/\2/g;')-$(printf "%s" "${data}" | sed 's/.*673\(.\).*/\1/g;')]/#/g;s/[$(printf "%s" "${data}" | sed 's/.*\(.\)88875821332317657673403.*/\1/g;')-$(printf "%s" "${data}" | sed 's/.*18756844799741779792287801369585923\(.\).*/\1/g;')]/ /g;s/$(printf "%s" "${data}" | sed 's/.*3431078871375578775867522\(.\)[854]*869896124178589832.*/\1/g;')/\\\\n/g;")\n";
  return 0;
)
};

# should parse grabber configuration file
#
# args: filepath
# output:
# side effect: redefines global variables
read_conf() {
  file="${p_conf_file}";
  if [ ! -f "${file}" ]; then
    return 1;
  fi;
# sourcing another scripts can't be done directly in current directory, so there such performing is needed
  if printf "%s" "${file}" | grep -vq "[^\]/"; then
    file="./${file}";
  fi;
  . "${file}";
  return 0;
};

# should write configuration file
#
# args:
# output:
# side effect: writes configuration file
write_conf() {
(
  config="\
# ${g_version} configuration file.
# by Cirno for Cirnos

# Always write specified options to configuration file.
# Default: 'false'
l_write_conf='false'

# Verbosity level. 
# Default: '3'
# 0    search and export results
# 1    + errors
# 2    + progress display messages.
# 3    + warning messages.
# 4    + debug information
l_verbose_level='3'

# Directory for temp files.
# Default: '${p_temp_dir}'
p_temp_dir='${p_temp_dir}'

# Action which is performed by default.
# Default: 'search'
# search   search specified tags
# download download specified tags
l_mode='search'

# Download mechanism type. 
# Default: 'onedir'
# onedir           images for each specified tag will be saved to seperated 
#                  directories.
# samedir  l_verbosity_level        all images for all specified tags will be saved in one 
#                  directory, specified in samedir-name option.
# onedir:symlinks  same as onedir, but for each tag of each image will be 
#                  created symlinks in other directories.
# samedir:symlinks same as samedir, but for each tag of each image will be 
#                  created symlinks in other directories.
# export           do not download, just print links in s_export_format
l_download_mode='onedir'

# Export format
# Default: '${s_export_format}'
# file:url          file url
# file:preview_url  file preview image url
# file:sample_url   file sample image url
# file:tags         file tags
# file:md5          file md5 hash
# file:count        file number
# file:id           file id
# file:parent_id    file parent id
# file:source       file source
s_export_format='${s_export_format}'

# Filename scheme to which file will be renamed. 
# Default: '${s_rename_string}'
# file:count   file number
# file:id      file id
# file:height  file height
# file:width   file width
# file:tags    file tags
# file:md5     file md5 hash
# Filename will be automaticly trimmed to 255 symbols including automaticly 
# adding extension.
s_rename_string='${s_rename_string}'

# From which page begin grabbing.
# Default: '${l_download_page_offset}'
l_download_page_offset='${l_download_page_offset}'

# Amount of images per page. According to danbooru API v1.13.0 must be in 1..100
# range, but in fact, with no_checks=true option, can be over 1000.
# Default: '100'
l_download_page_size='100'

# Directory to which all images will be saved.
# Default: '${p_storage_dir}'
p_storage_dir='${p_storage_dir}'

# Directory to which images will be saved if samedir download_type specified.
# Default: '${p_storage_big_dir}'
p_storage_big_dir='${p_storage_big_dir}'

# If defined, download only specified extenstions
# Default: ''
# Group intlo list using coma.
#l_download_extensions_allow='jpg,gif,png'

# If set to true, no tags will be added to '${p_db_file}'
# Default: 'false'
l_noadd=false

# If defined, do not download specified extenstions
# Default: ''
# Group intlo list using coma.
#l_download_extensions_deny='tiff,psd,xcf,bmp'

# Search mechanism type.
# Default: 'simple'
# simple  Gets a little outdated number of images, but faster.
# deep    Gets actual number of images, but slower.
l_search_mode='simple'

# Search sort order.
# Default: 'count'
# name
# count
# date
l_search_order='count'

# Reverse search order.
# Default: 'false'
# true
# false
l_search_reverse_order='false'

# Danbooru account username.
s_auth_login='${s_auth_login}'

# Danbooru account password hash.
s_auth_password_hash='${s_auth_password_hash}'

# Actual password salt. '<password>' will be replaced with actual password.
# Default: '${s_auth_password_salt}'
s_auth_password_salt='${s_auth_password_salt}'

# Danbooru URL.
# Default: '${p_danbooru_url}'
p_danbooru_url='${p_danbooru_url}'

# Delay in seconds to wait on query fail before try again.
# Default: '${l_fail_delay}'
l_fail_delay='${l_fail_delay}'

# Do not perform any values checks before sending to server. Most likely useless
# and even dangerous, if you do not understand what are you doing.
# Default: 'true'
l_validate_values='true'
";
  printf "%s" "${config}" > "${p_conf_file}";
  return 0;
)
};

# should ask user for creating file and it's actual name&path
#
# args: type path name
# output:
# side effect: creates files and directories
ask_to_make() {
(
  type="${1-}";
  path="${2-}";
  name="${3-}";
  if [ "${name}" != "force" ]; then
    notify 2 "Enter ${name} path [${path}]: ";
    read -r newpath;
  fi;
  path="${newpath:-${path}}";
  if [ ! -e "${path}" ]; then
    case "${type}" in
      ("conf")
        p_conf_file="${path}";
        write_conf;
      ;;
      ("dir")
        mkdir -p "${path}";
      ;;
    esac;
  fi;
  printf "%s" "${path}";
  return 0;
)
};

# should test if all user-specified values are correct
#
# args: filepath
# output:
# side effect: prints error messages
validate_values() {
  if [ ! -e "${p_temp_dir}" ]; then
    p_temp_dir="$(ask_to_make "dir" "${p_temp_dir}" "temp dir")";
    l_write_conf="true";
  fi;
  if [ "${l_mode}" = "download" ]; then
    if [ ! -e "${p_storage_dir}" ]; then
      p_storage_dir="$(ask_to_make "dir" "${p_storage_dir}" "storage dir")";
      l_write_conf="true";
    fi;
    case "${l_download_mode}" in
      ("samedir"|"samedir:symlinks")
        if [ ! -e "${p_storage_big_dir}" ]; then
          p_storage_big_dir="$(ask_to_make "dir" "${p_storage_big_dir}" "storage big dir")";
          l_write_conf="true";
        fi;
      ;;
    esac;
  fi;
  if [ ! -e "${p_conf_file}" ]; then
    if [ ! -e "$(dirname "${p_conf_file}")" ]; then
      ask_to_make "dir" "$(dirname "${p_conf_file}")" "force";
    fi;
#    p_conf_file="$(ask_to_make "conf" "${p_conf_file}" "configuration file")";
    write_conf;
  fi;
(
  if [ "${l_fail_delay}" -lt 0 ]; then
    notify 1 "l_fail_delay (-fd) must not be lesser then 0.\n";
    return 1;
  fi;
  if [ "${s_auth_password_hash}" ] || [ "${s_auth_login}" ]; then
    if [ ! "${s_auth_password_hash}" ]; then
      notify 1 "s_auth_password_hash (-p) must not be null, if s_auth_login (-u) specified.\n";
      return 3;
    fi;
    if [ ! "${s_auth_login}" ]; then
      notify 1 "s_auth_login (-u) must not be null, if s_auth_password_hash (-p) specified.\n";
      return 4;
    fi;
    if printf "%s" "${s_auth_password_salt}" | grep -vq "<password>"; then
      notify 1 "s_auth_password_salt (-ps) must contain '<password>' token.\n";
      return 5;
    fi;
  fi;
  if printf "%s" "${p_danbooru_url}" | grep -vq "^http://"; then
    notify 1 "'${p_danbooru_url}' is not valid danbooru url for p_danbooru_url (-url).\n";
    return 6;
  fi;
  case "${l_write_conf}" in
    ("true"|"false") ;;
    (*)
      notify 1 "l_write_config must be 'true' or 'false'.\n";
      return 9;
    ;;
  esac
  case "${l_validate_values}" in
    ("true"|"false") ;;
    (*)
      notify 1 "l_validate_values must be 'true' or 'false'.\n";
      return 10;
    ;;
  esac
  case "${l_mode}" in
    ("search")
      case "${l_search_mode}" in
        ("simple") ;;
        ("deep") ;;
        (*)
          notify 1 "l_search_mode (-sm) must be 'simple' or 'deep'.\n";
          return 11;
        ;;
      esac;
      case "${l_search_order}" in
        ("count") ;;
        ("name") ;;
        ("date") ;;
        (*)
          notify 1 "l_search_order (-so) must be 'count', 'name' or 'date'.\n";
          return 12;
        ;;
      esac;
      case "${l_search_reverse_order}" in
        ("true"|"false") ;;
        (*)
          notify 1 "l_validate_values must be 'true' or 'false'.\n";
          return 13;
        ;;
      esac
    ;;
    ("download")
      case "${l_download_mode}" in
        ("onedir"|"onedir:symlinks") ;;
        ("samedir"|"samedir:symlinks") ;;
        ("export") ;;
        (*)
          notify 1 "l_download_mode (-dm) must be 'onedir', 'onedir:symlinks', 'samedir', 'samedir:symlinks' or 'export'.\n";
          return 14;
        ;;
      esac;
      if [ "${l_download_page_size}" -lt 1 ]; then
        notify 1 "l_download_page_size (-dps) must not be lesser then 1.\n";
        return 15;
      fi;
      if [ "${l_download_page_size}" -gt 100 ]; then
        notify 3 "using l_download_page_size (-dps) over 100, you are acting not acording to API documentation; unexpected things may happen.\n";
      fi;
      if [ "${l_download_page_offset}" -lt 1 ]; then
        notify 1 "l_download_page_offset (-dpo) must not be lesser then 1.\n";
        return 16;
      fi;
      case "${l_noadd}" in
        ("true"|"false") ;;
        (*)
          notify 1 "l_noadd be 'true' or 'false'.\n";
          return 17;
        ;;
      esac;
    ;;
    ("actualize") ;;
    ("actualize-no-checks") ;;
    (*)
      notify 1 "l_action must be 'search', 'actualize', 'actualize-no-checks' or 'download'.\n";
      return 18;
    ;;
  esac;
  return 0;
)
};

# should just try to download files
#
# args: url local_path
# output:
# side effect: saves file to local path
downloader() {
(
  url="${1-}";
  local_filepath="${2-}";
  case "${l_downloader}" in
    ("wget")
      result="$(LANG=C wget -c -O "${local_filepath}" "${url}" 2>&1)" || {
        if printf "%s" "${result}" | grep -q "ERROR [0-9]*"; then
          printf "%s" "${result}" | sed -n "/ERROR/{s/.*ERROR //g;p;};";
          return 1;
        fi;
        if printf "%s" "${result}" | grep -q "unable to resolve host address"; then
          return 2;
        fi;
      };
    ;;
    ("fetch")
      result="$(LANG=C fetch -m -o "${local_filepath}" "${url}" 2>&1)" || {
        if printf "%s" "${result}" | grep -q "fetch: http://[^:]*: [A-Z]"; then
          printf "%s" "${result}" | sed -n "s/.*://g;p;";
          return 1;
        fi;
        if printf "%s" "${result}" | grep -q "No address record"; then
          return 2;
        fi;
      };
    ;;
    ("curl")
      LANG=C curl "${url}" -s -C - -o "${local_filepath}" || {
        if [ "$?" -eq 6 ]; then
          return 2;
        fi;
      };
    ;;
  esac;
  return 0;
)
};

# should download, move and rename files
#
# args:
# output:
# side effect: downloads, moves and renames files
download() {
(
  post_file_name="$(printf "%s" "${s_rename_string}" | sed "
    s/file:count/$(printf "%0${#total_count}d" "${count}")/g;
    s/file:id/${post_id}/g;
    s/file:height/${post_height}/g;
    s/file:width/${post_width}/g;
    s/file:tags/${safe_tags}/g;
    s/file:md5/${post_md5}/g;
    s/[[:space:]]*&[#0-9a-zA-Z]*[[:space:]]*;//g;
    s/^\(.\{0,$((254-${#post_file_ext}))\}\).*/\1/g;
  ").${post_file_ext}";
  notify 2 "    downloading file ${post_file_name} ($(printf "%0${#total_count}d" "${count}")/${total_count})...";
  case "${l_download_mode}" in
    ("onedir"|"onedir:symlinks") file_path="${p_storage_dir}/${safe_tag}/${post_file_name}"; ;;
    ("samedir"|"samedir:symlinks") file_path="${p_storage_big_dir}/${post_file_name}"; ;;
  esac;
  if [ -e "${file_path}" ]; then
    notify 2 "skip\n";
    if [ "${l_download_mode}" = "onedir:symlinks" ] || [ "${l_download_mode}" = "samedir:symlinks" ]; then
      IFS=" ";
      for i_tag in ${post_tags}; do
        i_tag="$(printf "%s" "${i_tag}" | sed 's,[/],,g;s/[[:space:]]\{1,\}/-/g;')";
        if [ "${i_tag}" = "${safe_tag}" ] && [ "${l_download_mode}" = "onedir:symlinks" ]; then
          continue;
        fi;
        if [ ! -d "${p_storage_dir}/${i_tag}" ]; then
          mkdir "${p_storage_dir}/${i_tag}";
        fi;
        ln -s "${file_path}" "${p_storage_dir}/${i_tag}/" 2>/dev/null;
        touch -acm -t "$(dateformat "${post_created_at}")" "${p_storage_dir}/${i_tag}/${post_file_name}";
      done;
    fi;
    return 0;
  fi;
  post_file_url="$(printf "%s" "${post_file_url}" | sed 's|\\/|\/|g')";
  tmpfile="${p_temp_dir}/$$-danbooru_grabber_temp_content_file";
  get_file "persist" "${post_file_url}" "${tmpfile}";
  case "${l_download_mode}" in
    ("onedir")
      if [ ! -d "${p_storage_dir}/${safe_tag}" ]; then
        mkdir "${p_storage_dir}/${safe_tag}";
      fi;
      mv "${tmpfile}" "${file_path}";
      touch -acm -t "$(dateformat "${post_created_at}")" "${file_path}";
    ;;
    ("samedir")
      mv "${tmpfile}" "${file_path}";
      touch -acm -t "$(dateformat "${post_created_at}")" "${file_path}";
    ;;
    ("onedir:symlinks"|"samedir:symlinks")
      if [ ! -d "${p_storage_dir}/${safe_tag}" ] && [ "${l_download_mode}" = "onedir:symlinks" ]; then
        mkdir "${p_storage_dir}/${safe_tag}";
      fi;
      mv "${tmpfile}" "${file_path}";
      touch -acm -t "$(dateformat "${post_created_at}")" "${file_path}";
      IFS=" ";
      for i_tag in ${post_tags}; do
        i_tag="$(printf "%s" "${i_tag}" | sed 's,[/],,g;s/[[:space:]]\{1,\}/-/g;')";
        if [ "${i_tag}" = "${safe_tag}" ] && [ "${l_download_mode}" = "onedir:symlinks" ]; then
          continue;
        fi;
        if [ ! -d "${p_storage_dir}/${i_tag}" ]; then
          mkdir "${p_storage_dir}/${i_tag}";
        fi;
        ln -s "${file_path}" "${p_storage_dir}/${i_tag}/" 2>/dev/null;
        touch -acm -t "$(dateformat "${post_created_at}")" "${p_storage_dir}/${i_tag}/${post_file_name}";
      done;
    ;;
  esac;
  notify 2 "done\n";
  return 0;
)
};

# should export file list
#
# args:
# output:
# side effect: prints file list
export_out() {
(
  string="$(printf "%s" "${s_export_format}" | sed "
    s/file:url/${post_file_url}/g;
    s/file:preview_url/${post_preview_url}/g;
    s/file:sample_url/${post_sample_url}/g;
    s/file:tags/${safe_tags}/g;
    s/file:md5/${post_md5}/g;
    s/file:count/$(printf "%0${#total_count}d" "${count}")/g;
    s/file:id/${post_id}/g;
    s/file:parent_id/${post_parent_id}/g;
    s/file:source/${post_source}/g;
  ")";
  notify 0 "${string}\n";
  return 0;
)
};

# should initialize functions for danbooru parsing
#
# args:
# output:
# side effect: defines funcionts
init_danbooru() {
# should download files and handle download errors
#
# args: url local_path
# output:
# side effect: saves file to local path
  get_file() {
  (
    persist="false"; 
    if [ "${1-}" = "persist" ]; then
      persist="true"; 
      shift;
    fi;
    url="${1-}";
    local_filepath="${2-}";
#    url_safe="$(printf "%s" "${url}" | sed 's,/,\\/,g;s,&,\\&,g;')";
#    safe_filepath="$(printf "%s" "${local_filepath}" | sed 's,/,\\/,g;s,&,\\&,g;')";
    if [ -e "${local_filepath}" ]; then
      rm "${local_filepath}";
    fi;
    while [ true ]; do
      while [ true ]; do
        result="$(downloader "${url}" "${local_filepath}")";
        case "$?" in
          (0) break; ;;
          (1) notify 3 "HTTP ERROR "${result}"\n"; ;;
          (2) notify 1 "unable to resolve host address '${url}'.\n"; ;;
        esac;
        sleep "${l_fail_delay}";
      done;
# tested on ~30 thousands of images without any single match, so considired as image-binary-safe.
      if grep -q "The site is down for maintenance" "${local_filepath}"; then
        notify 1 "Danbooru is currently down for maintenance.\n";
        rm "${local_filepath}";
        sleep "${l_fail_delay}";
        if [ "${persist}" = "true" ]; then
          continue;
        fi;
        return 2;
      fi;
      break;
    done;
    return 0;
  )
  };
  
  # should process api queries, logging in and urlencoding
  #
  # args: type params ispersist
  # output: query_reply
  # side effect:
  query() {
  (
    type="${1-}";
    params="${2-}";
    persist="${3:-}";
    case "${type}" in
      ("tag") url="${p_danbooru_url}/tag/index.xml?"; ;;
      ("post") url="${p_danbooru_url}/post/index.xml?"; ;;
    esac;
    temp_file="${p_temp_dir}/$$-danbooru_grabber_query_result";
    IFS=",";
    for param in ${params}; do
      IFS=" ";
      arg="$(printf "%s" "${param}" | sed 's/=.*//g;')";
      case "${arg}" in
        ("tags"|"name")
          out="";
          for tag in $(printf "%s" "${param}" | sed 's/^[^=]*=//g'); do
            out="${out}+$(printf "%s" "${tag}" | urlencode)";
          done;
          value="$(printf "%s" "${out}" | sed 's/^+//g;')";
        ;;
        (*)
          value="$(printf "%s" "${param}" | sed 's/^[^=]*=//g;' | urlencode)";
        ;;
      esac;
      url="${url}${arg}=${value}&";
    done;
    url="$(printf "%s" "${url}" | sed 's/&$//g;')";
    url="${url}${s_auth_string}";
    get_file ${persist} "${url}" "${temp_file}";
    cat "${temp_file}" | sed 's/&amp;/\&/g;';
    rm -f "${temp_file}";
  )
  };

  # should get actual count of specified tag
  #
  # args: ispersist tag
  # output: count
  # side effect:
  get_count() {
  (
    persist="";
    if [ "${1-}" = "persist" ]; then
      persist="${1-}";
      shift;
    fi;
    tag="${1-}";
    tagcount="$(($(printf "%s" "${tag}" | grep -c " ")+1))";
    if [ "${tagcount}" -lt "${l_tag_limit}" ]; then
      tag="${tag} status:active";
    fi;
    result="$(query "post" "limit=1,page=1,tags=${tag}" ${persist} | sed -n '/<posts/{s/.*count="\([0-9]*\)".*/\1/p;};')";
    printf "%d" "${result}";
    return 0;
  )
  };

  # should search in tags by given wildcard
  #
  # args: wildcard
  # output:
  # side effect: print search results
  search() {
  (
    tag="${1-}";
    result="$(query "tag" "order=${l_search_order},name=${tag}")" || { return 1; };

    if [ "$(printf "%s" "${tag}" | wc -w)" -ge 2 ] || printf "%s" "${result}" | grep -q '<tags type="array"/>'; then
      result="0 mixed ${tag}";
      l_search_mode="deep";
    else
      result="$(printf "%s\n" "${result}" | sed -n '/<tag /{s/type="0"/type="general"/g;s/type="1"/type="artist"/g;s/type="3"/type="title"/g;s/type="4"/type="character"/g;s/.*type="\([^"]*\)".*count="\([0-9]*\)".*name="\([^"]*\)".*/\2 \1 \3/g;p;};')";
      if [ "${l_search_reverse_order}" = "true" ]; then
        result="$(printf "%s\n" "${result}" | tac )";
      fi;
    fi;
    IFS=" ";
    printf "%s\n" "${result}" | while read -r line; do
      case "${l_search_mode}" in
        ("simple")
          notify 0 "$(printf "%#10s %#9s %s" ${line})\n";
        ;;
        ("deep")
          type="$(printf "%s" "${line}" | cut -d' ' -f2)";
          tag="$(printf "%s" "${line}" | cut -d' ' -f3-)";
          notify 0 "$(printf "%#10d %#9s ${tag}\n" "$(get_count "${tag}")" "${type}")\n";
        ;;
      esac;
    done;
    return 0;
  )
  };

  # should parse api data replise
  #
  # args: tag
  # output:
  # side effect: do all the stuff
  parser() {
  (
    tag="${1-}";
    notify 2 "Begining downloading for tag '${tag}'.\n";
    total_count="$(get_count "persist" "${tag}")";
    if [ "${total_count}" -eq 0 ]; then
      notify 1 "there is no tag '${tag}'.\n";
      return 1;
    fi;
    if [ "${l_noadd}" != "true" ] && [ "$(grep -c "^[[:space:]]*${tag}[[:space:]]*$" "${p_db_file}")" -eq 0 ]; then
      add_tag_to_db "${tag}";
    fi;
    total_pages="$(((${total_count}/${l_download_page_size})+((${total_count}%${l_download_page_size})&&1)))";
    page="${l_download_page_offset}";
    while [ "${page}" -le "${total_pages}" ]; do
      notify 2 "  Switching to page ${page} of ${total_pages}.\n";
      count="$((${page}*${l_download_page_size}-${l_download_page_size}+1))";
      result="$(query "post" "limit=${l_download_page_size},page=${page},tags=${tag}" "persist" | sed -n '/<post /{p;};')";
      printf "%s\n" "${result}" | while read -r post; do
        post_tags="$(printf "%s" ${post} | sed 's/.*tags="\([^"]*\)".*/\1/g;')";
        post_created_at="$(printf "%s" ${post} | sed 's/.*created_at="\([^"]*\)".*/\1/g;')";
        post_height="$(printf "%s" ${post} | sed 's/.*height="\([^"]*\)".*/\1/g;')";
        post_md5="$(printf "%s" ${post} | sed 's/.*md5="\([^"]*\)".*/\1/g;')";
        post_file_url="$(printf "%s" ${post} | sed 's/.*file_url="\([^"]*\)".*/\1/g;')";
        post_preview_url="$(printf "%s" ${post} | sed 's/.*preview_url="\([^"]*\)".*/\1/g;')";
        post_sample_url="$(printf "%s" ${post} | sed 's/.*sample_url="\([^"]*\)".*/\1/g;')";
        post_parent_id="$(printf "%s" ${post} | sed 's/.*parent_id="\([^"]*\)".*/\1/g;')";
        post_id="$(printf "%s" ${post} | sed 's/.*id="\([^"]*\)".*/\1/g;')";
        post_source="$(printf "%s" ${post} | sed 's/.*source="\([^"]*\)".*/\1/g;')";
        post_width="$(printf "%s" ${post} | sed 's/.*width="\([^"]*\)".*/\1/g;')";
        safe_tag="$(printf "%s" "${tag}" | sed 's,[/],,g;s/[[:space:]]\{1,\}/-/g;')";
        safe_tags="$(printf "%s" ${post_tags} | sed 's,[/],,g;s/[[:space:]]\{1,\}/-/g;s/&/\\&/g;')";
        post_file_ext="$(printf "%s" "${post_file_url}" | sed 's/.*\.//g')";
        this_is_allowed="true";
        IFS=",";
        if [ "${l_download_extensions_allow}" ]; then
          this_is_allowed="false";
          for ext_rule in ${l_download_extensions_allow}; do
            ext_rule="$(printf "%s" "${ext_rule}" | sed 's/^[[:space:]]*//g;s/[[:space:]]*$//g;')";
            if [ "${ext_rule}" = "${post_file_ext}" ]; then
              this_is_allowed="true";
            fi;
          done;
        fi;
        if [ "${l_download_extensions_deny}" ]; then
          for ext_rule in ${l_download_extensions_deny}; do
            ext_rule="$(printf "%s" "${ext_rule}" | sed 's/^[[:space:]]*//g;s/[[:space:]]*$//g;')";
            if [ "${ext_rule}" = "${post_file_ext}" ]; then
              this_is_allowed="false";
            fi;
          done;
        fi;
        if [ "${this_is_allowed}" = "false" ]; then
          continue;
        fi;
        case "${l_download_mode}" in
          ("export") export_out; ;;
          (*) download; ;;
        esac;
        count="$((${count}+1))";
      done;
      page="$((${page}+1))";
    done;
    notify 2 "Downloading for tag '${tag}' has been finished.\n";
    return 0;
  )
  };
};

add_tag_to_db() {
(
  tag="${1-}";
  printf "%s\n" "${tag}" >> "${p_db_file}";
)
};

actualize() {
(
  if [ ! -e "${p_db_file}" ]; then
    touch "${p_db_file}";
    tagsguide="\
# in this file tags adding after each download.
# one tag per line in usual -d syntax
# eg:
#
# iwakura_lain
# touhou cirno
# cirno chen yakumo_ran
";
    printf "%s" "${tagsguide}" > "${p_db_file}";
  fi;
  content="$(cat "${p_db_file}" | sed -n '/^[[:space:]]*[^#]\+/{s/^[[:space:]]*//g;s/[[:space:]]*$//g;p;};' | uniq)";
  if [ ! "${content}" ]; then
    notify 3 "No tags for auto update.\n";
    return 0;
  fi;
  if [ "${1-}" != "nocheck" ]; then
    content="$(printf "${content}\n" | while read tag; do
      total_count="$(get_count "persist" "${tag}")";
      if [ "${total_count}" -eq 0 ]; then
        notify 3 "there is no tag '${tag}'.\n";
        continue;
      fi;
      if [ "$(grep -c "^[[:space:]]*${tag}[[:space:]]*$" "${p_db_file}")" -gt 1 ]; then
        notify 3 "there is multiple entries for tag '${tag}'.\n";
      fi;
      printf "%s\n" "${tag}";
    done)";
  fi;
  IFS='
';
  
  printf "%s\n" "executing: $0 -d '$(printf "%s" $(printf "%s" "${content}" | sed 's/$/, /g;') | sed 's/[,]*[[:space:]]*$//g;')'";
  main "noadd" -d "$(printf "%s" $(printf "%s" "${content}" | sed 's/$/,/g;') | sed 's/[,]*$//g;')";
)
};

clean_tmp() {
(
  rm -f "${p_temp_dir}/$$-danbooru_grabber_query_result";
  rm -f "${p_temp_dir}/$$-danbooru_grabber_temp_content_file";
)
}

# should do everything that this grabber should
#
# args:
# output:
# side effect: works sometimes
main() {
  if [ "${1-}" = "noadd" ]; then
    l_noadd="true";
    shift;
  fi;
  init || { return 1$?; };
  if [ -d "${p_temp_dir}" ]; then
    cd "${p_temp_dir}";
    for tempfile in *-danbooru_grabber_*; do
      if [ ! -e "${tempfile}" ]; then
        continue;
      fi;
      if [ "${tempfile}" = "${p_temp_dir}/*-danbooru_grabber" ]; then
        continue;
      fi;
      pid="$(printf "%s" "${tempfile}" | sed 's/-.*//g;s|.*/||g;')";
      ps -p "${pid}" 1>/dev/null || { rm ${tempfile}; };
    done;
    cd "$OLDPWD";
  fi;
  read_conf;
  parse_args "get_conf" "$@";
  read_conf;
  parse_args "all" "$@";
  case "$?" in
    (0) ;;
    (1) help; return 0; ;;
    (2) help_atai; return 0; ;;
    (*) return "2$?";
  esac;
  case "${l_engine}" in
    ("danbooru") init_danbooru; ;;
  esac;
(
  if [ "${l_validate_values}" = "true" ]; then
    validate_values || { return "3$?"; };
  fi;
  if [ "${l_write_conf}" = "true" ]; then
    write_conf "${p_conf_file}";
  fi;
  IFS=",";
  for tag in ${s_tags}; do
    tag="$(printf "%s" "${tag}" | sed 's/^[[:space:]]*//g;s/[[:space:]]*$//g;')"
    tagcount="$(printf "%s" "${tag}" | wc -w)";
    if [ "${tagcount}" -gt "${l_tag_limit}" ]; then
      tag="$(printf "%s" "${tag}" | sed 's/^[[:space:]]*//g;s/[[:space:]]*$//g;')";
      if [ "${s_auth_string}" ]; then
        notify 3 "number of natively intersecting tags ('${tag}') can't be more then ${c_registred_tag_limit} for registred user.\n";
      else
        notify 3 "number of natively intersecting tags ('${tag}') can't be more then ${c_anonymous_tag_limit} for anonymous user. You can rise it up to ${c_registred_tag_limit} by registering and specifing username (-u,s_auth_login) and password (-p,s_auth_password_hash) options.\n";
      fi;
      notify 2 "Activating manual tag intersection.\n";
      l_download_tag_limit_bypass="true";
    fi;
    case "${l_mode}" in
      ("search") search "${tag}"; ;;
      ("download") parser "${tag}"; ;;
    esac;
  done;
  case "${l_mode}" in
    ("actualize") actualize; ;;
    ("actualize-no-checks") actualize "nocheck"; ;;
  esac;

  clean_tmp;

  return 0;
)
};

# main grabber code.
#set -u; # enable strict variable handling
main "$@";
exit "$?";
