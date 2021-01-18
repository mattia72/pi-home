
log_to_file()
{
  local msg_level="$1"
  local message="$2"

  [ $log_level -ge $msg_level ] && echo -e "`date +'%x %X'`: $message" >> $log_file
}

log_to_screen()
{
  local message="$1"
  local msg_level=0
  if [ $# -gt 1 ]; then
    msg_level="$1"
    message="$2"
  fi

  [ $log_level -ge $msg_level ] && echo -e "$message" 
  # msg_level 0 won't be logged
  [ $msg_level -gt 0 ] && log_to_file $msg_level "$message"
}

