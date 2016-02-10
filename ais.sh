#!/bin/bash
#-------------------------------------------------------------------------------
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.
#-------------------------------------------------------------------------------

AUI_DIR=`pwd`
# LOG FILE
LOG="${AUI_DIR}/`basename ${0}`_error.log"
[[ -f $LOG ]] && rm -f $LOG

#COMMON FUNCTIONS {{{

error_msg() { #{{{
  local MSG="${1}"
  echo -e "${MSG}"
  exit 1
} #}}}

cecho() { #{{{
  echo -e "$1"
  echo -e "$1" >>"$LOG"
  tput sgr0;
} #}}}

ncecho() { #{{{
  echo -ne "$1"
  echo -ne "$1" >>"$LOG"
  tput sgr0
} #}}}

spinny() { #{{{
  echo -ne "\b${SPIN:i++%${#SPIN}:1}"
} #}}}

print_line() { #{{{
  printf "%$(tput cols)s\n"|tr ' ' '-'
} #}}}

print_title() { #{{{
  clear
  print_line
  echo -e "# ${Bold}$1${Reset}"
  print_line
  echo ""
} #}}}


add_line() { #{{{
  ADD_LINE=${1}
  FILEPATH=${2}
  CHECK_LINE=`grep -F "${ADD_LINE}" ${FILEPATH}`
  [[ -z $CHECK_LINE ]] && echo "${ADD_LINE}" >> ${FILEPATH}
} #}}}


replace_line() { #{{{
  SEARCH=${1}
  REPLACE=${2}
  FILEPATH=${3}
  FILEBASE=`basename ${3}`

  sed -e "s/${SEARCH}/${REPLACE}/" ${FILEPATH} > /tmp/${FILEBASE} 2>"$LOG"
  if [[ ${?} -eq 0 ]]; then
    mv /tmp/${FILEBASE} ${FILEPATH}
  else
    cecho "failed: ${SEARCH} - ${FILEPATH}"
  fi
} #}}}

read_input_text() { #{{{
  if [[ $AUTOMATIC_MODE -eq 1 ]]; then
    OPTION=$2
  else
    read -p "$1 [y/N]: " OPTION
    echo ""
  fi
  OPTION=`echo "$OPTION" | tr '[:upper:]' '[:lower:]'`
} #}}}

read_input_options() { #{{{
  local line
  local packages
  if [[ $AUTOMATIC_MODE -eq 1 ]]; then
    array=("$1")
  else
    read -p "$prompt2" OPTION
    array=("$OPTION")
  fi
  for line in ${array[@]/,/ }; do
    if [[ ${line/-/} != $line ]]; then
      for ((i=${line%-*}; i<=${line#*-}; i++)); do
        packages+=($i);
      done
    else
      packages+=($line)
    fi
  done
  OPTIONS=("${packages[@]}")
} #}}}

invalid_option() { #{{{
  print_line
  echo "Invalid option. Try another one."
  pause_function
} #}}}


system_upgrade() { #{{{
  pacman -Syu
} #}}}

pause_function() { #{{{
    print_line
    read -e -sn 1 -p "Press enter to continue..."
  } #}}}

is_package_installed() { #{{{
  #check if a package is already installed
  for PKG in $1; do
    pacman -Q $PKG &> /dev/null && return 0;
  done
  return 1
} #}}}

package_install() { #{{{
  #install packages using pacman
  for PKG in ${1}; do
    if ! is_package_installed "${PKG}" ; then
      pacman -S ${PKG}
    else
      echo "${PKG} already installed!"
    fi
  done
} #}}}


check_archlinux() { #{{{
  if [[ ! -e /etc/arch-release ]]; then
    error_msg "ERROR! You must execute the script on Arch Linux."
  fi
} #}}}

check_hostname() { #{{{
  if [[ `echo ${HOSTNAME} | sed 's/ //g'` == "" ]]; then
    error_msg "ERROR! Hostname is not configured."
  fi
} #}}}


check_pacman_blocked() { #{{{
  if [[ -f /var/lib/pacman/db.lck ]]; then
    error_msg "ERROR! Pacman is blocked. \nIf not running remove /var/lib/pacman/db.lck."
  fi
} #}}}

check_connection(){ #{{{
    XPINGS=0
    XPINGS=$(( $XPINGS + 1 ))
    connection_test() {
      ping -q -w 1 -c 1 `ip r | grep default | awk 'NR==1 {print $3}'` &> /dev/null && return 1 || return 0
    }
    WIRED_DEV=`ip link | grep enp | awk '{print $2}'| sed 's/://' | sed '1!d'`
    WIRELESS_DEV=`ip link | grep wlp | awk '{print $2}'| sed 's/://' | sed '1!d'`
    if connection_test; then
      print_warning "ERROR! Connection not Found."
      print_info "Network Setup"
      conn_type_list=("Wired Automatic" "Wired Manual" "Wireless" "Skip")
      PS3="$prompt1"
      select CONNECTION_TYPE in "${conn_type_list[@]}"; do
        case "$REPLY" in
          1)
            systemctl start dhcpcd@${WIRED_DEV}.service
            break
            ;;
          2)
            systemctl stop dhcpcd@${WIRED_DEV}.service
            read -p "IP Address: " IP_ADDR
            read -p "Submask: " SUBMASK
            read -p "Gateway: " GATEWAY
            ip link set ${WIRED_DEV} up
            ip addr add ${IP_ADDR}/${SUBMASK} dev ${WIRED_DEV}
            ip route add default via ${GATEWAY}
            $EDITOR /etc/resolv.conf
            break
            ;;
          3)
            ip link set ${WIRELESS_DEV} up
            wifi-menu ${WIRELESS_DEV}
            break
            ;;
          4)
            break
            ;;
          *)
            invalid_option
            ;;
        esac
      done
      if [[ $XPINGS -gt 2 ]]; then
        print_warning "Can't establish connection. exiting..."
        exit 1
      fi
      [[ $REPLY -ne 4 ]] && check_connection
    fi
} #}}}

#CONFIGURE SUDO {{{
configure_sudo(){
  if ! is_package_installed "sudo" ; then
    print_title "SUDO - https://wiki.archlinux.org/index.php/Sudo"
    package_install "sudo"
  fi
  sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers
}
#}}}

#CREATE NEW USER {{{
create_new_user(){
  read -p "Username: " username
  useradd -m -g users -G wheel -s /bin/bash ${username}
  chfn ${username}
  passwd ${username}
  pause_function
}
#}}}


# ENABLE MULTILIB REPOSITORY {{{
add_multilib(){
# this option will avoid any problem with packages install
if [[ $ARCHI == x86_64 ]]; then
  local MULTILIB=`grep -n "\[multilib\]" /etc/pacman.conf | cut -f1 -d:`
  if [[ -z $MULTILIB ]]; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
    echo -e '\nMultilib repository added into pacman.conf file'
  else
    sed -i "${MULTILIB}s/^#//" /etc/pacman.conf
    local MULTILIB=$(( $MULTILIB + 1 ))
    sed -i "${MULTILIB}s/^#//" /etc/pacman.conf
  fi
fi
sed -i '/#Color/s/^#//' /etc/pacman.conf
}
#}}}

check_vga() { #{{{
  # Determine video chipset - only Intel, ATI and nvidia are supported by this script"
  ncecho " ${BBlue}[${Reset}${Bold}X${BBlue}]${Reset} Detecting video chipset "
  local VGA=`lspci | grep VGA | tr "[:upper:]" "[:lower:]"`
  local VGA_NUMBER=`lspci | grep VGA | wc -l`

  if [[ -n $(dmidecode --type 1 | grep VirtualBox) ]]; then
    cecho Virtualbox
    VIDEO_DRIVER="virtualbox"
  elif [[ $VGA_NUMBER -eq 2 ]] && [[ -n $(echo ${VGA} | grep "nvidia") || -f /sys/kernel/debug/dri/0/vbios.rom ]]; then
    cecho Bumblebee
    VIDEO_DRIVER="bumblebee"
  elif [[ -n $(echo ${VGA} | grep "nvidia") || -f /sys/kernel/debug/dri/0/vbios.rom ]]; then
    cecho Nvidia
    read_input_text "Install NVIDIA proprietary driver" $PROPRIETARY_DRIVER
    if [[ $OPTION == y ]]; then
      VIDEO_DRIVER="nvidia"
    else
      VIDEO_DRIVER="nouveau"
    fi
  elif [[ -n $(echo ${VGA} | grep "advanced micro devices") || -f /sys/kernel/debug/dri/0/radeon_pm_info || -f /sys/kernel/debug/dri/0/radeon_sa_info ]]; then
    cecho AMD/ATI
    read_input_text "Install ATI proprietary driver" $PROPRIETARY_DRIVER
    if [[ $OPTION == y ]]; then
      VIDEO_DRIVER="catalyst"
    else
      VIDEO_DRIVER="ati"
    fi
  elif [[ -n $(echo ${VGA} | grep "intel corporation") || -f /sys/kernel/debug/dri/0/i915_capabilities ]]; then
    cecho Intel
    VIDEO_DRIVER="intel"
  else
    cecho VESA
    VIDEO_DRIVER="vesa"
  fi
  OPTION="y"
  [[ $VIDEO_DRIVER == intel || $VIDEO_DRIVER == vesa ]] && read -p "Confirm video driver: $VIDEO_DRIVER [Y/n]" OPTION
  if [[ $OPTION == n ]]; then
    read -p "Type your video driver [ex: sis, fbdev, modesetting]: " VIDEO_DRIVER
  fi
} #}}}


#VIDEO CARDS {{{
install_video_cards(){
  package_install "dmidecode"
  print_title "VIDEO CARD"
  check_vga
  #Virtualbox {{{
  if [[ ${VIDEO_DRIVER} == virtualbox ]]; then
    package_install "virtualbox-guest-utils"
    package_install "mesa-libgl"
    add_module "vboxguest vboxsf vboxvideo" "virtualbox-guest"
    add_user_to_group ${username} vboxsf
    systemctl disable ntpd
    systemctl enable vbo
    VBoxClient-all
  #}}}
  #Bumblebee {{{
  elif [[ ${VIDEO_DRIVER} == bumblebee ]]; then
    XF86_DRIVERS=$(pacman -Qe | grep xf86-video | awk '{print $1}')
    [[ -n $XF86_DRIVERS ]] && pacman -Rcsn $XF86_DRIVERS
    is_package_installed "nouveau-dri" && pacman -Rdds --noconfirm nouveau-dri
    pacman -S --needed intel-dri xf86-video-intel bumblebee nvidia
    package_install "pangox-compat" #fix nvidia-settings
    package_install "libva-vdpau-driver"
    if [[ ${ARCHI} == x86_64 ]]; then
      is_package_installed "lib32-nouveau-dri" && pacman -Rdds --noconfirm lib32-nouveau-dri
      pacman -S --needed lib32-nvidia-utils lib32-intel-dri
    fi
    replace_line '*options nouveau modeset=1' '#options nouveau modeset=1' /etc/modprobe.d/modprobe.conf
    replace_line '*MODULES="nouveau"' '#MODULES="nouveau"' /etc/mkinitcpio.conf
    mkinitcpio -p linux
    gpasswd -a ${username} bumblebee
  #}}}
  #NVIDIA {{{
  elif [[ ${VIDEO_DRIVER} == nvidia ]]; then
    XF86_DRIVERS=$(pacman -Qe | grep xf86-video | awk '{print $1}')
    [[ -n $XF86_DRIVERS ]] && pacman -Rcsn $XF86_DRIVERS
    is_package_installed "nouveau-dri" && pacman -Rdds --noconfirm nouveau-dri
    pacman -S --needed nvidia{,-utils}
    package_install "pangox-compat" #fix nvidia-settings
    package_install "libva-vdpau-driver"
    if [[ ${ARCHI} == x86_64 ]]; then
      is_package_installed "lib32-nouveau-dri" && pacman -Rdds --noconfirm lib32-nouveau-dri
      pacman -S --needed "lib32-nvidia-utils"
    fi
    replace_line '*options nouveau modeset=1' '#options nouveau modeset=1' /etc/modprobe.d/modprobe.conf
    replace_line '*MODULES="nouveau"' '#MODULES="nouveau"' /etc/mkinitcpio.conf
    mkinitcpio -p linux
    nvidia-xconfig --add-argb-glx-visuals --allow-glx-with-composite --composite -no-logo --render-accel -o /etc/X11/xorg.conf.d/20-nvidia.conf;
  #}}}
  #Nouveau [NVIDIA] {{{
  elif [[ ${VIDEO_DRIVER} == nouveau ]]; then
    is_package_installed "nvidia" && pacman -Rdds --noconfirm nvidia{,-utils}
    [[ -f /etc/X11/xorg.conf.d/20-nvidia.conf ]] && rm /etc/X11/xorg.conf.d/20-nvidia.conf
    package_install "mesa-libgl"
    package_install "xf86-video-${VIDEO_DRIVER} ${VIDEO_DRIVER}-dri"
    if [[ ${ARCHI} == x86_64 ]]; then
      is_package_installed "lib32-nvidia-utils" && pacman -Rdds --noconfirm lib32-nvidia-utils
      pacman -S --needed "lib32-${VIDEO_DRIVER}-dri"
    fi
    replace_line '#*options nouveau modeset=1' 'options nouveau modeset=1' /etc/modprobe.d/modprobe.conf
    replace_line '#*MODULES="nouveau"' 'MODULES="nouveau"' /etc/mkinitcpio.conf
    mkinitcpio -p linux
  #}}}
  #Catalyst [ATI] {{{
  elif [[ ${VIDEO_DRIVER} == catalyst ]]; then
    XF86_DRIVERS=$(pacman -Qe | grep xf86-video | awk '{print $1}')
    [[ -n $XF86_DRIVERS ]] && pacman -Rcsn $XF86_DRIVERS
    is_package_installed "ati-dri" && pacman package_remove "ati-dri"
    [[ -f /etc/modules-load.d/ati.conf ]] && rm /etc/modules-load.d/ati.conf
    if [[ ${ARCHI} == x86_64 ]]; then
      is_package_installed "lib32-ati-dri" && pacman -Rdds --noconfirm lib32-ati-dri
    fi
    package_install "linux-headers"
    # Add repository
    aur_package_install "catalyst-test"
    aticonfig --initial --output=/etc/X11/xorg.conf.d/20-radeon.conf
    systemctl enable atieventsd
    systemctl enable catalyst-hook
    systemctl enable temp-links-catalyst
  #}}}
  #ATI {{{
  elif [[ ${VIDEO_DRIVER} == ati ]]; then
    is_package_installed "catalyst-test" && pacman -Rdds --noconfirm catalyst-test
    package_install "mesa-libgl"
    [[ -f /etc/X11/xorg.conf.d/20-radeon.conf ]] && rm /etc/X11/xorg.conf.d/20-radeon.conf
    [[ -f /etc/modules-load.d/catalyst.conf ]] && rm /etc/modules-load.d/ati.conf
    package_install "xf86-video-${VIDEO_DRIVER} ${VIDEO_DRIVER}-dri"
    if [[ ${ARCHI} == x86_64 ]]; then
      is_package_installed "lib32-catalyst-utils" && pacman -Rdds --noconfirm lib32-catalyst-utils
      package_install "lib32-${VIDEO_DRIVER}-dri"
    fi
    add_module "radeon" "ati"
  #}}}
  #Intel {{{
  elif [[ ${VIDEO_DRIVER} == intel ]]; then
    package_install "xf86-video-intel intel-dri libva-intel-driver"
    package_install "mesa-libgl"
    [[ ${ARCHI} == x86_64 ]] && package_install "lib32-mesa-libgl"
  #}}}
  #Vesa {{{
  else
    package_install "xf86-video-${VIDEO_DRIVER}"
    package_install "mesa-libgl"
    [[ ${ARCHI} == x86_64 ]] && package_install "lib32-mesa-libgl"
  fi
  #}}}
  pause_function
}
#}}}



git_clone() { #{{{
  #Clone github repositories
  reponame=${1}
  directory=${2}
  if [ -z $directory ]; then
    directory="$userhome/projects/$reponame"
  else
    directory="$userhome/$directory"
  fi

  print_title "Clone $reponame"
  rm -rf $directory

  su -c "cd $userhome && git clone https://github.com/jlesquembre/${reponame}.git $directory" $username
  su -c "cd $directory && git remote remove origin" $username
  su -c "cd $directory && git remote add origin git@github.com:jlesquembre/${reponame}.git" $username

  pause_function

} #}}}


ARCHI=`uname -m`

while true
do
  print_title "ARCHLINUX INSTALL"
  echo " 1) Add user"
  echo " 2) Basic Setup"
  echo " 3) Install extras"
  echo " 4) Install basic user configuration"
  echo " q) Quit"
  echo ""
  MAINMENU+=" q"
  read_input_options "$MAINMENU"
  for OPT in ${OPTIONS[@]}; do
    case "$OPT" in
      1)
        create_new_user
        ;;
      2)
        check_archlinux
        check_hostname
        check_connection
        check_pacman_blocked
        add_multilib
        system_upgrade
        configure_sudo
        pause_function
        ;;
      3)
        package_install "bash-completion"
        pause_function

        package_install "base-devel"
        pause_function

        package_install "ntp"
        is_package_installed "ntp" && timedatectl set-ntp true
        pause_function

        package_install "zip unzip unrar p7zip"
        pause_function

        package_install "alsa-utils alsa-plugins"
        [[ ${ARCHI} == x86_64 ]] && package_install "lib32-alsa-plugins"
        pause_function

        package_install "pulseaudio pulseaudio-alsa"
        [[ ${ARCHI} == x86_64 ]] && package_install "lib32-libpulse"
        # automatically switch to newly-connected devices
        add_line "load-module module-switch-on-connect" "/etc/pulse/default.pa"
        pause_function

        package_install "openssh"
        systemctl enable sshd
        pause_function

        package_install "xorg-server xorg-server-utils xorg-xinit"
        package_install "xf86-input-synaptics xf86-input-mouse xf86-input-keyboard"
        package_install "mesa"
        # package_install "gamin"
        KEYMAP=$(localectl status | grep Keymap | awk '{print $3}')
        localectl set-keymap ${KEYMAP}
        pause_function

        install_video_cards

        package_install "ttf-bitstream-vera ttf-dejavu ttf-freefont ttf-inconsolata ttf-hack"
        package_install "git tk aspell-en aspell-es rxvt-unicode rxvt-unicode-terminfo urxvt-perls fish"
        pause_function

        package_install "upower i3-wm i3lock dmenu rofi compton xorg-xwininfo"
        pause_function

        package_install "xfce4 xfce4-goodies"
        #package_install "gvfs gvfs-smb gvfs-afc lxpolkit"
        #package_install "xdg-user-dirs"
        #config_xinitrc "startxfce4"
        systemctl enable upower
        pause_function

        package_install "lightdm-gtk-greeter lightdm accountsservice"
        systemctl enable lightdm
        pause_function


        package_install "netctl dhcpcd ifplugd"
        #systemctl enable NetworkManager
        pause_function

        package_install "plasma-meta breeze-kde4 breeze-gtk kde-gtk-config"
        pause_function

        print_title "WIFI"
        read -p "Install wifi support? [y/N]: " OPT
        if [[ $OPT == "y" ]]; then
            package_install "wpa_actiond wpa_supplicant dialog"
            pause_function
        fi

        print_title "Intel Microcode update files for Intel CPUs"
        read -p "Install Intel CPU support? [y/N]: " OPT
        if [[ $OPT == "y" ]]; then
            package_install "intel-ucode"
            pause_function
        fi

        package_install "udevil notify-osd zenity gphoto2 conky python-setuptools lsb-release"
        pause_function

        package_install "ranger atool file w3m pass keychain rsync"
        pause_function

        package_install "gvim ctags the_silver_searcher tig"
        pause_function

        package_install "chromium firefox weechat"
        pause_function

        package_install "gst-plugins-base gst-plugins-base-libs gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav"
        package_install "gstreamer0.10 gstreamer0.10-plugins"
        pause_function

        package_install "amarok kid3-qt kdegraphics-okular"
        pause_function

        package_install "vlc mpv"
        pause_function

        package_install "autofs sshfs"
        pause_function

        package_install "ipython ethtool"
        pause_function

        package_install "haveged"
        systemctl enable haveged
        pause_function

        package_install "mariadb"
        #/usr/bin/mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
        #systemctl enable mysqld
        #systemctl start mysqld
        #/usr/bin/mysql_secure_installation
        pause_function

        ;;

      4)
        read -p "Username: " username
        if id -u $username >/dev/null 2>&1; then

            userhome=`su -c 'echo $HOME' $username`
            su -c "mkdir -p $userhome/projects" $username

            repos=( arch_install_script blog jlle doc2git invewrapper termite pytag )
            for repo in ${repos[@]}
            do
              git_clone $repo
            done

            git_clone vim .vim
            git_clone dotfiles dotfiles

            print_title "Create links"
            su -c "$userhome/dotfiles/create_links.sh" $username
            pause_function

            print_title "Generate SSH key"
            su -c "ssh-keygen -t rsa -b 2048" $username
            pause_function

            print_title "Build AUR packages"
            su -c "mkdir -p $userhome/aur" $username
            aur_pkgs=( python-pew google-talkplugin )
            for aur_pkg in ${aur_pkgs[@]}
            do
              su -c "cd $userhome/aur && fish -c \"aur_build $aur_pkg\"" $username
              pause_function
            done


        else
            print_line
            echo "User does not exist."
            pause_function
        fi
        ;;

      "q")
        exit 0
        ;;

      *)
        invalid_option
        ;;
    esac
  done
done
#}}}
