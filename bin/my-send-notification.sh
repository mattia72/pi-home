#!/bin/bash
#set -x

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
prevent_notification_file_name="PREVENT_NOTIFICATION"
ifttt_key_file_name="IFTTT_SECRET_KEY"
min_time_between_notifications=120
force_sending=0
log_file="${0}.log"

log_level=-1 # no log, 1:error, 2:warning, 3:info

usage()
{
  cat <<END_USAGE
  Usage: ${0##*/} [-h] -e <event> [-f] [-i <file>] [-n <num>] [-l <file>] [-v <num>]

  Sends POST web request to
  https://maker.ifttt.com/trigger/<event>/with/key/<key>

  Options:
       -h         Display this help and exit
       -f         Force sending notification
       -e <event> Notification event name
       -i <file>  This file in script directory contains IFTTT key for notifications. Default: $ifttt_key_file_name
       -l <file>  Log file. Default $log_file
       -v <num>   Log level (0: no log; 1: error; 2: warning; 3: info)
       -n <num>   Time between notifications should be minimum <num> minutes. Default: $min_time_between_notifications

END_USAGE
}

log_to_file()
{
  local level="$1"
  local message="$2"

  [ $log_level -ge $level ] && echo -e "`date`: $message" >> $log_file
}

log_to_screen()
{
  local message="$1"
  local level=3 #info
  if [ $# -gt 1 ]; then
    level="$1"
    message="$2"
  fi

  [ $log_level -ge $level ] && echo -e "$message" 
  log_to_file $level "$message"
}

notify()
{
  local event="$1"
  local par1="${2:-}"
  local par2="${3:-}"
  local par3="${4:-}"
  if (( notification_preventer_file_exists !=1 )) ; then
    log_to_screen "Sending $event notification..."
    params="{\"value1\":\"$par1\",\"value2\":\"$par2\",\"value3\":\"$par3\"}" 
    if [ -n "$par1" -o -n "$par2" -o -n "$par3" ]; then
      log_to_screen 3 "Parameters: $params"
    fi
    curl -s -X POST -H "Content-Type: application/json" -d "$params" \
    "https://maker.ifttt.com/trigger/$event/with/key/$ifttt_key" 2> >(tee -a $log_file)
    CURL_RETURN_CODE=$?
    echo
    if [ $CURL_RETURN_CODE -ne 0 ]; then
      error_msg="Running curl failed with return code - ${CURL_RETURN_CODE}"
      log_to_screen 1 "$error_msg\n"
    else
      log_to_screen 3 "Sending $event notification succeeded."
    fi
    if [ $force_sending -ne 1 ]; then
      touch "$script_dir/$prevent_notification_file_name"
    fi
  else
      log_to_screen 3 "Notification sending prevented by file."
  fi
}

OPTIND=1 
while getopts ":e:1:2:3:hfl:v:n:i:" opt; do
  #echo opt:$opt $OPTARG
  case "$opt" in
    e) event=$OPTARG ;; 
    1) p1=$OPTARG ;; 
    2) p2=$OPTARG ;; 
    3) p3=$OPTARG ;; 
    f) force_sending=1 ;;
    h) usage; exit 0 ;;
    i) ifttt_key_file_name=$OPTARG ;; 
    v) log_level=$OPTARG ;; 
    l) log_file=$OPTARG ;; 
    n) min_time_between_notifications=$OPTARG ;; 
    \?) log_to_screen 1 "Unknown option: -$OPTARG" >&2; exit 1;;
    :) log_to_screen 1 "Missing option argument for -$OPTARG" >&2; exit 1;;
    *) log_to_screen 1 "Unimplemented option: -$OPTARG" >&2; exit 1;;
  esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.
if [ -z $event ]; then
  log_to_screen 1 "Option -e <event> is mandatory." >&2 
  exit 1; 
fi

if [ -e "$script_dir/$ifttt_key_file_name" ]; then
  ifttt_key=$(cat "$script_dir/$ifttt_key_file_name")
else
  log_to_screen 1 "$ifttt_key_file_name not exists." >&2 
  exit 1; 
fi

[ -z "$(find "$script_dir" -mmin "-$min_time_between_notifications" -name "$prevent_notification_file_name")" ]
notification_preventer_file_exists=$?

if [ $force_sending -eq 1 ]; then
  notification_preventer_file_exists=0
  log_to_screen 3 "Force sending $event notification."
fi

notify "$event" "$p1" "$p2" "$p3"

