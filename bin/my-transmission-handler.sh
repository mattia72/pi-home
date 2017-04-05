#!/bin/bash
#set -x

auth=transmission:transmission
movedir=""
remove_completed=0
shutdown_if_no_active_torrent=0
shutdown_before=""
log_level=-1 # no log
max_seed_hours=48
max_seed_ratio='1.0'
log_file=${0}.log

usage()
{
  echo -e "Usage: ${0##*/} [-h] -a <un:pw> [-r] [-d [-b <hhmm>]] [-s <num>] [-m <dir>] [-l <num>]" 
  echo  
  echo -e "Without any option, it prints the status of the active torrents." 
  echo  
  echo -e "Options:" 
  echo -e "     -h         Help" 
  echo -e "     -a <un:pw> Authentication <user:password>" 
  echo -e "     -t <num>   Max seeding hours. Default: $max_seed_hours" 
  echo -e "     -s <num>   Max seeding ratio. Default: $max_seed_ratio" 
  echo -e "     -r         Remove completed torrents."
  echo -e "                (State: Stopped or Finished or seeding ratio or time reached)" 
  echo -e "     -d         Shutdown if there is no active torrent" 
  echo -e "     -b <hhmm>  Shutdown only before specified time. Format: hhmm, eg: `date +"%H%M"`" 
  echo -e "     -m <dir>   Move completed torrents to the specified directory" 
  echo -e "     -l <num>   Log level (0: no log; 1: log on remove and shutdown; 2: all)"
  echo  
}

log_to_file()
{
  local level="$1"
  local message="$2"

  [ $log_level -ge $level ] && echo -e "`date`: $message" >> $log_file
}

log_everywhere()
{
  local message="$1"

  echo -e "$message" 
  log_to_file 2 "$message"
}

OPTIND=1 
while getopts ":a:ht:s:rdb:l:m:" opt; do
  #echo opt:$opt $OPTARG
  case "$opt" in
    a) auth=$OPTARG ;;
    t) max_seed_hours=$OPTARG ;;
    s) max_seed_ratio=$OPTARG ;;
    r) remove_completed=1 ;;
    d) shutdown_if_no_active_torrent=1 ;;
    b) shutdown_before=$OPTARG ;;
    l) log_level=$OPTARG ;; 
    m) movedir=$OPTARG ;; 
    h) usage; exit 0 ;;
    ?) echo -e "Error: invalid option - $OPTARG";exit 1 ;;
  esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.

set -u

source "${0%/*}/my-calculator.lib.sh"

BASE_COMMAND="transmission-remote -n $auth"
TORRENT_ID_LIST=$($BASE_COMMAND -l | sed -e '1d;$d;s/^ *\([0-9]\+\).*$/\1/')

for TORRENT_ID in $TORRENT_ID_LIST
do
  CMD_OUT=$($BASE_COMMAND -t $TORRENT_ID -i)
  
  NAME=$(echo -e "$CMD_OUT" | grep -i "Name:" | sed 's/^ *//' | cut -d ' ' -f 2-)
  PERCENT=$(echo -e "$CMD_OUT" | grep -i "Percent Done:" | sed 's/^ *//' | cut -d ' ' -f 3)
  STATE=$(echo -e "$CMD_OUT" | grep -i "State:" | sed 's/^ *//' | cut -d ' ' -f 2)
  RATIO=$(echo -e "$CMD_OUT" | grep -i "Ratio:" | sed 's/^ *//' | cut -d ' ' -f 2)

  SEEDING_TIME_DAYS=$(echo -e "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\([0-9]\+\) day.\? .*$/\1/p' )
  SEEDING_TIME_HOURS=$(echo -e "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\([0-9]\+\) hour.\? .*$/\1/p' )

  TOTAL_SIZE=$(echo -e "$CMD_OUT" | sed -n '/Total size/s/^.*: *\([0-9.]\+ [a-zA-Z]\+\) .*$/\1/p' ) 
  UPLOADED=$(echo -e "$CMD_OUT" | sed -n '/Uploaded:/s/^.*: *\([0-9.]\+ [a-zA-Z]\+\).*$/\1/p' ) 
  [ -z "$UPLOADED" ] && UPLOADED="0.00 MB"

  [ -z "$SEEDING_TIME_DAYS" ] &&  SEEDING_TIME_DAYS=0 
  [ -z "$SEEDING_TIME_HOURS" ] &&  SEEDING_TIME_HOURS=0 
  SEEDING_DAYS_IN_HOURS=$(( 24*SEEDING_TIME_DAYS ))
  time=$(( SEEDING_DAYS_IN_HOURS + SEEDING_TIME_HOURS ))

  #echo u:$UPLOADED/$TOTAL_SIZE
  Human2Byte "$UPLOADED" up_bytes
  Human2Byte "$TOTAL_SIZE" total_bytes

  BcCalc "$time > ${max_seed_hours}" seeding_time_reached
  BcCalc "${up_bytes%*B} > ${total_bytes%*B}*${max_seed_ratio}" seeding_ratio_reached

  log_entry="$TORRENT_ID - $STATE\tUp/Total: $UPLOADED/$TOTAL_SIZE\tRatio: $RATIO"
  (( seeding_ratio_reached )) && log_entry="$log_entry (max reached)"
  log_entry="${log_entry}\tSeedTime: ${SEEDING_TIME_DAYS}d+${SEEDING_TIME_HOURS}h=${time}h"
  (( seeding_time_reached )) && log_entry="$log_entry (max reached)"
  log_entry="${log_entry}\t$NAME"

  log_everywhere "$log_entry"

  if [[ "$PERCENT" = "100%" && ( "$STATE" = "Stopped" || "$STATE" = "Finished" || $seeding_time_reached == 1 || $seeding_ratio_reached == 1 ) ]]; then
    log_everywhere "Torrent #$TORRENT_ID is completed."
    if [ -n "$movedir" ]; then
      log_everywhere "Moving downloaded file(s) to $movedir."
      transmission-remote -n $auth -torrent $TORRENT_ID -move $movedir
      log_to_file 1 "$log_entry moved to $movedir"
    fi
    if [ $remove_completed -eq 1 ]; then
      log_everywhere "Removing torrent from list."
      transmission-remote -n $auth --torrent $TORRENT_ID --remove
      log_to_file 1 "$log_entry removed"
    fi
  else
    log_everywhere "Torrent #$TORRENT_ID is NOT completed."
  fi
done


if [[ $shutdown_before == "" ]]; then
  shutdown_before_ok=1
else
  current_time=`date +"%H%M"`
  current_time=${current_time##*0}
  shutdown_before=${shutdown_before##*0}
  shutdown_before_ok=$(( current_time < shutdown_before ))
fi

TORRENT_ID_LIST=$($BASE_COMMAND -l | sed -e '1d;$d;s/^ *\([0-9]\+\).*$/\1/')
if [ -z "$TORRENT_ID_LIST" ]; then
  log_everywhere "No active torrent found."
  if [[ $shutdown_if_no_active_torrent == 1 && $shutdown_before_ok == 1 ]]; then
     log_to_file 1 "Shutdown initiated."
     shutdown -h -t 60 "Shutdown initiated by ${0##*/}. Type 'sudo shutdown -c' to cancel it!" &
  fi
fi

