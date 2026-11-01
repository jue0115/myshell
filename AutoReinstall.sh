#!/usr/bin/env bash

if (( EUID != 0 )); then
    command -v clear >/dev/null 2>&1 && clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

install_dependencies() {
  local packages=()
  command -v wget >/dev/null 2>&1 || packages+=(wget)
  command -v curl >/dev/null 2>&1 || packages+=(curl)
  ((${#packages[@]} == 0)) && return 0

  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "${packages[@]}"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "${packages[@]}"
  else
    echo "Error: wget and curl are required." >&2
    exit 1
  fi
}

install_dependencies

function CopyRight() {
  command -v clear >/dev/null 2>&1 && clear
  echo "########################################################"
  echo "#                                                      #"
  echo "#  Auto Reinstall Script                               #"
  echo "#                                                      #"
  echo "#  Author: hiCasper                                    #"
  echo "#  Blog: https://blog.hicasper.com/post/135.html       #"
  echo "#  Feedback: https://github.com/hiCasper/Shell/issues  #"
  echo "#  Last Modified: 2026-11-01                           #"
  echo "#                                                      #"
  echo "#  Supported by MoeClub                                #"
  echo "#                                                      #"
  echo "########################################################"
  echo -e "\n"
}

function isValidIp() {
  local ip=$1
  local ret=1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ip=(${ip//\./ })
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    ret=$?
  fi
  return $ret
}

function ipCheck() {
  isLegal=0
  for add in $MAINIP $GATEWAYIP $NETMASK; do
    isValidIp $add
    if [ $? -eq 1 ]; then
      isLegal=1
    fi
  done
  return $isLegal
}

function GetIp() {
  MAINIP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
  GATEWAYIP=$(ip -4 route show default 2>/dev/null | awk 'NR == 1 {print $3}')
  SUBNET=$(ip -o -4 addr show scope global 2>/dev/null | awk 'NR == 1 {sub(/.*\//, "", $4); print $4}')
  if [[ $SUBNET =~ ^[0-9]+$ ]] && (( SUBNET <= 32 )); then
    local value=$(( 0xffffffff ^ ((1 << (32 - SUBNET)) - 1) ))
    NETMASK="$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
  else
    NETMASK=''
  fi
}

function UpdateIp() {
  read -r -p "Your IP: " MAINIP
  read -r -p "Your Gateway: " GATEWAYIP
  read -r -p "Your Netmask: " NETMASK
}

function SetNetwork() {
  isAuto='0'
  if [[ -f '/etc/network/interfaces' ]];then
    [[ ! -z "$(sed -n '/iface.*inet static/p' /etc/network/interfaces)" ]] && isAuto='1'
    [[ -d /etc/network/interfaces.d ]] && {
      cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
      [[ "$cfgNum" -ne '0' ]] && {
        for netConfig in `ls -1 /etc/network/interfaces.d/*.cfg`
        do
          [[ ! -z "$(cat $netConfig | sed -n '/iface.*inet static/p')" ]] && isAuto='1'
        done
      }
    }
  fi

  if [[ -d '/etc/sysconfig/network-scripts' ]];then
    cfgNum="$(find /etc/sysconfig/network-scripts -maxdepth 1 -type f -name 'ifcfg-*' ! -name 'ifcfg-lo' |wc -l)" || cfgNum='0'
    [[ "$cfgNum" -ne '0' ]] && {
      for netConfig in /etc/sysconfig/network-scripts/ifcfg-*; do
        [[ -f "$netConfig" && "$netConfig" != *ifcfg-lo && "$netConfig" != *:* ]] || continue
        if grep -Eiq '^[[:space:]]*BOOTPROTO=(static|none|manual)' "$netConfig" ||
           grep -Eiq '^[[:space:]]*(IPADDR|PREFIX|NETMASK)=' "$netConfig"; then
          isAuto='1'
        fi
      done
    }
  fi
}

function NetMode() {
  CopyRight

  if [ "$isAuto" == '0' ]; then
    read -r -p "Use DHCP to configure network automatically? [Y/n]:" input
    case $input in
      [yY][eE][sS]|[yY]) NETSTR='' ;;
      [nN][oO]|[nN]) isAuto='1' ;;
      *) NETSTR='' ;;
    esac
  fi

  if [ "$isAuto" == '1' ]; then
    GetIp
    ipCheck
    if [ $? -ne 0 ]; then
      echo -e "Error occurred when detecting ip. Please input manually.\n"
      UpdateIp
    else
      CopyRight
      echo "IP: $MAINIP"
      echo "Gateway: $GATEWAYIP"
      echo "Netmask: $NETMASK"
      echo -e "\n"
      read -r -p "Confirm? [Y/n]:" input
      case $input in
        [yY][eE][sS]|[yY]) ;;
        [nN][oO]|[nN])
          echo -e "\n"
          UpdateIp
          ipCheck
          [[ $? -ne 0 ]] && {
            clear
            echo -e "Input error!\n"
            exit 1
          }
        ;;
        *) ;;
      esac
    fi
    NETSTR="--ip-addr ${MAINIP} --ip-gate ${GATEWAYIP} --ip-mask ${NETMASK}"
  fi
}

function RHELImageBootConf() {
  touch /tmp/bootconf.sh
  echo '#!/bin/sh'>/tmp/bootconf.sh
  printf "hostnamectl set-hostname '%s'\n" "$ORIGINAL_HOSTNAME" >>/tmp/bootconf.sh

  staticIp='1'
  if [ "$isAuto" == '1' ]; then
    echo -e "\n"
    read -r -p "Writing static ip to system? [Y/n]: " input
    case $input in
      [yY][eE][sS]|[yY]) staticIp='0' ;;
      *) staticIp='1' ;;
    esac
  fi

  if [ "$isAuto" == '1' ] && [ "$staticIp" == '0' ]; then
    cat >>/tmp/bootconf.sh <<EOF
if [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]; then
  sed -i 's/^BOOTPROTO=.*/BOOTPROTO=static/' /etc/sysconfig/network-scripts/ifcfg-eth0
  cat >> /etc/sysconfig/network-scripts/ifcfg-eth0 <<NETCFG
IPADDR=$MAINIP
NETMASK=$NETMASK
GATEWAY=$GATEWAYIP
DNS1=8.8.8.8
DNS2=8.8.4.4
NETCFG
fi
EOF
  fi
  cat >>/tmp/bootconf.sh <<EOF
if [ -f /etc/rc.d/rc.local.bak ]; then
  cp -f /etc/rc.d/rc.local.bak /etc/rc.d/rc.local
fi
rm -f /bootconf.sh
shutdown -r now
EOF
  sed -i '/sbin\/reboot/i\ sync; umount /mnt 2>\/dev\/null || true; root_part=""; for p in $(list-devices partition); do fs=$(blkid -o value -s TYPE "$p" 2>\/dev\/null); case "$fs" in ext2|ext3|ext4|xfs|btrfs) ;; *) continue;; esac; mount "$p" /mnt 2>\/dev\/null || continue; if [ -d /mnt/etc ]; then root_part="$p"; umount /mnt; break; fi; umount /mnt; done; [ -n "$root_part" ] || exit 1; mount "$root_part" /mnt; mkdir -p /mnt/etc/rc.d; [ -f /mnt/etc/rc.d/rc.local ] || printf "#!/bin/sh\\n" > /mnt/etc/rc.d/rc.local; cp -f /mnt/etc/rc.d/rc.local /mnt/etc/rc.d/rc.local.bak; chmod +x /mnt/etc/rc.d/rc.local; cp -f /bootconf.sh /mnt/bootconf.sh; chmod 755 /mnt/bootconf.sh; printf "\\n/bootconf.sh\\n" >> /mnt/etc/rc.d/rc.local; sync; umount /mnt; \\' /tmp/InstallNET.sh
  sed -i '/newc/i\cp -f \/tmp\/bootconf.sh \/tmp\/boot\/bootconf.sh'  /tmp/InstallNET.sh
  grep -Fq 'if [ -d /mnt/etc ]' /tmp/InstallNET.sh || {
    echo "Error: downloaded InstallNET.sh is incompatible with DD boot configuration." >&2
    exit 1
  }
}

function PreserveHostname() {
  local installer=${1:-/tmp/InstallNET.sh} label
  local -a labels
  ORIGINAL_HOSTNAME=$(hostname) || return 1
  if [[ -z $ORIGINAL_HOSTNAME || ${#ORIGINAL_HOSTNAME} -gt 253 || $ORIGINAL_HOSTNAME == *. ]]; then
    echo "Error: invalid current hostname: $ORIGINAL_HOSTNAME" >&2
    return 1
  fi
  IFS=. read -r -a labels <<< "$ORIGINAL_HOSTNAME"
  for label in "${labels[@]}"; do
    if [[ ! $label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
      echo "Error: invalid current hostname: $ORIGINAL_HOSTNAME" >&2
      return 1
    fi
  done
  local short_name=${ORIGINAL_HOSTNAME%%.*} domain=''
  [[ $ORIGINAL_HOSTNAME == *.* ]] && domain=${ORIGINAL_HOSTNAME#*.}
  if ! grep -Fq 'hostname=$linux_relese domain=$linux_relese' "$installer" ||
     ! grep -q '^d-i netcfg/choose_interface ' "$installer"; then
    echo "Error: InstallNET.sh hostname configuration has changed." >&2
    return 1
  fi
  sed -i "s/hostname=\$linux_relese domain=\$linux_relese/hostname=$short_name domain=$domain/g" "$installer" || return 1
  # netcfg/hostname overrides names supplied by DHCP or reverse DNS.
  sed -i "/^d-i netcfg\/choose_interface /i\\d-i netcfg/get_hostname string $short_name\nd-i netcfg/get_domain string $domain\nd-i netcfg/hostname string $ORIGINAL_HOSTNAME" "$installer"
}

function Start() {
  CopyRight

  isCN='0'
  geo=$(curl -fsSL -m 10 https://ipinfo.io/json 2>/dev/null | grep '"country": "CN"' || true)
  if [[ "$geo" != "" ]];then
    isCN='1'
  fi

  if [ "$isAuto" == '0' ]; then
    echo "Network Type: DHCP"
  else
    echo "IP: $MAINIP"
    echo "Gateway: $GATEWAYIP"
    echo "Netmask: $NETMASK"
  fi

  [[ "$isCN" == '1' ]] && echo "Location: Domestic"

  if [ -f "/tmp/InstallNET.sh" ]; then
    rm -f /tmp/InstallNET.sh
  fi
  if ! curl -fsSL -o /tmp/InstallNET.sh 'https://fastly.jsdelivr.net/gh/hiCasper/Shell@latest/InstallNET.sh'; then
    echo "Error: failed to download InstallNET.sh." >&2
    exit 1
  fi
  chmod 755 /tmp/InstallNET.sh
  PreserveHostname || exit 1
  echo "Hostname after reinstall: $ORIGINAL_HOSTNAME"
  #curl -sSL -o /tmp/InstallNET.sh 'https://cdn.jsdelivr.net/gh/MoeClub/Note@latest/InstallNET.sh' && chmod a+x /tmp/InstallNET.sh

  CMIRROR=''
  CVMIRROR=''
  DMIRROR=''
  UMIRROR=''
  if [[ "$isCN" == '1' ]];then
    CMIRROR="--mirror http://mirrors.cloud.tencent.com/centos"
    CVMIRROR="--mirror http://mirrors.cloud.tencent.com/centos-vault"
    DMIRROR="--mirror https://mirrors.cloud.tencent.com/debian"
    UMIRROR="--mirror https://mirrors.cloud.tencent.com/ubuntu"
  fi

  sed -i 's|\$1\$4BJZaD0A\$y1QykUnJ6mXprENfwpseH0|\$1\$7R4IuxQb\$J8gcq7u9K0fNSsDNFEfr90|' /tmp/InstallNET.sh

  if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE='UEFI'
  else
    BOOT_MODE='BIOS/Legacy'
  fi
  echo "Firmware mode: $BOOT_MODE"

  echo -e "\nPlease select an OS:"
  echo "  1) CentOS 7.8 (DD Image)"
  echo "  2) CentOS 7.6 (DD Image, ServerSpeeder Avaliable)"
  echo "  3) Debian 9"
  echo "  4) Debian 10"
  echo "  5) Debian 11"
  echo "  6) Debian 12 (Bookworm)"
  echo "  7) Debian 13 (Trixie)"
  echo "  8) Ubuntu 16.04"
  echo "  9) Ubuntu 18.04"
  echo " 10) Ubuntu 20.04"
  echo "  0) Exit"
  echo -ne "\nYour option: "
  read N
  case $N in
    1) echo -e "\nPassword: Pwd@CentOS\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh $NETSTR -dd 'https://api.moetools.net/get/centos-78-image' $DMIRROR ;;
    2) echo -e "\nPassword: Pwd@CentOS\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/InstallNET.sh $NETSTR -dd 'https://api.moetools.net/get/centos-76-image' $DMIRROR ;;
    3) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -d 9 -v 64 -a $NETSTR $DMIRROR ;;
    4) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -d 10 -v 64 -a $NETSTR $DMIRROR ;;
    5) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -d 11 -v 64 -a $NETSTR $DMIRROR ;;
    6) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -d bookworm -v 64 -a $NETSTR $DMIRROR ;;
    7) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -d trixie -v 64 -a $NETSTR $DMIRROR ;;
    8) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -u 16.04 -v 64 -a $NETSTR $UMIRROR ;;
    9) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -u 18.04 -v 64 -a $NETSTR $UMIRROR ;;
   10) echo -e "\nPassword: Pwd@Linux\n"; read -s -n1 -p "Press any key to continue..."; bash /tmp/InstallNET.sh -u 20.04 -v 64 -a $NETSTR $UMIRROR ;;
    0) exit 0;;
    *) echo "Wrong input!"; exit 1;;
  esac
}

SetNetwork
NetMode
Start
