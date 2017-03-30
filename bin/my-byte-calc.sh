#!/usr/bin/bash

Byte2Human()
{
  local numOfBytes="$1"

  while read -r B; do
    [ $B -lt 1024 ] && echo ${B} bytes && break
    KB=$(((B+512)/1024))
    [ $KB -lt 1024 ] && echo ${KB} kilobytes && break
    MB=$(((KB+512)/1024))
    [ $MB -lt 1024 ] && echo ${MB} megabytes && break
    GB=$(((MB+512)/1024))
    [ $GB -lt 1024 ] && echo ${GB} gigabytes && break
    echo $(((GB+512)/1024)) terabytes
  done < <(echo "$numOfBytes")
}

Human2Byte()
{
  local human="$1"
  if [ -n "$2" ]; then
    declare -n result="$2"
  else
    result=""
  fi

  local num="${human%*[ KMG]B}"
  local unit="${human##*[0-9 ]}"

  echo -n "$num $unit = "

  case "$num" in
    *[.,]*) echo "Error: Only integers are allowed."
      return 1 ;;
  esac

  case "$unit" in
    KB)
      result=$((num*1024)) 
      ;;
    MB)
      result=$((num*1024*1024)) 
      ;;
    GB)
      result=$((num*1024*1024*1024)) 
      ;;
    *) echo "Error: valid units are: KB, MB, GB."
      return 1 ;;
  esac
  echo $result B
}

Byte2Human 1231231123
Human2Byte 1245KB bytes
echo $bytes
Human2Byte 1223MB
Human2Byte 12GB

