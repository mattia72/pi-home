pulseaudio --start
# run "bluetoothctl" then "devices" to find the MAC address of your device.
Q10_MAC="5A:5A:5A:A6:0C:32"

if hcitool con | grep -q "$MAC"
then
  echo -e "disconnect $MAC \nquit" | bluetoothctl
else
  echo -e "connect $MAC \nquit" | bluetoothctl
fi
echo -e "power on\nconnect 5A:5A:5A:A6:0C:32 \nquit" | sudo bluetoothctl

read -p "Du you want to restart kodi [y/N]" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
  sudo systemctl restart kodi
fi
