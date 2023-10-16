#!/usr/bin/env sh
# https://github.com/dennypage/dpinger
LOG_PREFIX="vpnserver.sh"
LOG_FILE=/var/log/vpnserver.log
source /common.sh

# Global Variables
# This is a multi-tenant init script
# Tenant configuration is mounted to this directory
DATA_DIR=${DATA_DIR:-/data}
# SE VPN runtime directory
VPN_DIR=${VPN_DIR:-/sevpn}
VPN_CMD=${VPN_DIR}/vpncmd

# Tenant Variables
VPN_SERVER_PORT=${VPN_SERVER_PORT:-5555}
VPN_SERVER_HOST=${VPN_SERVER_HOST:-localhost}
VPN_TENANT=${VPN_TENANT:-"default"}

EXTERNAL_IP=""

# Utility Functions
function vpn_tools() {
  ${VPN_CMD} /TOOLS /CMD:$*
}

function vpn_server_cmd() {
  ${VPN_CMD} ${VPN_SERVER_HOST}:${VPN_SERVER_PORT} /SERVER /PASSWORD:$(cat ${DATA_DIR}/admin.txt) $@ &> ${DATA_DIR}/vpncmd_server.log
}

function vpn_server_cmd_nopass() {
  ${VPN_CMD} ${VPN_SERVER_HOST}:${VPN_SERVER_PORT} /SERVER $@ &> ${DATA_DIR}/vpncmd_server.log
}

# Init Functions
function prepare_runtime() {
  local cmd_file=${DATA_DIR}/init.cmd

  if [ ! -d ${DATA_DIR} ] ; then
    _die "${DATA_DIR} not found. Start container with a /data mount."
  fi

  # VPN Server Config
  local server_conf=${DATA_DIR}/vpn_server.config
  if [ ! -r ${server_conf} ] ; then
    _warn "${server_conf} not found. Default setting is used."
    touch ${server_conf}
  fi
  ln -s ${server_conf} ${VPN_DIR}/vpn_server.config

  # Language Config
  local lang_conf=${DATA_DIR}/lang.conf
  if [ ! -r ${lang_conf} ] ; then
    _warn "${lang_conf} not found. Default setting is used."
    echo "en" > ${lang_conf}
  fi
  ln -s ${lang_conf} ${VPN_DIR}/lang.conf

  # Allow localhost only Admin login
  local adminip=${DATA_DIR}/adminip.txt
  if [ ! -r ${adminip} ] ; then
    _warn "${adminip} not found. Allow Admin logins only from localhost."
    echo -e "127.0.0.1\n::1\n" > ${adminip}
  fi
  ln -s ${adminip} ${VPN_DIR}/adminip.txt

  local chain_certs=${DATA_DIR}/chain_certs
  if [ ! -d ${chain_certs} ] ; then
    _warn "${chain_certs} not found. Empty directory is used."
    mkdir ${chain_certs}
  fi
  ln -s ${chain_certs} ${VPN_DIR}/chain_certs

  local packet_log=${DATA_DIR}/packet_log
  if [ ! -d ${packet_log} ] ; then
    mkdir ${packet_log}
  fi
  ln -s ${packet_log} ${VPN_DIR}/packet_log
  
  local security_log=${DATA_DIR}/security_log
  if [ ! -d ${security_log} ] ; then
    mkdir ${security_log}
  fi
  ln -s ${security_log} ${VPN_DIR}/security_log
  
  local server_log=${DATA_DIR}/server_log
  if [ ! -d ${server_log} ] ; then
    mkdir ${server_log}
  fi
  ln -s ${server_log} ${VPN_DIR}/server_log
  
  local server_conf_backup
  if [ ! -d ${server_conf_backup} ] ; then
    mkdir ${server_conf_backup}
  fi
  ln -s ${server_conf_backup} ${VPN_DIR}/backup.vpn_server.config

  if [ -r ${cmd_file} ] ; then
    rm ${cmd_file}
  fi
}

function check_vpn_server() {
  local vpn_version=$(vpn_tools About | grep Version | head -1)
  _info "VPN Server Version: ${vpn_version}"

  vpn_tools Check &> ${DATA_DIR}/server_check.log
  if [ $? -gt 0 ] ; then
    _die "Server check failed. Verbose output in ${DATA_DIR}/server_check.log"
  fi
}

function get_external_ip() {
  EXTERNAL_IP=$(curl -s --max-time 5.5 ifconfig.me)
  echo $EXTERNAL_IP > ${DATA_DIR}/external_ip.txt
  _info "VPN Server External Address: $EXTERNAL_IP"
}

# Custom Init Functions
function prerun() {
  if [ -r ${DATA_DIR}/prerun.sh ] ; then
    _info "Prerun script found. Running..."
    source ${DATA_DIR}/prerun.sh
  fi
}

# function postrun() {
#   if [ -r ${DATA_DIR}/postrun.sh ] ; then
#     _info "Postrun script found. Running..."
#     source ${DATA_DIR}/postrun.sh
#   fi
# }

function admin_password() {
  local admin=${DATA_DIR}/admin.txt
  local cmd_file=${DATA_DIR}/password.cmd

  if [ -r ${cmd_file} ] ; then
    rm ${cmd_file}
  fi

  if [ -r ${admin} ] ; then
    VPN_PASSWORD=$(cat ${admin})
    if [ "${VPN_PASSWORD}x" != "x" ] ; then
      _info "VPN Adminstrator Password: ${VPN_PASSWORD}"
      return
    fi
  fi

  VPN_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
  echo -e "ServerPasswordSet $VPN_PASSWORD\nFlush\n" > ${cmd_file}
  echo "$VPN_PASSWORD" > $admin
  _info "New VPN Adminstrator Password: ${VPN_PASSWORD}"
}

function init_network() {
  mkdir /dev/net
}

function init_certificate() {
  local key_file=${DATA_DIR}/server.key
  local crt_file=${DATA_DIR}/server.crt
  local cmd_file=${DATA_DIR}/init.cmd

  if [ -r ${cmd_file} ] ; then
    rm ${cmd_file}
  fi

  if [ ! -r $key_file ] || [ ! -r $crt_file ] ; then
    _warn "Server certificate not found. Using defaults."
    return
  fi

  echo -e "ServerCertSet /LOADCERT:${crt_file} /LOADKEY:${key_file}\nFlush\n"  >> ${cmd_file}
  _info "VPN Server Certificate:"
  openssl x509 -in ${crt_file} -text -noout
}

function init_wireguard() {
  local key_file=${DATA_DIR}/wg_key.txt
  local psk_file=${DATA_DIR}/wg_psk.txt
  local cmd_file=${DATA_DIR}/init.cmd
  local is_cmd=false

  if [ -r ${cmd_file}  ] ; then
    rm ${cmd_file}
  fi

  if [ ! -r ${key_file} ] ; then
      vpn_tools GenX25519 > ${key_file}
      _warn "New Wireguard key created"
      is_cmd=true
  fi

  if [ ! -r ${psk_file} ] ; then
      vpn_tools GenX25519 > ${psk_file}
      _warn "New Wireguard psk created"
      is_cmd=true
  fi

  local key=$(cat ${key_file} | grep Private | cut -d " " -f 3)
  local pub=$(cat ${key_file} | grep Public | cut -d " " -f 3)
  local psk=$(cat ${psk_file} | grep Private | cut -d " " -f 3)

  if $is_cmd ; then
    cat >> ${cmd_file} <<EOF
ProtoOptionsSet wireguard /NAME:Enabled /VALUE:True
ProtoOptionsSet wireguard /NAME:PrivateKey /VALUE:$key
ProtoOptionsSet wireguard /NAME:PresharedKey /VALUE:$psk
Flush
EOF
  fi

  _info " Wireguard Public Key: $pub"
  _info "        Wireguard PSK: $psk"
}

function tail_server_log() {
  local log_file=$(ls -r ${VPN_DIR}/server_log/vpn_*.log | head -1)
  _info "Server Log: $log_file"
  tail -f -n +1  $log_file
}

function clear_log() {
  local log_file=$(ls -r ${VPN_DIR}/server_log/vpn_*.log 2> /dev/null | head -1)
  if [ ! -z "$log_file" ] ; then
    echo -n "" > $log_file
  fi
}

function exec_vpnserver_bin() {

  clear_log

  _info "VPN Server Address: ${EXTERNAL_IP}:${VPN_SERVER_PORT}"
  _info "VPN Tenant: $VPN_TENANT"

  cd ${VPN_DIR}
  exec ./vpnserver execsvc
}

function start_vpnserver_bin() {
  clear_log

  _info "VPN Server Address: ${EXTERNAL_IP}:${VPN_SERVER_PORT}"
  _info "VPN Tenant: $VPN_TENANT"

  cd ${VPN_DIR}
  ./vpnserver start
}

function stop_vpnserver_bin() {
  cd ${VPN_DIR}
  ./vpnserver stop
}


function init_vpnserver() {
  local cmd_file=${DATA_DIR}/init.cmd
  local password_cmd=${DATA_DIR}/password.cmd

  # while true ; do
  #   _info "Waiting for the VPN Server to be online..."
  #   netstat -tpane | grep 5555 &> /dev/null
  #   if [ $? -gt 0 ] ; then
  #       sleep 2
  #   else
  #     break
  #   fi
  # done

  # echo -e "SyslogEnable 3 /HOST:localhost:514\nFlush\n" > ${cmd_file}

  if [ -r ${password_cmd} ] ; then
    vpn_server_cmd_nopass /IN:${password_cmd} &> /dev/null
    _info "Administrator password set"
  fi

  if [ -r ${cmd_file} ] ; then
    vpn_server_cmd /IN:${cmd_file} &> /dev/null
  fi

  _info "VPN Server initialization finished"
}

function usage() {
  _info "TODO"
}

function start_vpnserver() {
  prerun

  prepare_runtime
  check_vpn_server

  init_network

  get_external_ip
  admin_password
  init_certificate
  init_wireguard

  # exec_vpnserver_bin
  start_vpnserver_bin
  sleep 1
  init_vpnserver
}

function check_server_info() {
  vpn_server_cmd "ServerInfoGet"
}

function main() {
  local action=${1:---start}
  _info "Action: $action"

  if [ "${action}" == "--start" ] ; then
    start_vpnserver
    exit $?
  fi

  if [ "${action}" == "--stop" ] ; then
    stop_vpnserver_bin
    exit $?
  fi

  if [ "${action}" == "--restart" ] ; then
    stop_vpnserver_bin
    sleep 1
    start_vpnserver
    exit $?
  fi
}

main $* 2>&1 | tee -a $LOG_FILE
