#!/usr/bin/env bash

#########################################################################
# Build your image based on: Debian bullseye
# setup fresh Box with Raspiblitz above - login per SSH and run this script:
##########################################################################

defaultRepo="Smiril"
defaultBranch="v1.8"

me="${0##/*}"

nocolor="\033[0m"
red="\033[31m"

## usage as a function to be called whenever there is a huge mistake on the options
usage(){
  printf %s"${me} [--option <argument>]

Options:
  -h, --help                               this help info
  -i, --interaction [0|1]                  interaction before proceeding with exection (default: 1)
  -f, --fatpack [0|1]                      fatpack mode (default: 1)
  -u, --github-user [rootzoll|other]       github user to be checked from the repo (default: ${defaultRepo})
  -b, --branch [v1.7|v1.8]                 branch to be built on (default: ${defaultBranch})
  -d, --display [lcd|hdmi|headless]        display class (default: lcd)
  -t, --tweak-boot-drive [0|1]             tweak boot drives (default: 1)
  -w, --wifi-region [off|US|GB|other]      wifi iso code (default: AT) or 'off'

Notes:
  all options, long and short accept --opt=value mode also
  [0|1] can also be referenced as [false|true]
"
  exit 1
}
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi

## default user message
error_msg(){ printf %s"${red}${me}: ${1}${nocolor}\n"; exit 1; }

## assign_value variable_name "${opt}"
## it strips the dashes and assign the clean value to the variable
## assign_value status --on IS status=on
## variable_name is the name you want it to have
## $opt being options with single or double dashes that don't require arguments
assign_value(){
  case "${2}" in
    --*) value="${2#--}";;
    -*) value="${2#-}";;
    *) value="${2}"
  esac
  case "${value}" in
    0) value="false";;
    1) value="true";;
  esac
  ## Escaping quotes is needed because else if will fail if the argument is quoted
  # shellcheck disable=SC2140
  eval "${1}"="\"${value}\""
}

## get_arg variable_name "${opt}" "${arg}"
## get_arg service --service ssh
## variable_name is the name you want it to have
## $opt being options with single or double dashes
## $arg is requiring and argument, else it fails
## assign_value "${1}" "${3}" means it is assining the argument ($3) to the variable_name ($1)
get_arg(){
  case "${3}" in
    ""|-*) error_msg "Option '${2}' requires an argument.";;
  esac
  assign_value "${1}" "${3}"
}

## hacky getopts
## 1. if the option requires argument, and the option is preceeded by single or double dash and it
##    can be it can be specified with '-s=ssh' or '-s ssh' or '--service=ssh' or '--service ssh'
##    use: get_arg variable_name "${opt}" "${arg}"
## 2. if a bunch of options that does different things are to be assigned to the same variable
##    and the option is preceeded by single or double dash use: assign_value variable_name "${opt}"
##    as this option does not require argument, specifu $shift_n=1
## 3. if the option does not start with dash and does not require argument, assign to command manually.
while :; do
  case "${1}" in
    -*=*) opt="${1%=*}"; arg="${1#*=}"; shift_n=1;;
    -*) opt="${1}"; arg="${2}"; shift_n=2;;
    *) opt="${1}"; arg="${2}"; shift_n=1;;
  esac
  case "${opt}" in
    -i|-i=*|--interaction|--interaction=*) get_arg interaction "${opt}" "${arg}";;
    -f|-f=*|--fatpack|--fatpack=*) get_arg fatpack "${opt}" "${arg}";;
    -u|-u=*|--github-user|--github-user=*) get_arg github_user "${opt}" "${arg}";;
    -b|-b=*|--branch|--branch=*) get_arg branch "${opt}" "${arg}";;
    -d|-d=*|--display|--display=*) get_arg display "${opt}" "${arg}";;
    -t|-t=*|--tweak-boot-drive|--tweak-boot-drive=*) get_arg tweak_boot_drive "${opt}" "${arg}";;
    -w|-w=*|--wifi-region|--wifi-region=*) get_arg wifi_region "${opt}" "${arg}";;
    "") break;;
    *) error_msg "Invalid option: ${opt}";;
  esac
  shift "${shift_n}"
done

## if there is a limited option, check if the value of variable is within this range
## $ range_argument variable_name possible_value_1 possible_value_2
range_argument(){
  name="${1}"
  eval var='$'"${1}"
  shift
  if [ -n "${var:-}" ]; then
    success=0
    for tests in "${@}"; do
      [ "${var}" = "${tests}" ] && success=1
    done
    [ ${success} -ne 1 ] && error_msg "Option '--${name}' cannot be '${var}'! It can only be: ${*}."
  fi
}

apt_install(){
    sudo apt install -y ${@}
    if [ $? -eq 100 ]; then
        echo "FAIL! apt failed to install needed packages!"
        echo ${@}
        exit 1
    fi
}

general_utils="curl"
## loop all general_utils to see if program is installed (placed on PATH) and if not, add to the list of commands to be installed
for prog in ${general_utils}; do
  ! command -v ${prog} >/dev/null && general_utils_install="${general_utils_install} ${prog}"
done
## if any of the required programs are not installed, update and if successfull, install packages
if [ -n "${general_utils_install}" ]; then
  echo -e "\n*** SOFTWARE UPDATE ***"
  sudo apt update -y || exit 1
  apt_install ${general_utils_install}
fi

## use default values for variables if empty

# INTERACTION
# ----------------------------------------
# When 'false' then no questions will be asked on building .. so it can be used in build scripts
# for containers or as part of other build scripts (default is true)
: "${interaction:=true}"
range_argument interaction "0" "1" "false" "true"

# FATPACK
# -------------------------------
# could be 'true' (default) or 'false'
# When 'true' it will pre-install needed frameworks for additional apps and features
# as a convenience to safe on install and update time for additional apps.
# When 'false' it will just install the bare minimum and additional apps will just
# install needed frameworks and libraries on demand when activated by user.
# Use 'false' if you want to run your node without: go, dot-net, nodejs, docker, ...
: "${fatpack:=true}"
range_argument fatpack "0" "1" "false" "true"

# GITHUB-USERNAME
# ---------------------------------------
# could be any valid github-user that has a fork of the raspiblitz repo - 'rootzoll' is default
# The 'raspiblitz' repo of this user is used to provisioning sd card with raspiblitz assets/scripts later on.
: "${github_user:=$defaultRepo}"
curl -s "https://api.github.com/repos/${github_user}/raspiblitz" | grep -q "\"message\": \"Not Found\"" && error_msg "Repository 'raspiblitz' not found for user '${github_user}"

# GITHUB-BRANCH
# -------------------------------------
# could be any valid branch or tag of the given GITHUB-USERNAME forked raspiblitz repo
: "${branch:=$defaultBranch}"
curl -s "https://api.github.com/repos/${github_user}/raspiblitz/branches/${branch}" | grep -q "\"message\": \"Branch not found\"" && error_msg "Repository 'raspiblitz' for user '${github_user}' does not contain branch '${branch}'"

# DISPLAY-CLASS
# ----------------------------------------
# Could be 'hdmi', 'headless' or 'lcd' (lcd is default)
: "${display:=lcd}"
range_argument display "lcd" "hdmi" "headless"

# TWEAK-BOOTDRIVE
# ---------------------------------------
# could be 'true' (default) or 'false'
# If 'true' it will try (based on the base OS) to optimize the boot drive.
# If 'false' this will skipped.
: "${tweak_boot_drive:=true}"
range_argument tweak_boot_drive "0" "1" "false" "true"


# WIFI
# ---------------------------------------
# WIFI country code like 'US' (default)
# If any valid wifi country code Wifi will be activated with that country code by default
: "${wifi_region:=AT}"

echo "*****************************************"
echo "*     RASPIBLITZ BOX IMAGE SETUP        *"
echo "*****************************************"
echo "For details on optional parameters - call with '--help' or check source code."

# output
for key in interaction fatpack github_user branch display tweak_boot_drive wifi_region; do
  eval val='$'"${key}"
  [ -n "${val}" ] && printf '%s\n' "${key}=${val}"
done

# AUTO-DETECTION: CPU-ARCHITECTURE
# ---------------------------------------
cpu="$(uname -m)" && echo "cpu=${cpu}"
architecture="$(dpkg --print-architecture 2>/dev/null)" && echo "architecture=${architecture}"
case "${cpu}" in
  x86_64|amd64);;
  *) echo -e "# FAIL #\nCan only build on ARM, aarch64, x86_64, amd64 not on: cpu=${cpu}"; exit 1;;
esac

# AUTO-DETECTION: OPERATINGSYSTEM
# ---------------------------------------
if [ $(cat /etc/os-release 2>/dev/null | grep -c 'Debian') -gt 0 ]; then
  if [ $(uname -n | grep -c 'raspberrypi') -gt 0 ] && [ "${cpu}" = aarch64 ]; then
    # default image for RaspberryPi
    baseimage="raspios_arm64"
  elif [ $(uname -n | grep -c 'rpi') -gt 0 ] && [ "${cpu}" = aarch64 ]; then
    # experimental: a clean alternative image of debian for RaspberryPi
    baseimage="debian_rpi64"
  elif [ "${cpu}" = "arm" ] || [ "${cpu}" = "aarch64" ]; then
    # experimental: fallback for all debian on arm
    baseimage="armbian"
  else
    # experimental: fallback for all debian on other CPUs
    baseimage="debian"
  fi
elif [ $(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu') -gt 0 ]; then
  baseimage="ubuntu"
else
  echo "\n# FAIL: Base Image cannot be detected or is not supported."
  cat /etc/os-release 2>/dev/null
  uname -a
  exit 1
fi
echo "baseimage=${baseimage}"

# USER-CONFIRMATION
if [ "${interaction}" = "true" ]; then
  echo -n "# Do you agree with all parameters above? (yes/no) "
  read -r installRaspiblitzAnswer
  [ "$installRaspiblitzAnswer" != "yes" ] && exit 1
fi
echo -e "Building RaspiBlitz ...\n"
sleep 3 ## give time to cancel

export DEBIAN_FRONTEND=noninteractive

# FIXING LOCALES
# https://github.com/rootzoll/raspiblitz/issues/138
# https://daker.me/2014/10/how-to-fix-perl-warning-setting-locale-failed-in-raspbian.html
# https://stackoverflow.com/questions/38188762/generate-all-locales-in-a-docker-image
if [ "${baseimage}" = "debian" ]; then
  echo -e "\n*** FIXING LOCALES FOR BUILD ***"

  sudo sed -i "s/^# de_AT.UTF-8 UTF-8.*/de_AT.UTF-8 UTF-8/g" /etc/locale.gen
  sudo sed -i "s/^# de_AT ISO-8859-1.*/de_AT ISO-8859-1/g" /etc/locale.gen
  sudo locale-gen
  export LANGUAGE=de_AT.UTF-8
  export LANG=de_AT.UTF-8
  if [ ! -f /etc/apt/sources.list.d/zoe.list ]; then
    echo "# Add the ftp.at.debian.org/debian/ to the sources.list"
    echo "deb http://ftp.at.debian.org/debian/ bullseye main" | sudo tee /etc/apt/sources.list.d/zoe.list
  fi
fi

echo "*** Remove unnecessary packages ***"
sudo apt remove --purge -y libreoffice* oracle-java* chromium-browser nuscratch scratch sonic-pi python2 vlc
sudo apt clean -y
sudo apt autoremove -y

echo -e "\n*** UPDATE Debian***"
sudo apt update -y
sudo apt upgrade -f -y

echo -e "\n*** SOFTWARE UPDATE ***"
# based on https://raspibolt.org/system-configuration.html#system-update
# htop git curl bash-completion vim jq dphys-swapfile bsdmainutils -> helpers
# autossh telnet vnstat -> network tools bandwidth monitoring for future statistics
# parted dosfstools -> prepare for format data drive
# btrfs-progs -> prepare for BTRFS data drive raid
# fbi -> prepare for display graphics mode. https://github.com/rootzoll/raspiblitz/pull/334
# sysbench -> prepare for powertest
# build-essential -> check for build dependencies on Ubuntu, Armbian
# dialog -> dialog bc python3-dialog
# rsync -> is needed to copy from HDD
# net-tools -> ifconfig
# xxd -> display hex codes
# netcat -> for proxy
# openssh-client openssh-sftp-server sshpass -> install OpenSSH client + server
# psmisc -> install killall, fuser
# ufw -> firewall
# sqlite3 -> database
# lsb-release -> needed to know which distro version we're running to add APT sources
general_utils="policykit-1 htop lynx git curl bash-completion vim jq dphys-swapfile bsdmainutils autossh telnet vnstat parted dosfstools btrfs-progs fbi sysbench build-essential dialog bc python3-dialog unzip whois wireless-tools iw lsb-release"
python_dependencies="python3-venv python3-dev python3-wheel python3-jinja2 python3-pip"
server_utils="rsync net-tools xxd netcat openssh-client openssh-sftp-server sshpass psmisc ufw sqlite3"
[ "${baseimage}" = "armbian" ] && armbian_dependencies="armbian-config" # add armbian-config
apt_install ${general_utils} ${python_dependencies} ${server_utils} ${armbian_dependencies}
sudo apt clean -y
sudo apt autoremove -y

echo -e "\n*** Python DEFAULT libs & dependencies ***"
# make sure /usr/bin/pip exists (and calls pip3 in Debian Buster)
sudo update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1
# 1. libs (for global python scripts)
# grpcio==1.42.0 googleapis-common-protos==1.53.0 toml==0.10.2 j2cli==0.3.10 requests[socks]==2.21.0
# 2. For TorBox bridges python scripts (pip3) https://github.com/radio24/TorBox/blob/master/requirements.txt
# pytesseract mechanize PySocks urwid Pillow requests
# 3. Nyx
# setuptools
python_libs="grpcio==1.42.0 googleapis-common-protos==1.53.0 toml==0.10.2 j2cli==0.3.10 requests[socks]==2.21.0 protobuf==3.20.1"
torbox_libs="pytesseract mechanize PySocks urwid Pillow requests setuptools"
sudo -H python3 -m pip install --upgrade pip
sudo -H python3 -m pip install ${python_libs} ${torbox_libs}

if [ -f "/usr/bin/python3.9" ]; then
  # use python 3.9 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
  echo "python calls python3.9"
elif [ -f "/usr/bin/python3.10" ]; then
  # use python 3.10 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1
  sudo ln -s /usr/bin/python3.10 /usr/bin/python3.9
  echo "python calls python3.10"
elif [ -f "/usr/bin/python3.8" ]; then
  # use python 3.8 if available
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  echo "python calls python3.8"
else
  echo "# FAIL #"
  echo "There is no tested version of python present"
  exit 1
fi

echo -e "\n*** PREPARE ${baseimage} ***"

# make sure the fatzoe user is present
if [ "$(compgen -u | grep -c fatzoe)" -eq 0 ];then
  echo "# Adding the user fatzoe"
  sudo adduser --disabled-password --gecos "" fatzoe
  sudo adduser fatzoe sudo
fi

# special prepare when debian
if [ "${baseimage}" = "debian" ]; then
    
  echo -e "\n*** PREPARE Debian OS VARIANTS ***"
  # run fsck on sd root partition on every startup to prevent "maintenance login" screen
  # see: https://github.com/rootzoll/raspiblitz/issues/782#issuecomment-564981630
  # see https://github.com/rootzoll/raspiblitz/issues/1053#issuecomment-600878695
  # use command to check last fsck check: sudo tune2fs -l /dev/mmcblk0p2
  if [ "${tweak_boot_drive}" == "true" ]; then
    echo "* running tune2fs"
    sudo tune2fs -c 1 /dev/nvme0n1p1
  else
    echo "* skipping tweak_boot_drive"
  fi
fi

# special prepare when Nvidia Jetson Nano
if [ $(uname -a | grep -c 'Debian') -gt 0 ] ; then
  echo "Debian --> disable GUI on boot"
  sudo systemctl set-default multi-user.target
fi

echo -e "\n*** CONFIG ***"
# based on https://raspibolt.github.io/raspibolt/raspibolt_20_pi.html#raspi-config

# set new default password for root user
echo "root:raspiblitz" | sudo chpasswd
echo "fatzoe:raspiblitz" | sudo chpasswd

# limit journald system use
sudo sed -i "s/^#SystemMaxUse=.*/SystemMaxUse=512M/g" /etc/systemd/journald.conf
sudo sed -i "s/^#SystemMaxFileSize=.*/SystemMaxFileSize=150M/g" /etc/systemd/journald.conf

# change log rotates
# see https://github.com/rootzoll/raspiblitz/issues/394#issuecomment-471535483
echo "
/var/log/syslog
{
    rotate 7
    daily
    missingok
    notifempty
    delaycompress
  compress
  postrotate
    invoke-rc.d rsyslog rotate > /dev/null
  endscript
}

/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
{
  rotate 4
  size=100M
  missingok
  notifempty
  compress
  delaycompress
  sharedscripts
  postrotate
    invoke-rc.d rsyslog rotate > /dev/null
  enscript
}


/var/log/kern.log
/var/log/auth.log
{
        rotate 4
        size=100M
        missingok
        notifempty
        compress
        delaycompress
        sharedscripts
        postrotate
                invoke-rc.d rsyslog rotate > /dev/null
        endscript
}

/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
    rotate 4
    weekly
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        invoke-rc.d rsyslog rotate > /dev/null
    endscript
}
" | sudo tee ./rsyslog
sudo mv ./rsyslog /etc/logrotate.d/rsyslog
sudo chown root:root /etc/logrotate.d/rsyslog
sudo service rsyslog restart
echo -e "\n*** ADDING MAIN USER admin ***"
# based on https://raspibolt.org/system-configuration.html#add-users
# using the default password 'raspiblitz'
sudo adduser --disabled-password --gecos "" admin
echo "admin:raspiblitz" | sudo chpasswd
sudo adduser admin sudo
sudo adduser admin lpadmin
sudo chsh admin -s /bin/bash
# configure sudo for usage without password entry
echo '%sudo ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo
# check if group "admin" was created
if [ $(sudo cat /etc/group | grep -c "^admin") -lt 1 ]; then
  echo -e "\nMissing group admin - creating it ..."
  sudo /usr/sbin/groupadd --force --gid 1002 admin
  sudo usermod -a -G admin admin
else
  echo -e "\nOK group admin exists"
fi

echo -e "\n*** ADDING SERVICE USER bitcoin"
# based on https://raspibolt.org/guide/raspberry-pi/system-configuration.html
# create user and set default password for user
sudo adduser --disabled-password --gecos "" bitcoin
echo "bitcoin:raspiblitz" | sudo chpasswd
# make home directory readable
sudo chmod 755 /home/bitcoin

# WRITE BASIC raspiblitz.info to sdcard
# if further info gets added .. make sure to keep that on: blitz.preparerelease.sh
sudo touch /home/admin/raspiblitz.info
echo "baseimage=${baseimage}" | tee raspiblitz.info
echo "cpu=${cpu}" | tee -a raspiblitz.info
echo "displayClass=headless" | tee -a raspiblitz.info
sudo mv raspiblitz.info /home/admin/
sudo chmod 755 /home/admin/raspiblitz.info
sudo chown admin:admin /home/admin/raspiblitz.info

echo -e "\n*** ADDING GROUPS FOR CREDENTIALS STORE ***"
# access to credentials (e.g. macaroon files) in a central location is managed with unix groups and permissions
sudo /usr/sbin/groupadd --force --gid 9700 lndadmin
sudo /usr/sbin/groupadd --force --gid 9701 lndinvoice
sudo /usr/sbin/groupadd --force --gid 9702 lndreadonly
sudo /usr/sbin/groupadd --force --gid 9703 lndinvoices
sudo /usr/sbin/groupadd --force --gid 9704 lndchainnotifier
sudo /usr/sbin/groupadd --force --gid 9705 lndsigner
sudo /usr/sbin/groupadd --force --gid 9706 lndwalletkit
sudo /usr/sbin/groupadd --force --gid 9707 lndrouter

echo -e "\n*** SHELL SCRIPTS & ASSETS ***"
# copy raspiblitz repo from github
cd /home/admin/ || exit 1
sudo -u admin git config --global user.name "${github_user}"
sudo -u admin git config --global user.email "johndoe@example.com"
sudo -u admin rm -rf /home/admin/raspiblitz
sudo -u admin git clone -b "${branch}" https://github.com/${github_user}/raspiblitz.git
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin cp /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod +x /home/admin/config.scripts/*.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/setup.scripts /home/admin/
sudo -u admin chmod +x /home/admin/setup.scripts/*.sh

# install newest version of BlitzPy
blitzpy_wheel=$(ls -tR /home/admin/raspiblitz/home.admin/BlitzPy/dist | grep -E "any.whl" | tail -n 1)
blitzpy_version=$(echo "${blitzpy_wheel}" | grep -oE "([0-9]\.[0-9]\.[0-9])")
echo -e "\n*** INSTALLING BlitzPy Version: ${blitzpy_version} ***"
sudo -H /usr/bin/python -m pip install "/home/admin/raspiblitz/home.admin/BlitzPy/dist/${blitzpy_wheel}" >/dev/null 2>&1

# make sure lndlibs are patched for compatibility for both Python2 and Python3
file="/home/admin/config.scripts/lndlibs/lightning_pb2_grpc.py"
! grep -Fxq "from __future__ import absolute_import" "${file}" && sed -i -E '1 a from __future__ import absolute_import' "${file}"
! grep -Eq "^from . import.*" "${file}" && sed -i -E 's/^(import.*_pb2)/from . \1/' "${file}"

# add /sbin to path for all
sudo bash -c "echo 'PATH=\$PATH:/sbin' >> /etc/profile"

echo -e "\n*** RASPIBLITZ EXTRAS ***"

# screen for background processes
# tmux for multiple (detachable/background) sessions when using SSH https://github.com/rootzoll/raspiblitz/issues/990
# fzf install a command-line fuzzy finder (https://github.com/junegunn/fzf)
apt_install tmux screen fzf

echo "
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern \"**\" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval \"$(SHELL=/bin/sh lesspipe)\"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z \"${debian_chroot:-}\" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we \"want\" color)
case \"$TERM\" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n \"$force_color_prompt\" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
    else
    color_prompt=
    fi
fi

if [ \"$color_prompt\" = yes ]; then
    PS1=\'${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w \$\[\033[00m\] \'
else
    PS1=\'${debian_chroot:+($debian_chroot)}\u@\h:\w\$ \'
fi
# raspiblitz custom command prompt https://github.com/rootzoll/raspiblitz/issues/2400
raspiIp=$(hostname -I | cut -d \" \" -f1)
if [ \"$color_prompt\" = yes ]; then
    PS1=\'${debian_chroot:+($debian_chroot)}\[\033[00;33m\]\u@$raspiIp:\[\033[00;34m\]\w\[\033[01;35m\]$(__git_ps1 "(%s)") \[\033[01;33m\]₿\[\033[00m\] \'
else
    PS1=\'${debian_chroot:+($debian_chroot)}\u@$raspiIp:\w₿ \'
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case \"$TERM\" in
xterm*|rxvt*)
    PS1=\"\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1\"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval \"$(dircolors -b ~/.dircolors)\" || eval \"$(dircolors -b)\"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
#alias ll='ls -l'
#alias la='ls -A'
#alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# https://github.com/rootzoll/raspiblitz/issues/1784
NG_CLI_ANALYTICS=ci
source /usr/share/doc/fzf/examples/key-bindings.bash
# shortcut commands
source /home/admin/_commands.sh
# automatically start main menu for admin unless
# when running in a tmux session
if [ -z \"$TMUX\" ]; then
    ./00raspiblitz.sh newsshsession
fi
" > /home/admin/.bashrc

echo -e "\n*** SWAP FILE ***"
# based on https://stadicus.github.io/RaspiBolt/raspibolt_20_pi.html#move-swap-file
# but just deactivating and deleting old (will be created alter when user adds HDD)
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall

echo -e "\n*** INCREASE OPEN FILE LIMIT ***"
# based on https://raspibolt.org/guide/raspberry-pi/security.html#increase-your-open-files-limit
sudo sed --in-place -i "56s/.*/*    soft nofile 256000/" /etc/security/limits.conf
sudo bash -c "echo '*    hard nofile 256000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root soft nofile 256000' >> /etc/security/limits.conf"
sudo bash -c "echo 'root hard nofile 256000' >> /etc/security/limits.conf"
sudo bash -c "echo '# End of file' >> /etc/security/limits.conf"
sudo sed --in-place -i "23s/.*/session required pam_limits.so/" /etc/pam.d/common-session
sudo sed --in-place -i "25s/.*/session required pam_limits.so/" /etc/pam.d/common-session-noninteractive
sudo bash -c "echo '# end of pam-auth-update config' >> /etc/pam.d/common-session-noninteractive"
# increase the possible number of running processes from 128
sudo bash -c "echo 'fs.inotify.max_user_instances=4096' >> /etc/sysctl.conf"

# *** fail2ban ***
# based on https://raspibolt.org/security.html#fail2ban
echo "*** HARDENING ***"
apt_install --no-install-recommends python3-systemd fail2ban

# *** CACHE DISK IN RAM & KEYVALUE-STORE***
echo "Activating CACHE RAM DISK ... "
sudo /home/admin/_cache.sh ramdisk on
sudo /home/admin/_cache.sh keyvalue on

# *** Wifi, Bluetooth & other RaspberryPi configs ***
if [ "${baseimage}" = "debian" ]; then

  if [ "${wifi_region}" == "off" ]; then
    echo -e "\n*** DISABLE WIFI ***"
    sudo systemctl disable wpa_supplicant.service
    sudo iwconfig wlan0 down
  else
    echo -e "\n*** ENABLE WIFI ***"
    sudo iw reg set ${wifi_region}
    sudo systemctl enable wpa_supplicant.service
    sudo iwconfig wlan0 up
  fi

  # remove bluetooth services
  sudo systemctl disable bluetooth.service
  sudo systemctl disable hciuart.service

  # remove bluetooth packages
  sudo apt remove -y --purge pi-bluetooth bluez bluez-firmware
fi

# *** BOOTSTRAP ***
echo -e "\n*** BOOTSTRAP SERVICE ***"
sudo chmod +x /home/admin/_bootstrap.sh
sudo cp /home/admin/assets/bootstrap.service /etc/systemd/system/bootstrap.service
sudo systemctl enable bootstrap

# *** BACKGROUND TASKS ***
echo -e "\n*** BACKGROUND SERVICE ***"
sudo chmod +x /home/admin/_background.sh
sudo cp /home/admin/assets/background.service /etc/systemd/system/background.service
sudo systemctl enable background

# *** BACKGROUND SCAN ***
sudo /home/admin/_background.scan.sh install

#######
# TOR #
#######
echo
sudo /home/admin/config.scripts/tor.install.sh install || exit 1

###########
# BITCOIN #
###########
echo
sudo /home/admin/config.scripts/bitcoin.install.sh install || exit 1

# *** BLITZ WEB SERVICE ***
echo "Provisioning BLITZ WEB SERVICE"
sudo /home/admin/config.scripts/blitz.web.sh http-on || exit 1

# *** FATPACK *** (can be activated by parameter - see details at start of script)
if ${fatpack}; then
  echo -e "\n*** FATPACK ***"

  echo "* Adding nodeJS Framework ..."
  sudo /home/admin/config.scripts/bonus.nodejs.sh on || exit 1

  echo "* Optional Packages (may be needed for extended features)"
  apt_install qrencode secure-delete fbi ssmtp unclutter xterm python3-pyqt5 xfonts-terminus apache2-utils nginx python3-jinja2 socat libatlas-base-dev hexyl autossh

  echo "* Adding LND ..."
  sudo /home/admin/config.scripts/lnd.install.sh install || exit 1
  
  echo "* Adding CUPS ..."
  sudo /home/admin/config.scripts/cups.config.sh install || exit 1
  echo "* Enable CUPS ..."
  sudo /home/admin/config.scripts/cups.config.sh on || exit 1
  
  echo "* Adding Core Lightning ..."
  sudo /home/admin/config.scripts/cl.install.sh install || exit 1
  echo "* Adding the cln-grpc plugin ..."
  sudo /home/admin/config.scripts/cl-plugin.cln-grpc.sh install || exit 1

  # *** UPDATE FALLBACK NODE LIST (only as part of fatpack) *** see https://github.com/rootzoll/raspiblitz/issues/1888
  echo "*** FALLBACK NODE LIST ***"
  sudo -u admin curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ -o /home/admin/fallback.nodes
  byteSizeList=$(sudo -u admin stat -c %s /home/admin/fallback.nodes)
  if [ ${#byteSizeList} -eq 0 ] || [ ${byteSizeList} -lt 10240 ]; then
    echo "WARN: Failed downloading fresh FALLBACK NODE LIST --> https://bitnodes.io/api/v1/snapshots/latest/"
    sudo rm /home/admin/fallback.nodes 2>/dev/null
    sudo cp /home/admin/assets/fallback.nodes /home/admin/fallback.nodes
  fi
  sudo chown admin:admin /home/admin/fallback.nodes

  echo "* Adding Raspiblitz API ..."
  sudo /home/admin/config.scripts/blitz.web.api.sh on || exit 1

  echo "* Adding Raspiblitz WebUI ..."
  sudo /home/admin/config.scripts/blitz.web.ui.sh on || exit 1

  # set build code as new default
  sudo rm -r /home/admin/assets/nginx/www_public
  sudo cp -a /home/blitzapi/blitz_web/build/* /home/admin/assets/nginx/www_public
  sudo chown admin:admin /home/admin/assets/nginx/www_public
  sudo rm -r /home/blitzapi/blitz_web/build/*

else
  echo "* skipping FATPACK"
fi

echo
echo "*** raspiblitz.info ***"
sudo cat /home/admin/raspiblitz.info

# *** RASPIBLITZ IMAGE READY INFO ***
echo -e "\n**********************************************"
echo "BASIC BOX BUILD DONE"
echo -e "**********************************************\n"
echo "Your SD Card Image for RaspiBlitz is ready (might still do display config)."
echo "Take the chance & look thru the output above if you can spot any errors or warnings."
echo -e "\nIMPORTANT IF WANT TO MAKE A RELEASE IMAGE FROM THIS BUILD:"
echo "1. login fresh --> user:admin password:raspiblitz"
echo -e "2. run --> release\n"

# (do last - because might trigger reboot)
if [ "${display}" != "headless" ] || [ "${baseimage}" = "raspios_arm64" ]; then
  echo "*** ADDITIONAL DISPLAY OPTIONS ***"
  echo "- calling: blitz.display.sh set-display ${display}"
  sudo /home/admin/config.scripts/blitz.display.sh set-display ${display}
  sudo /home/admin/config.scripts/blitz.display.sh rotate 1
fi

echo "# BUILD DONE - see above"
