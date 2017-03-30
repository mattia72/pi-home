#!/bin/sh

/usr/bin/transmission-remote -n mata:transmission -t $TR_TORRENT_ID -r
echo "`date`: $TR_TORRENT_ID - $TR_TORRENT_NAME removed" >> /home/pi/transmission-torrent-done.log
#echo "`date` - `whoami`: $TR_TORRENT_ID - $TR_TORRENT_NAME removed" >> /tmp/transmission-torrent-done.log
