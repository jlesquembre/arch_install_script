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
    pacman -S ${PKG}
  done
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
            systemctl enable dhcpcd@${WIRED_DEV}.service
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
    sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers
  fi
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


while true
do
  print_title "ARCHLINUX ULTIMATE INSTALL - https://github.com/helmuthdu/aui"
  echo " 1) "Add user")"
  echo " 2) "Basic Setup")"
  echo ""
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
        system_upgrade
        configure_sudo
        ;;
      3)
        ;;

      "q")
        finish
        ;;
      *)
        invalid_option
        ;;
    esac
  done
done
#}}}
