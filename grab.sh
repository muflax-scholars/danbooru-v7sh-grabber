#!/bin/ash

# main script scheme
# 
#          init
#           V
# read default conf file
#           V
# get conf path from args
#           V
# read got conf file path
#           V
#       parse args
#           V
#     validate args
#           V
#    ---------------
#    V             V
#   download    search
#    V             V
#   query        query
#    V             V
#   download&    print
#   rename      search
#   files      results

#
# should test if specified binary name at present in system
#
# args: binaryname
# output: binarypath
# side effect:
which() {
(
  case "${PATH}" in
    (*[!:]:) PATH="${PATH}:"; ;;
  esac;
  program="$1";
  IFS=":";
  for element in ${PATH}; do
    if [ ! "${element}" ]; then
      element=".";
    fi;
    if [ -f "${element}/${program}" ] && [ -x "${element}/${program}" ]; then
      printf "%s" "${element}/${program}";
      break;
    fi;
  done;
  return 1;
)
};
dirname() {
(
  path="$1";
  out="$(printf "%s" "$1" | sed 's|\(.*\)/[^/]*|\1|g;')";
  printf "%s" "${out}";
  return 0;
)
};

urlencode() {
(
  IFS="";
  read -r input;
  out="$(printf "%s" "${input}" | od -t x1 -v | sed 's/^[0-9]*//g;s/[[:space:]]\{1,\}/%/g;s/[%]*$//g;' | while read -r line; do printf "%s" "${line}"; done)";
  printf "%s" "${out}";
  return 0;
)
};

dateformat() {
(
  date="$1";
  out="$(printf "%s" "${date}" | sed 's/^[a-zA-Z]*[[:space:]]*\([a-zA-Z]*\)[[:space:]]*\([0-9]*\)[[:space:]]*\([0-9]*\):\([0-9]*\):\([0-9]*\)[[:space:]]*[0-9+-]*[[:space:]]*\([0-9]*\)/\6\1\2\3\4.\5/g;s/Jan/01/g;s/Feb/02/g;s/Mar/03/g;s/Apr/04/g;s/May/05/g;s/Jun/06/g;s/Jul/07/g;s/Aug/08/g;s/Sep/09/g;s/Oct/10/g;s/Nov/11/g;s/Dec/12/g;')";
  printf "%s" "${out}";
  return 0;
)
};

# should initialize hardcoded variables defaults and logic variables
#
# args:
# output:
# side effect: defines variables
init() {
  g_version="Danbooru v7sh grabber v0.10.0 for Danbooru API v1.13.0";
# const
  c_anonymous_tag_limit="2";      # API const
  c_registred_tag_limit="6";      # API const
# logic
  l_mode="search";                # "search" "download"
  l_search_mode="simple"          # "simple" "deep"
  l_search_order="count";         # "count" "name" "date"
  l_search_reverse_order="false"; # "false" "true"
  l_download_mode="onedir";       # "onedir" "onedir:symlinks" "samedir" "samedir:symlinks"
  l_download_page_size="100";     # 100 1..100..*
  l_download_page_offset="1";     # 1 1..
  l_verbose_level="3";            # 3 0..4
  l_validate_values="true";       # "true" "false"
  l_write_conf="false";           # "false" "true"
  l_fail_delay="60";              # 60 0..
  l_tag_limit="0";                # defined in parse_args
# path
  p_exec_dir="$(
    scriptpath="$(printf "%s" "$(dirname "$0")" | sed "s|\.\./[^/]*||g;s|^[./]+|/|g;")";
    firstchar="$(printf "%s" "${scriptpath}" | sed 's/^\(.\).*/\1/g;')";
    if [ "${firstchar}" = "/" ] && [ "${scriptpath}" != "/" ] && [ -e "${scriptpath}" ]; then
      printf "%s" "${scriptpath}";
    elif [ "${firstchar}" = "/" ] && [ "${scriptpath}" != "/" ] && [ ! -e "${scriptpath}" ]; then
      printf "%s" "${PWD}${scriptpath}";
    else
      printf "%s" "${PWD}";
    fi;
  )";
  p_danbooru_url="http://danbooru.donmai.us";
  p_storage_dir="${p_exec_dir}/storage";
  p_storage_big_dir="${p_storage_dir}/files";
  p_temp_dir="${p_exec_dir}/tmp";
  p_conf_file="${HOME}/.config/danbooru-grab.conf";
# string
  s_auth_string="";
  s_auth_login="";
  s_auth_password_hash=""; #
  s_auth_password_salt="choujin-steiner--<password>--";
  s_tags="";
  s_rename_string="file:md5";
  s_export_format="file:url";
  if [ "$(which "wget")" ]; then
    b_downloader="wget -c -O PATH URL";
    r_http_error_grep="ERROR [0-9]*";
    r_http_error_sed="/ERROR/{s/.*ERROR //g;p;};";
    r_http_error_resolve="unable to resolve host address";
  elif [ "$(which "fetch")" ]; then
    b_downloader="fetch -m -o PATH URL";
    r_http_error_grep="fetch: http://[^:]*: [A-Z]";
    r_http_error_sed="s/.*://g;p;";
    r_http_error_resolve="No address record";
  else
    return 1;
  fi;
  # password hasher
  if [ "$(which "sha1sum")" ]; then
    b_hasher="sha1sum";
  elif [ "$(which "sha1")" ]; then
    b_hasher="sha1";
  else
    return 2;
  fi;
# args
  arg_tmp_password="false";
  return 0;
};

# should print message, if message_level is lesser or equal l_verbose_level
#
# args: message_level message
# output:
# side effect: prints messge to cerr
notify() {
(
  print_level="$1";
  shift;
  if [ ! "$1" ]; then
    return 1;
  fi;
  message="$@";
  verbose_level="${l_verbose_level}";
  if [ "${print_level}" = "a" ]; then
    print_level="$((${verbose_level}-1))";
  fi;
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
  password_salt="$1";
  password="$(printf "%s" "$2" | sed 's,/,\\/,g;s,&,\\&,g;')";
  printf "%s" "$(printf "%s" "${password_salt}" | sed "s/<password>/${password}/g;")" | ${b_hasher};
  return 0;
)
};

# should parse grabber arguments
#
# args:
# output:
# side effect: redefines global variables
parse_args() {
  if [ "$1" = "get_conf" ]; then
    shift;
    while [ "$1" ]; do
      case "$1" in
        ("-c"|"--config")  p_conf_file="$2"; [ "$2" ] && { shift; }; ;; 
      esac;
      shift;
    done;
    return 0;
  fi;
  shift;
  if [ ! "$1" ]; then
    set -- "--help";
  fi;
  while [ "$1" ]; do
    case "$1" in
      ("-?"|"-h"|"-help"|"--help") return 1; ;;
      ("-9") return 2; ;;
      ("-w"|"--write-config") l_write_conf="true"; ;;
      ("-d"|"--download") l_mode="download"; ;;
      ("-s"|"--search") l_action="search"; ;;
      ("-sr"|"--search-reverse") l_search_reverse_order="true"; ;;
      ("-n"|"--no-checks") l_validate_values="false"; ;;
      ("-v"|"--verbosity") l_verbose_level="$(printf "%d" "$2" 2>/dev/null)"; [ "$2" ] && { shift; } ; ;;
      ("-td"|"--tempdir") p_temp_dir="$2"; [ "$2" ] && { shift; }; ;;
      ("-dm"|"--download-mode") l_download_mode="$2"; [ "$2" ] && { shift; }; ;;
      ("-def"|"--download-export-format") s_export_format="$2"; [ "$2" ] && { shift; }; ;;
      ("-dpo"|"--download-page-offset") l_download_page_offset="$2"; [ "$2" ] && { shift; }; ;;
      ("-dps"|"--download-page-size") l_download_page_size="$2"; [ "$2" ] && { shift; }; ;;
      ("-dsd"|"--download-storage-dir") p_storage_dir="$2"; [ "$2" ] && { shift; }; ;;
      ("-dsn"|"--download-samedir") p_storage_big_dir="$2"; [ "$2" ] && { shift; }; ;;
      ("-dfn"|"--download-file-name") s_rename_string="$2"; [ "$2" ] && { shift; }; ;;
      ("-sm"|"--search-mode") l_search_mode="$2";  [ "$2" ] && { shift; }; ;;
      ("-so"|"--search-order") l_search_order="$2"; [ "$2" ] && { shift; }; ;;
      ("-u"|"--username") s_auth_login="$2"; [ "$2" ] && { shift; }; ;;
      ("-p"|"--password") tmp_password="$2"; arg_tmp_password="true"; [ "$2" ] && { shift; }; ;;
      ("-ps"|"--password-salt") s_auth_password_salt="$2"; [ "$2" ] && { shift; }; ;;
      ("-url"|"--url") p_danbooru_url="$2"; [ "$2" ] && { shift; }; ;;
      ("-fd"|"--fail-delay") l_fail_delay="$(printf "%d" "$2" 2>/dev/null)"; [ "$2" ] && { shift; }; ;;
      ("-bd"|"--binary-downloader") b_downloader="$2"; [ "$2" ] && { shift; }; ;;
      ("-bh"|"--binary-hasher") b_hasher="$2"; [ "$2" ] && { shift; }; ;;
      (*) s_tags="${s_tags} $1"; arg_s_tags="true"; ;;
    esac;
    shift;
  done;
  if [ "${arg_tmp_password}" = "true" ]; then
    s_auth_password_hash="$(password_hash "${s_auth_password_salt}" "${tmp_password}")";
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
  -c   --config                 <FILEPATH>
               Danbooru grabber configuration file.
               Default: '${p_conf_file}'
  -w   --write-config
               Write specified options to configuration file.
  -v   --verbosity
               Verbosity level. 
               Default: '${l_verbose_level}'
               0    no output.
               1    + errors and rusilts
               2    + progress display messages.
               3    + warning messages.
               4    + debug information
  -td --tempdir                 <DIRPATH>
               Directory for temp files.
               Default: '${p_temp_dir}'
  -d   --download
               Downloads images related to specified tags.
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
  -def --download-export-format <FORMAT>
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
  -dpo --download-page-offset   <1..>
               From which page begin grabbing.
               Default: '${l_download_page_offset}'
  -dps --download-page-size     <1..100>
               Amount of images per page. According to danbooru API v1.13.0 must
               be in 1.100 range, but in fact, with -n option, can be over 1000.
               Default: '${l_download_page_size}'
  -dsd --download-storage-dir   <DIRPATH>
               Directory to which all images will be saved.
               Default: '${p_storage_dir}'
  -dsn --download-samedir       <DIRPATH>
               Directory to which images will be saved if samedir download-type 
               specified.
               Default: '${p_storage_big_dir}'
  -dfn --download-file-name     <FORMAT>
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
  -sm --search-mode             <simple|deep>
               Search mechanism type.
               Default: '${l_search_mode}'
               simple      Gets a little outdated number of images, but faster.
               deep        Gets actual number of images, but slower.
  -so  --search-order           <name|count|date>
               Search sort order.
               date
               count
               name
               Default: '${l_search_order}'
  -sr  --searh-reverse
               Default: '${l_search_reverse_order}'
               Reverse search order.
  -u   --username               <USERNAME>
               Danbooru account username.
  -p   --password               <PASSWORD>
               Danbooru account password.
  -ps  --password-salt          <PASSWORD SALT>
               Actual password salt. '<password>' will be replaced with actual
               password.
               Default: '${s_auth_password_salt}'
  -url --url                    <URL>
               Danbooru URL.
               Default: '${p_danbooru_url}'
  -fd  --fail-delay             <0..>
               Delay in seconds to wait on query fail before try again.
               Default: '${l_fail_delay}'
  -bd  --binary-downloader      <EXEC PATH, OPTIONS>
               Path with options to downloader programm. 'PATH' will be replaced
               with downloading file saving point, 'URL' with target url.
               Default: '${b_downloader}'
  -bh  --binary-hasher          <EXEC PATH, OPTIONS>
               Path with options to sha1 hash generator programm.
               Default: '${b_hasher}'
  -n   --no-checks
               Do not perform any values checks before sending to server. Most
               likely useless and even dangerous, if you do not understand what
               are you doing.
               Default: '${l_validate_values}'

  Options are overriding in that order:
  Hardcoded defaults -> Default config -> -c Specified config 
  -> Command-line options

  You also may combine tags through their intersection using ' ' (space) without
  space and specify multiple tags using ',' (coma).

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
  data="659658759531120655977442455993431078871375578775867522085448698961241785898320841875684479974177979228780136958592397761257995933576702158887582133231765767340336755676885982469867634093175555587573486759624075136866683296877866340679813767558979796330697977133477982312097689987961341";
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
# 0    no output.
# 1    + errors and rusilts
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
s_auth_string='${s_auth_string}'

# Danbooru account password hash.
s_auth_password_hash='${s_auth_password_hash}'

# Actual password salt. '<password>' will be replaced with actual password.
# Default: '${s_auth_password_salt}'
s_auth_password_salt='${s_auth_password_salt}'

# Danbooru URL.
# Default: '${p_danbooru_urb_hasherl}'
p_danbooru_url='${p_danbooru_url}'

# Delay in seconds to wait on query fail before try again.
# Default: '${l_fail_delay}'
l_fail_delay='${l_fail_delay}'

# Do not perform any values checks before sending to server. Most likely useless
# and even dangerous, if you do not understand what are you doing.
# Default: 'true'
l_validate_values='true'

# Path with options to downloader programm. 'PATH' will be replaced with 
# downloading file saving point, 'URL' with target url.
# Default: '${b_downloader}'
b_downloader='${b_downloader}'

# Path with options to sha1 hash generator programm.
# Default: '${b_hasher}'
b_hasher='${b_hasher}'
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
  type="$1";
  path="$2";
  name="$3";
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
    p_conf_file="$(ask_to_make "conf" "${p_conf_file}" "configuration file")";
  fi;
(
  if [ "${l_fail_delay}" -lt 0 ]; then
    notify 1 "l_fail_delay (-fd) must not be lesser then 0.\n";
    return 1;
  fi;
  if [ "${l_verbose_level}" -lt 0 ] || [ "${l_verbose_level}" -gt 4 ]; then
    notify 1 "l_verbose_level (-v) must be in range 0..4.\n";
    return 2;
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
  if printf "%s" "${b_downloader}" | grep -vq "\(PATH\|URL\)"; then
    notify 1 "b_downloader (-bd) must containt 'PATH' and 'URL' tokens.\n";
    return 7;
  fi;
  if [ ! "${b_hasher}" ]; then
    notify 1 "b_hasher (-bh) must not be null.\n";
    return 8;
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
    ;;
    (*)
      notify 1 "l_action must be 'search' or 'download'.\n";
      return 17;
    ;;
  esac;
  IFS=",";
  for tag in ${s_tags}; do
    tagcount="$(printf "%s" "${tag}" | wc -w)";
    if [ "${tagcount}" -gt "${l_tag_limit}" ]; then
      if [ "${s_auth_string}" ]; then
        notify 1 "number of intersecting tags ('${tag}') can't be more then ${c_registred_tag_limit}for registred user.\n";
      else
        notify 1 "number of intersecting tags ('${tag}') can't be more then ${c_anonymous_tag_limit} for anonymous user. You can rise it to ${c_registred_tag_limit} by registering and specifing username (-u,s_auth_login) and password (-p,s_auth_password_hash) options.\n";
      fi;
      return 18;
    fi;
  done;
  if [ ! "${b_downloader}" ]; then
    notify 1 "Not wget not fetch binaries not found in system.\n";
    return 19;
  fi;
  if [ ! "${b_hasher}" ]; then
    notify 1 "Not sha1 not sha1sum binaries not found in system.\n";
    return 20;
  fi;
  return 0;
)
};

# should do actual downloading of API query replies and files
#
# args: type url local_filepath
# output: query_reply
# side effect: saves files
query() {
(
  type="$1";
  params="$2";
  persist="$3";
  case "${type}" in
    ("tag") url="${p_danbooru_url}/tag/index.xml?"; ;;
    ("post") url="${p_danbooru_url}/post/index.xml?"; ;;
  esac;
  temp_file="${p_temp_dir}/danbooru_grabber_query_result";
  IFS=",";
  for param in ${params}; do
    IFS=" ";
    arg="$(printf "%s" "${param}" | sed 's/=.*//g;')";
    case "${arg}" in
      ("tags"|"name")
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
  cat "${temp_file}";
  rm -f "${temp_file}";
)
};

get_file() {
(
  persist="false"; 
  if [ "$1" = "persist" ]; then
    persist="true"; 
    shift;
  fi;
  url="$1";
  local_filepath="$2";
  url_safe="$(printf "%s" "${url}" | sed 's,/,\\/,g;s,&,\\&,g;')";
  safe_filepath="$(printf "%s" "${local_filepath}" | sed 's,/,\\/,g;s,&,\\&,g;')";
  if [ -e "${local_filepath}" ]; then
    rm "${local_filepath}";
  fi;
  exec_string="$(printf "%s\n" "${b_downloader}" | sed -e "s/PATH/${safe_filepath}/g;s/URL/${url_safe}/g;")";
  lim=10;
  while [ true ]; do
    while [ true ]; do
      result="$(LANG="C" ${exec_string} 2>&1)" && { break; } || {
        if [ "${persist}" != "true" ]; then
          lim="$((${lim}-1))";
          if [ "${lim}" -le 0 ]; then
            return 1;
          fi;
        fi;
      };
      if printf "%s" "${result}" | grep -q "${r_http_error_grep}"; then
        notify 3 "HTTP ERROR $(printf "%s" "${result}" | sed -n "${r_http_error_sed}")\n";
      fi;
      if printf "%s" "${result}" | grep -q "${r_http_error_resolve}"; then
        notify 1 "unable to resolve host address '${url}'.\n";
      fi;
      sleep "${l_fail_delay}";
    done;
# tested on ~30 thousands of images without any single match, so considired as image-binary-safe.
    if grep -q "The site is down for maintenance" "${local_filepath}"; then
      notify 1 "Danbooru is currently down for maintenance.\n";
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

get_count() {
(
  if [ "$1" = "persist" ]; then
    persist="$1";
    shift;
  fi;
  tag="$1";
  tagcount="$(($(printf "%s" "${tag}" | grep -c " ")+1))";
  if [ "${tagcount}" -lt "${l_tag_limit}" ]; then
    tag="${tag} status:active";
  fi;
  result="$(query "post" "limit=1,page=1,tags=${tag}" ${persist} | sed -n '/<posts/{s/.*count="\([0-9]*\)".*/\1/p;};')";
  printf "%d" "${result}";
  return 0;
)
};

search() {
(
  tag="$1";
  result="$(query "tag" "order=${l_search_order},name=${tag}")" || { return 1; };
  if [ "$(printf "%s" "${tag}" | wc -w)" -ge 2 ]; then
    result="0 mixed ${tag}";
    l_search_mode="deep";
  else
    result="$(printf "%s\n" "${result}" | sed -n '/<tag /{s/type="0"/type="general"/g;s/type="1"/type="artist"/g;s/type="3"/type="title"/g;s/type="4"/type="character"/g;s/.*type="\([^"]*\)" count="\([0-9]*\)".*name="\([^"]*\)".*/\2 \1 \3/g;p;};')";
    if [ "${l_search_result_reverse_order}" = "true" ]; then
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

# file:count   file number
# file:id      file id
# file:height  file height
# file:width   file width
# file:tags    file tags
# file:md5     file md5 hash
download() {
(
  post_file_name="$(printf "%s" "${s_rename_string}" | sed "
    s/file:count/$(printf "%0${#total_count}d" "${count}")/g;
    s/file:id/${post_id}/g;
    s/file:height/${post_height}/g;
    s/file:width/${post_width}/g;
    s/file:tags/${post_tags}/g;
    s/file:md5/${post_md5}/g;
    s/[[:space:]]*&[#0-9a-zA-Z]*[[:space:]]*;//g;
    s/^\(.\{0,$((254-${#post_file_ext}))\}\).*/\1/g;
  ").${post_file_ext}";
  case "${l_download_mode}" in
    ("onedir"|"onedir:symlinks") file_path="${p_storage_dir}/${safe_tag}/${post_file_name}"; ;;
    ("samedir"|"samedir:symlinks") file_path="${p_storage_big_dir}/${post_file_name}"; ;;
  esac;
  if [ -e "${file_path}" ]; then
    notify 2 "skip: ${file_path}\n";
    return 0;
  fi;
  post_file_url="$(printf "%s" "${post_file_url}" | sed 's|\\/|\/|g')";
  tmpfile="${p_temp_dir}/danbooru_grabber_temp_content_file";
  notify 2 "begin: ${file_path}\n";
  get_file "${post_file_url}" "${tmpfile}";
  case "${l_download_mode}" in
    ("onedir")
      if [ ! -d "${p_storage_dir}/${safe_tag}" ]; then
        mkdir "${p_storage_dir}/${safe_tag}";
      fi;
      mv "${tmpfile}" "${file_path}";
      touch -acm -t "$(dateformat "${post_created_at}")" "${file_path}";
    ;;
    ("samedir")
      if [ ! -d "${p_storage_dir}/${safe_tag}" ]; then
        mkdir "${p_storage_dir}/${safe_tag}";
      fi;
      mv "${tmpfile}" "${file_path}";
      touch -acm -t "$(dateformat "${post_created_at}")" "${file_path}";
    ;;
    ("onedir:symlinks"|"samedir:symlinks")
      if [ ! -d "${p_storage_dir}/${safe_tag}" ]; then
        mkdir "${p_storage_dir}/${safe_tag}";
      fi;
      mv "${tmpfile}" "${file_path}";
      touch -acm -t "$(dateformat "${post_created_at}")" "${file_path}";
      IFS="-";
      for i_tag in ${post_tags}; do
        if [ "${i_tag}" = "${safe_tag}" ]; then
          continue;
        fi;
        if [ ! -d "${p_storage_dir}/${i_tag}" ]; then
          mkdir "${p_storage_dir}/${i_tag}";
        fi;
        ln -s "${file_path}" "${p_storage_dir}/${i_tag}/";
        touch -acm -t "$(dateformat "${post_created_at}")" "${p_storage_dir}/${i_tag}/${post_file_name}";
      done;
    ;;
  esac;
  notify 2 " end: ${file_path}\n";
  return 0;
)
};

export_out() {
(
  string="$(printf "%s" "${s_export_format}" | sed "
    s/file:url/${post_file_url}/g;
    s/file:preview_url/${post_preview_url}/g;
    s/file:sample_url/${post_sample_url}/g;
    s/file:tags/${post_tags}/g;
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


parser() {
(
  tag="$1";
  total_count="$(get_count "persist" "${tag}")";
  if [ "${total_count}" -eq 0 ]; then
    notify 1 "there is no tag '${tag}'.\n";
    return 1;
  fi;
  total_pages="$((${total_count}/${l_download_page_size}))";
  if [ "$((${total_count}%${l_download_page_size}))" -gt 0 ]; then
    total_pages="$((${total_pages}+1))";
  fi;
  page="${l_download_page_offset}";
  while [ "${page}" -le "${total_pages}" ]; do
    count="$((${page}*${l_download_page_size}-${l_download_page_size}+1))";
    result="$(query "post" "limit=${l_download_page_size},page=${page},tags=${tag}" "persist" | sed -n '/<post /{p;};')";
    printf "%s\n" "${result}" | while read -r post; do
      printf -- "$(printf "%s" "${post}" | sed 's/[^"]*"\([^"]*\)"/\1\\n/g;s/\/>//g;s/&/\\&/g;s|/|\\\\/|g;')" | (
        vars="post_score post_preview_width post_tags post_created_at post_height\
              post_md5 post_file_url post_preview_url post_preview_height\
              post_creator_id post_sample_url post_sample_width post_status\
              post_sample_height post_rating post_hash_children post_parent_id\
              post_id post_change post_source post_width";
        IFS=" ";
        for var in $vars; do
          read -r "$var";
        done;
        post_tags="$(printf "%s" "${post_tags}" | sed 's,[/],,g;s/&/\\&/g;s/[[:space:]]\{1,\}/-/g;')";
        safe_tag="$(printf "%s" "${tag}" | sed 's,[/],,g;s/&/\\&/g;s/[[:space:]]\{1,\}/-/g;')";
        post_file_ext="$(printf "%s" "${post_file_url}" | sed 's/.*\.//g')";
        case "${l_download_mode}" in
          ("export") export_out; ;;
          (*) download; ;;
        esac;
      );
      count="$((${count}+1))";
    done;
    page="$((${page}+1))";
  done;
  return 0;
)
};

catch_error() {
(
  notify 4 "$(printf "INTERNAL ERROR %d%02d" "$1" "$?")\n";
  return 0;
)
};


main() {
  set +x;
  init || { return 1$?; };
  read_conf;
  parse_args "get_conf" "$@";
  read_conf;
  parse_args "all" "$@";
(
  case "$?" in
    (0) ;;
    (1) help; return 0; ;;
    (2) help_atai; return 0; ;;
    (*) catch_error 1; return "1$?";
  esac;
  if [ "${l_validate_values}" = "true" ]; then
    validate_values || { catch_error 2; return "2$?"; };
  fi;
  if [ "${l_write_conf}" = "true" ]; then
    write_conf "${p_conf_file}";
  fi;
  IFS=",";
  for tag in ${s_tags}; do
    tag="$(printf "%s" "${tag}" | sed 's/^[[:space:]]*//g;s/[[:space:]]*$//g;')"
    case "${l_mode}" in
      ("search") search "${tag}"; ;;
      ("download") parser "${tag}"; ;;
    esac;
  done;
  return 0;
)
};

main "$@" && { exit 0; } || { exit "$?"; }
