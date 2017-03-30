#!/bin/bash
#set -x

auth=transmission:transmission
movedir=""
remove_completed=0
shutdown_if_no_active_torrent=0
log_level=0 # no log
max_seed_hours=48
max_seed_ratio='1.0'
log_file=${0}.log

OPTIND=1 
while getopts ":a:ht:s:rdl:m:" opt; do
  case "$opt" in
    a) auth=$OPTARG ;;
    t) max_seed_hours=$OPTARG ;;
    s) max_seed_ratio=$OPTARG ;;
    r) remove_completed=1 ;;
    d) shutdown_if_no_active_torrent=1 ;;
    l) log_level=$OPTARG ;; 
    m) movedir=$OPTARG ;; 
    h) echo "Usage: ${0##*/} [-h] -a <un:pw> [-r] [-d] [-s <num>] [-m <dir>] [-l <num>]" 
  echo  
  echo "Without any option, it prints the status of the active torrents." 
  echo  
  echo "Options:" 
  echo "     -h         Help" 
  echo "     -a <un:pw> Authentication <user:password>" 
  echo "     -t <num>   Max seeding hours" 
  echo "     -s <num>   Max seeding ratio" 
  echo "     -r         Remove completed torrents."
  echo "                (State: Stopped, Finished or seeding ratio or time reached)" 
  echo "     -d         Shutdown if there is no active torrent" 
  echo "     -m <dir>   Move completed torrents to the specified directory" 
  echo "     -l <num>   Log level (0: no log; 1: log on remove, shutdown; 2: all)"
  echo  
  exit ;;
    *) break ;;
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
  
  NAME=$(echo "$CMD_OUT" | grep -i "Name:" | sed 's/^ *//' | cut -d ' ' -f 2-)
  PERCENT=$(echo "$CMD_OUT" | grep -i "Percent Done:" | sed 's/^ *//' | cut -d ' ' -f 3)
  STATE=$(echo "$CMD_OUT" | grep -i "State:" | sed 's/^ *//' | cut -d ' ' -f 2)
  RATIO=$(echo "$CMD_OUT" | grep -i "Ratio:" | sed 's/^ *//' | cut -d ' ' -f 2)
  SEEDING_TIME_DAYS=$(echo "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\([0-9]\+\) day.\?, .*$/\1/p' )
  SEEDING_TIME_HOURS=$(echo "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:.*\([0-9]\+\) hour.\? .*$/\1/p' )
  TOTAL_SIZE=$(echo "$CMD_OUT" | sed -n '/Total size/s/^.*: *\([0-9.]\+ [a-zA-Z]\+\) .*$/\1/p' ) 
  UPLOADED=$(echo "$CMD_OUT" | sed -n '/Uploaded:/s/^.*: *\([0-9.]\+ [a-zA-Z]\+\).*$/\1/p' ) 
  [ "$UPLOADED" = "None" ] && UPLOADED="0.00 MB"

  SEEDING_DAYS_IN_HOURS=0
  [ -z "$SEEDING_TIME_DAYS" ] || SEEDING_DAYS_IN_HOURS=$(( 24*SEEDING_TIME_DAYS ))
  time=$(( SEEDING_DAYS_IN_HOURS + SEEDING_TIME_HOURS ))

  Human2Byte "$UPLOADED" up_bytes
  Human2Byte "$TOTAL_SIZE" total_bytes

  BcCalc "$time > ${max_seed_hours}" seeding_time_reached
  BcCalc "${up_bytes%*B} > ${total_bytes%*B}*${max_seed_ratio}" seeding_ratio_reached

  log_entry="$TORRENT_ID - $STATE\tUp/Total: $UPLOADED/$TOTAL_SIZE\tRatio: $RATIO"
  (( seeding_ratio_reached )) && log_entry="$log_entry (max reached)"
  log_entry="${log_entry}\tSeedTime: ${time}h"
  (( seeding_time_reached )) && log_entry="$log_entry (max reached)"
  log_entry="${log_entry}\t$NAME"

  echo -e "$log_entry"

  if [[ "$PERCENT" = "100%" && ( "$STATE" = "Stopped" || "$STATE" = "Finished" || $seeding_time_reached == 1 || $seeding_ratio_reached == 1 ) ]]; then
  echo "Torrent #$TORRENT_ID is completed."
  if [ -n "$movedir" ]; then
    echo "Moving downloaded file(s) to $movedir."
    [ $log_level -ge 1 ] && echo "`date`: $log_entry moved to $movedir" >> $log_file
    transmission-remote -n $auth -torrent $TORRENT_ID -move $movedir
  fi
  if [ $remove_completed -eq 1 ]; then
    echo "Removing torrent from list."
    transmission-remote -n $auth --torrent $TORRENT_ID --remove
    [ $log_level -ge 1 ] && echo "`date`: $log_entry removed" >> $log_file
  fi
  else
    [ $log_level -ge 2 ] && echo "`date`: $log_entry not completed" >> $log_file
  fi
done


TORRENT_ID_LIST=$($BASE_COMMAND -l | sed -e '1d;$d;s/^ *\([0-9]\+\).*$/\1/')
if [ -z "$TORRENT_ID_LIST" ]; then
  echo "No active torrent found."
  [ $log_level -ge 2 ] && echo "`date`: No active torrent found" >> $log_file
  if (( shutdown_if_no_active_torrent )); then
     [ $log_level -ge 1 ] && echo "`date`: Shutdown initiated." >> $log_file
     shutdown -h now &
  fi
fi

