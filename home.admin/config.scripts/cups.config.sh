#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install or remove CUPS services on parallel chains"
  echo "cups.config.sh install - called by the build_x86_64-amd64.sh"
  echo "cups.config.sh info"
  echo "cups.config.sh on"
  echo "cups.config.sh off"
  echo
  exit 1
fi


if [ "$1" = "info" ] ; then
  # the version that this script installs by default
  echo "CUPSDefaultInstallVersion='$(sudo apt search cups | grep cups)"
  exit 0
fi

if [ "$1" = "install" ] ; then

  echo "# *** INSTALL CUPS BINARY ***"
  sudo apt-get install cups cups-bsd  -y
  echo "- OK install of CUPS done"
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  sudo systemctl enable cups
  sudo systemctl start cups
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo systemctl stop cups
  sudo systemctl disable cups
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run"
exit 1
