#!/usr/bin/bash

Byte2Human()
{
  local numOfBytes="$1"

  while read -r B; do
    [ $B -lt 1024 ] && echo ${B} B && break
    KB=$(((B+512)/1024))
    [ $KB -lt 1024 ] && echo ${KB} KB && break
    MB=$(((KB+512)/1024))
    [ $MB -lt 1024 ] && echo ${MB} MB && break
    GB=$(((MB+512)/1024))
    [ $GB -lt 1024 ] && echo ${GB} GB && break
    echo $(((GB+512)/1024)) TB
  done < <(echo "$numOfBytes")
}

BcCalc()
{
  local exp="$1"
  if [ ! -z ${2+x} ]; then  #0 if $2 not set, otherwice "x"
    declare -n result="$2"
    result=$( echo "$exp" | bc )
  else
    echo "$exp" | bc 
  fi
}

Human2Byte()
{
  local human="$1"
  if [ ! -z ${2+x} ]; then  #0 if $2 not set, otherwice "x"
    declare -n result="$2"
  else
    result=""
  fi

  local num="${human%*[ KMG]*B}"
  local unit="${human##*[0-9 ]}"
  hash bc /dev/null 2>&1 
  local bc_nok=$?

  #echo -n "$num $unit = "

  case "$num" in
    *[.]*) 
      if (( bc_nok == 1 )); then 
        echo "Error: Only integers are allowed."
        return 1
      fi          ;;
  esac

  case "$unit" in
    KB)
      if (( bc_nok )); then
        result=$((num*1024)) 
      else
        BcCalc "$num*1024" bc_result
        result=$bc_result
      fi
      ;;
    MB)
      if (( bc_nok )); then
        result=$((num*1024*1024)) 
      else
        BcCalc "$num*1024*1024" bc_result
        result=$bc_result
      fi
      ;;
    GB)
      if (( bc_nok )); then
        result=$((num*1024*1024*1024)) 
      else
        BcCalc "$num*1024*1024*1024" bc_result
        result=$bc_result
      fi
      ;;
    *) echo "Error: valid units are: KB, MB, GB."
      return 1 ;;
  esac

  if [ -z "$2" ]; then
    echo $result
  fi
}

tests()
{
  Byte2Human 1231231123
  Human2Byte "12.45 KB"
  Human2Byte "1245 KB"
  Human2Byte "1245 GB" result1
  echo "result1=$result1 B"
  calc=$( BcCalc "123.23>123.45" ) 
  echo "calc result: $calc"
  if (( calc )); then
    echo "nok less then"
  else
    echo "ok greater"
  fi
#echo $bytes
#Human2Byte 1223MB
#Human2Byte 12GB
}

