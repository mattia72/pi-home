#!/bin/bash
#set -x

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
auth=user:password
movedir=""
remove_completed=0
shutdown_if_no_active_torrent=0
shutdown_before=""
log_level=0 # no log
max_seed_hours=52 #48 + 10%
max_seed_ratio=10 # not reliable enough so keep it high!
log_file=${0}.log
prevent_shutdown_file_name="PREVENT_SHUTDOWN"
ifttt_key_file_name="IFTTT_SECRET_KEY"
min_time_between_notifications=120

usage()
{
  cat <<END_USAGE
  Usage:

  ${0##*/}  
  [-h] -a <un:pw> [-r <num>] [-d [-b <hhmm>]] [-s <num>] [-m <dir>] 
  [-l <num>] [-i <file>] [-n <num>] [-l <file>] [-v <num>]

  Without any option, it prints the status of the active torrents.

  Options:
       -h         Display this help and exit
       -a <un:pw> Authentication <user:password>
       -t <num>   Max seeding hours. Default: $max_seed_hours
       -r <num>   Max seeding ratio. Default: $max_seed_ratio
       -d         Delete completed torrents from the list.
                  (completed: Stopped or Finished and seeding ratio or time reached)
       -s         Shutdown if there is no active torrent. 
                  Shutdown can be prevented by creating a file, named $prevent_shutdown_file_name.
                  It will prevent the shutdown on the day of creation.
       -b <hhmm>  Shutdown only before specified time. Format: hhmm, eg: `date +"%H%M"`
       -m <dir>   Move completed torrents to the specified directory
       -i <file>  This file in script directory contains IFTTT key for notifications. Default: $ifttt_key_file_name
       -n <num>   Time between notifications should be minimum <num> minutes. Default: $min_time_between_notifications
       -l <file>  Log file
       -v <num>   Log level (0: no log; 1: log on remove and shutdown; 2: all)

END_USAGE
}

source "${0%/*}/my-logger.lib.sh"

force_notify()
{
  local event="$1"
  local par1="${2:-}"
  local par2="${3:-}"
  local par3="${4:-}"

  bash $script_dir/my-send-notification.sh -e "$event" \
  -1 "$par1" -2 "$par2" -3 "$par3" \
  -i "$ifttt_key_file_name" \
  -l "$log_file" -v "$log_level" -n "$min_time_between_notifications"
}

notify()
{
  local event="$1"
  local par1="${2:-}"
  local par2="${3:-}"
  local par3="${4:-}"

  bash $script_dir/my-send-notification.sh -e "$event" \
  -1 "$par1" -2 "$par2" -3 "$par3" \
  -i "$ifttt_key_file_name" \
  -l "$log_file" -v "$log_level" -n "$min_time_between_notifications"
}

OPTIND=1 
while getopts ":a:ht:sr:db:l:v:m:n:i:" opt; do
  #echo opt:$opt $OPTARG
  case "$opt" in
    a) auth=$OPTARG ;;
    b) shutdown_before=$OPTARG ;;
    d) remove_completed=1 ;;
    i) ifttt_key_file_name=$OPTARG ;; 
    l) log_file=$OPTARG ;; 
    m) movedir=$OPTARG ;; 
    n) min_time_between_notifications=$OPTARG ;; 
    r) max_seed_ratio=$OPTARG ;;
    s) shutdown_if_no_active_torrent=1 ;;
    t) max_seed_hours=$OPTARG ;;
    v) log_level=$OPTARG ;; 
    h) usage; exit 0 ;;
    ?) echo -e "Error: invalid option - $OPTARG";exit 1 ;;
  esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.

if [ "$auth" = 'user:password' ]; then
  log_to_screen 1 "Option -a <user:password> is mandatory." >&2 
  exit 1; 
fi

log_to_screen 3 "auth                           : $auth"
log_to_screen 3 "max_seed_hours                 : $max_seed_hours"
log_to_screen 3 "max_seed_ratio                 : $max_seed_ratio"
log_to_screen 3 "remove_completed               : $remove_completed"
log_to_screen 3 "shutdown_if_no_active_torrent  : $shutdown_if_no_active_torrent"
log_to_screen 3 "shutdown_before                : $shutdown_before"
log_to_screen 3 "log_level                      : $log_level"
log_to_screen 3 "movedir                        : $movedir"

set -u

source "${0%/*}/my-calculator.lib.sh"

BASE_COMMAND="transmission-remote -n $auth"
TORRENT_ID_LIST=$($BASE_COMMAND -l | sed -e '1d;$d;s/^ *\([0-9]\+\).*$/\1/')

notify_entry=""
for TORRENT_ID in $TORRENT_ID_LIST
do
  CMD_OUT=$($BASE_COMMAND -t $TORRENT_ID -i)
  
  NAME=$(echo -e "$CMD_OUT" | grep -i "Name:" | sed 's/^ *//' | cut -d ' ' -f 2-)
  PERCENT=$(echo -e "$CMD_OUT" | grep -i "Percent Done:" | sed 's/^ *//' | cut -d ' ' -f 3)
  STATE=$(echo -e "$CMD_OUT" | grep -i "State:" | sed 's/^ *//' | cut -d ' ' -f 2)
  RATIO=$(echo -e "$CMD_OUT" | grep -i "Ratio:" | sed 's/^ *//' | cut -d ' ' -f 2)

  SEEDING_TIME_DAYS=$(echo -e "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\([0-9]\+\) day.\?.*$/\1/p' )
  SEEDING_TIME_HOURS=$(echo -e "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\(.*, \)\?\([0-9]\+\) hour.\?.*$/\2/p' )

  TOTAL_SIZE=$(echo -e "$CMD_OUT" | sed -n '/Total size/s/^.*: *\([0-9.]\+ [a-zA-Z]\+\) .*$/\1/p' ) 
  UPLOADED=$(echo -e "$CMD_OUT" | sed -n '/Uploaded:/s/^.*: *\([0-9.]\+ [a-zA-Z]\+\).*$/\1/p' ) 
  [ -z "$UPLOADED" ] && UPLOADED="0.00 MB"

  [ -z "$SEEDING_TIME_DAYS" ] &&  SEEDING_TIME_DAYS=0 
  [ -z "$SEEDING_TIME_HOURS" ] &&  SEEDING_TIME_HOURS=0 
  SEEDING_DAYS_IN_HOURS=$(( 24*SEEDING_TIME_DAYS ))
  all_seed_time=$(( SEEDING_DAYS_IN_HOURS + SEEDING_TIME_HOURS ))

  #echo u:$UPLOADED/$TOTAL_SIZE
  Human2Byte "$UPLOADED" up_bytes
  Human2Byte "$TOTAL_SIZE" total_bytes

  BcCalc "${up_bytes%*B} > ${total_bytes%*B}*${max_seed_ratio}" seeding_ratio_reached

  #Hátravan=(1-arány)*(48+0.4*letöltött adatmennyiség)-seedben töltött idő
  exp="(1-${RATIO})*($max_seed_hours + 0.4*(${total_bytes%*B}/(1024^3)))-${all_seed_time}" 
#  echo "$exp"
  BcCalc "$exp" required_seed_time
  exp="define min(x,y){if(x<y){return(x)};return(y)} min($required_seed_time, $max_seed_hours)" 
#  echo "$exp"
  BcCalc "$exp" required_seed_time
  BcCalc "($all_seed_time > ${max_seed_hours}) || ($required_seed_time < 0)" seeding_time_reached

  log_entry="Id:$TORRENT_ID - '$STATE'\tUp/Total: $UPLOADED/$TOTAL_SIZE\tRatio: $RATIO"
  (( seeding_ratio_reached )) && log_entry="$log_entry (max reached)"
  #log_entry="${log_entry}\tSeedTime: ${SEEDING_TIME_DAYS}d+${SEEDING_TIME_HOURS}h=${all_seed_time}h"
  log_entry="${log_entry}\tSeedTime: ${all_seed_time}h"
  log_entry="${log_entry}\tRest: ${required_seed_time}h"
  (( seeding_time_reached )) && log_entry="$log_entry (max reached)"
  log_entry="${log_entry}\t$NAME"

  log_to_screen "$log_entry"
  notify_entry="$notify_entry\n$log_entry"
  completed=0
  if [[ "$PERCENT" = "100%" && ( "$STATE" = "Stopped" || "$STATE" = "Finished" ) && ( $seeding_time_reached == 1 || $seeding_ratio_reached == 1 ) ]]; then
    log_to_screen "Torrent #$TORRENT_ID is completed."
    if [ -n "$movedir" ]; then
      log_to_screen "Moving downloaded file(s) to $movedir."
      transmission-remote -n $auth -torrent $TORRENT_ID -move $movedir
      log_to_file 1 "$log_entry moved to $movedir"
    fi
    if (( remove_completed )); then
      log_to_screen 1 "Removing torrent from list."
      transmission-remote -n $auth --torrent $TORRENT_ID --remove
      log_to_file 1 "$log_entry removed"
    fi
    completed=1
  else
    log_to_screen "Torrent #$TORRENT_ID is NOT completed."
    completed=0
  fi

  log_level_tmp=$log_level
  if (( completed && remove_completed )); then log_level=3; fi
  log_to_screen 3 "completed: $completed"
  log_to_screen 3 "Percent: $PERCENT"
  log_to_screen 3 "SeedingTimeReached?: $seeding_time_reached"
  log_to_screen 3 "SeedingRatioReached?: $seeding_ratio_reached"
  if (( completed && remove_completed )); then log_level=$log_level_tmp; fi
done


#[ ! -e "$script_dir/$prevent_shutdown_file_name" ] 
#shutdown_preventer_file_exists=$?
#echo "P1:$shutdown_preventer_file_exists"
[ -z "$(find "$script_dir" -mtime -1 -name "$prevent_shutdown_file_name")" ]
shutdown_preventer_file_exists=$?
#echo "P2:$shutdown_preventer_file_exists"

if [[ $shutdown_before == "" ]]; then
  before_time_limit_ok=1
else
  current_time=`date +"%H%M"`
  #current_time_cut=${current_time##+([0 ])} # doesn't work :(
  current_time_cut=$(echo $current_time | sed 's/^\s*0*//')
  shutdown_before_cut=$(echo $shutdown_before | sed 's/^\s*0*//') 
  before_time_limit_ok=$(( current_time_cut < shutdown_before_cut ))
  log_to_file 2 "time: $current_time_cut limit: $shutdown_before_cut ok: $before_time_limit_ok"
fi

TORRENT_ID_LIST=$($BASE_COMMAND -l | sed -e '1d;$d;s/^ *\([0-9]\+\).*$/\1/')
if [ -z "$TORRENT_ID_LIST" ]; then
  log_to_screen "No active torrent found."
  #send notifictaion to my phone
  force_notify "no_active_torrent"
  echo

  log_to_file 2 "Shutdown?: $shutdown_if_no_active_torrent Time limit not reached?: $before_time_limit_ok Avoid file exists?: $shutdown_preventer_file_exists"


  if (( shutdown_if_no_active_torrent == 1 )); then

    (( shutdown_preventer_file_exists == 1 )) && log_to_screen "Shutdown canceled by file: `dirname "$0"`/$prevent_shutdown_file_name"  
    (( before_time_limit_ok == 0 )) && log_to_screen "Shutdown canceled by time limit."

    if (( before_time_limit_ok == 1 && shutdown_preventer_file_exists != 1 )); then
     log_to_file 1 "Shutdown initiated."
     #shutdown in a minute
     force_notify "raspi_shutdown_started"
     sudo shutdown 1 "Shutdown initiated by $script_name. You can prevent it by: 'shutdown -c; touch $current_dir/$prevent_shutdown_file_name'" >> $log_file 2>&1 
    fi
  fi
else
  notify "get_torrent_info" "$notify_entry"
  echo
fi

