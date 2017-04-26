#!/bin/bash
#set -x

auth=transmission:transmission
movedir=""
remove_completed=0
shutdown_if_no_active_torrent=0
shutdown_before=""
log_level=0 # no log
max_seed_hours=48
max_seed_ratio='1.0'
log_file=${0}.log
prevent_shutdown_file_name="PREVENT_SHUTDOWN"

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
  echo -e "     -r <num>   Max seeding ratio. Default: $max_seed_ratio" 
  echo -e "     -d         Delete completed torrents from the list."
  echo -e "                (completed: Stopped or Finished or seeding ratio or time reached)" 
  echo -e "     -s         Shutdown if there is no active torrent. " 
  echo -e "                Shutdown can be prevented by creating a file, named $prevent_shutdown_file_name." 
  echo -e "                It will prevent the shutdown on the day of creation." 
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

log_to_screen()
{
  local message="$1"

  echo -e "$message" 
  log_to_file 2 "$message"
}

OPTIND=1 
while getopts ":a:ht:sr:db:l:m:" opt; do
  #echo opt:$opt $OPTARG
  case "$opt" in
    a) auth=$OPTARG ;;
    t) max_seed_hours=$OPTARG ;;
    r) max_seed_ratio=$OPTARG ;;
    d) remove_completed=1 ;;
    s) shutdown_if_no_active_torrent=1 ;;
    b) shutdown_before=$OPTARG ;;
    l) log_level=$OPTARG ;; 
    m) movedir=$OPTARG ;; 
    h) usage; exit 0 ;;
    ?) echo -e "Error: invalid option - $OPTARG";exit 1 ;;
  esac
done
shift "$((OPTIND-1))" # Shift off the options and optional --.

#echo  "auth                            $auth"
#echo  "max_seed_hours                  $max_seed_hours"
#echo  "max_seed_ratio                  $max_seed_ratio"
#echo  "remove_completed                $remove_completed"
#echo  "shutdown_if_no_active_torrent   $shutdown_if_no_active_torrent"
#echo  "shutdown_before                 $shutdown_before"
#echo  "log_level                       $log_level"
#echo  "movedir                         $movedir"

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

  SEEDING_TIME_DAYS=$(echo -e "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\([0-9]\+\) day.\?.*$/\1/p' )
  SEEDING_TIME_HOURS=$(echo -e "$CMD_OUT" |  sed -n '/Seeding Time/s/^.\+\?:[ \t]*\([0-9]\+\) hour.\?.*$/\1/p' )

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
  #log_entry="${log_entry}\tSeedTime: ${SEEDING_TIME_DAYS}d+${SEEDING_TIME_HOURS}h=${time}h"
  log_entry="${log_entry}\tSeedTime: ${time}h"
  (( seeding_time_reached )) && log_entry="$log_entry (max reached)"
  log_entry="${log_entry}\t$NAME"

  log_to_screen "$log_entry"

  #if [[ "$PERCENT" = "100%" && ( "$STATE" = "Stopped" || "$STATE" = "Finished" || $seeding_time_reached == 1 || $seeding_ratio_reached == 1 ) ]]; then
  if [[ "$PERCENT" = "100%" && ( "$STATE" = "Stopped" || "$STATE" = "Finished" ) && ( $seeding_time_reached == 1 || $seeding_ratio_reached == 1 ) ]]; then
    log_to_screen "Torrent #$TORRENT_ID is completed."
    if [ -n "$movedir" ]; then
      log_to_screen "Moving downloaded file(s) to $movedir."
      transmission-remote -n $auth -torrent $TORRENT_ID -move $movedir
      log_to_file 1 "$log_entry moved to $movedir"
    fi
    if (( remove_completed )); then
      log_to_screen "Removing torrent from list."
      transmission-remote -n $auth --torrent $TORRENT_ID --remove
      log_to_file 1 "$log_entry removed"
    fi
  else
    log_to_screen "Torrent #$TORRENT_ID is NOT completed."
  fi
done


current_dir=`dirname "$0"`
#[ ! -e "$current_dir/$prevent_shutdown_file_name" ] 
#preventer_file_exists=$?
#echo "P1:$preventer_file_exists"
[ -z "$(find "$current_dir" -mtime -1 -name "$prevent_shutdown_file_name")" ]
preventer_file_exists=$?
#echo "P2:$preventer_file_exists"

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
  log_to_file 2 "Shutdown?: $shutdown_if_no_active_torrent Time limit not reached?: $before_time_limit_ok Avoid file exists?: $preventer_file_exists"


  if (( shutdown_if_no_active_torrent == 1 )); then

    (( preventer_file_exists == 1 )) && log_to_screen "Shutdown canceled by file: `dirname "$0"`/$prevent_shutdown_file_name"  
    (( before_time_limit_ok == 0 )) && log_to_screen "Shutdown canceled by time limit."

    if (( before_time_limit_ok == 1 && preventer_file_exists != 1 )); then
     log_to_file 1 "Shutdown initiated."
     #shutdown in a minute
     sudo shutdown -h >> $log_file 2>&1 
    fi
  fi
fi

