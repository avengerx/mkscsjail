#!/bin/bash

runner_user=steam_runner
updater_user=steam_updater

usercachefile="/tmp/steamusercache.dat"

jaildir="./scsjail"
atsjaildir="atsd"
etsjaildir="ets2d"
datadir="var/lib"
u_upd="scsup"
u_run="scsrun"
u_grp="scs"
bind_ip="any"
numa_enable=false
numa_nodes=""
numa_cpus=""
numa_hardware_cpus=()

sppath="."
scsgame="both"
sv_desc="This server was set up using mkscsjail.sh"
sv_name="chRoot-jailed Dedicated Server"
sv_welcome="Be polite and respectful to fellow truckers."
sv_pass=""
sv_port="27015"
sv_token="" # [ats,ets2]
sv_mods=""
sv_pdmg="true"
sv_traffic="true"
sv_cmp_hide="false"
sv_hide_coll="true"
sv_svc_nocoll="false"
sv_menu_ghost="false"
sv_speedlim="false,true" # ats,ets2
sv_optmods="true"
sv_tzs=2
sv_max_vehicles=160
sv_max_controllable_vehicles=80
sv_max_spawnable_vehicles=20
sv_vport=100
sv_nametags=false

steamcliurl="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
atsgid="2239530"
atsbinpath="bin/linux_x64/amtrucks_server"
atsprettyname="American Truck Simulator"
atsdatadir="${datadir}/${atsprettyname}"
etsgid="1948160"
etsbinpath="bin/linux_x64/eurotrucks2_server"
etsprettyname="Euro Truck Simulator 2"
etsdatadir="${datadir}/${etsprettyname}"

# Optional, by steamcmd to handle locales
# Not sure where this should be in every system. The path below
# applies to Gentoo 17.0.
locale_path="/usr/lib64/locale/locale-archive"

# Required by steamcmd to connect to steam's HTTPS endpoints
sslcerts_path="/etc/ssl/certs"

# make a synlink from /bin to steamcmd within its install location
binlnk=(steam/linux32/steamcmd)

# libraries that are not shown by ldd but are required by the apps, somehow.
lib32=(libcurl.so)
lib64=(ld-linux.so.2 ld-linux-x86-64.so.2)
libcommon=(libnss_dns.so.2 libnss_files.so.2)

# symlinks to solibs in steam/game paths to avoid LD_LIBRARY_PATH pollution
lib32lnk=(
  steam/linux32/crashhandler.so
  steam/linux32/libstdc++.so.6
  steam/linux32/libtier0_s.so
  steam/linux32/libvstdlib_s.so
  steam/linux32/steamclient.so
  steam/linux32/steamconsole.so
)
lib64lnk=( steam/linux64/steamclient.so )

# files, types major-minor for required files in /dev (created via mknod)
devfiles=("random:c:1:8" "urandom:c:1:9")

steamidcache=()
steamnamecache=()
steamurlcache=()
iplist=()

_ifs="${IFS}"

function fail() {
  >&2 echo "fatal: ${1}
at ${BASH_SOURCE[${2:-1}]}:${BASH_LINENO[${2:-1}-1]} (${FUNCNAME[${2:-1}]}())"
  exit 1
}

function failnl() {
  echo "${1:-failed.}"
  fail "${2}" 2
}

function showhelp() {
  echo "usage: ${0} <flags> <server-parameters>

Flags:
  --jaildir=[path]
    Directory where to set up the jail files in. If the directory doesn't
    exist, it will be created.
    Default: ${jaildir}

  --bind=<ip:interface>
    Binds the server to the specific IP address and interface.
    Format: x.y.z.k nic0
    E.g.: 192.168.0.2:eth0
    Default: any (bind to all IPs in all interfaces)

  --numa-cpu=<physical cpu>
    Binds the server to specific physical CPU.
    Default: empty (disable NUMA).
    If you specify this, the CPU cores must be specified via --numa-cores.

  --numa-cores=<CPU cores index interval>
    Binds the server to specific CPU cores in the selected physical CPUs.
    Example: --numa-cores=14-17,34-37
    Default: empty (disable NUMA).
    If you specify this, the physical CPUs must be specified via --numa-cpus.

  --game=[ats|ets2|both]
    Specifies which game to set up in the jail; either American Truck
    Simulator or Euro Truck Simulator 2; or just both games.
    Overrides any --both, --ets or --ats specified previously.
    Default: ${scsgame}

  --ats, --amtrucks
    Specifies American Truck Simulator only should be set up in the jail.
    Overrides any --both, --ets or --game specified previously.

  --ets, --ets2, --eutrucks
    Specifies Euro Truck Simulator 2 only should be set up in the jail.
    Overrides any --both, --ats or --game specified previously.

  --both, --bothgames
    Specifies both games should be set up in the jail.
    Overrides any --ets, --ats or --game specified previously.

  --server-packages=<path>
  --sp=<path>
    Path to the server_packages.{dat,sii} files required to run the server.
    More information about server packages files at:
    https://modding.scssoft.com/wiki/Documentation/Tools/Dedicated_Server

  --server-packages-path=<path>
    Path to search for game's server_packages.sii and server_packages.dat.
    Will search in own directory if only either game is selected or,
    respectively, inside ats/ and ets2/ if not found or if both games are to
    be set up. Information on how to generate the files at:
    https://modding.scssoft.com/wiki/Documentation/Tools/Dedicated_Server

Server Parameters:
    Server parameters will be shared by both games if both are set up in the
    jail except, by default, the speed limiter is disabled
    for ATS and enabled for ETS2.

  --load-config=<path>
  --lc=<path>
    Loads intial server configuration parameters from .sii file.
    This will override any server parameter passed before in the command line.

  --sv-desc=<description>
  --svd=<description>
    Server's description. Maximum length: 63 characters.
    Default: ${sv_desc}

  --sv-name=<name>
  --svn=<name>
    Server name in lobby listing. Maximum length: 63 characters.
    Default: ${sv_name}

  --sv-welcome=<message>
  --svw=<message>
    Server welcome message. Maximum length: 127 characters.
    Default: ${sv_welcome}

  --sv-pass=[password]
  --svpw=[password]
    Server password. Empty for no password. Maximum 63 characters.
    Default: empty (no password).

  --sv-port=<1025-65535>
  --svpt=<1025-65535>
    Server base port. Default is 27015 and it will also allocate the next
    port for the query. E.g. if you choose 12300 as the port, 12301 will
    be assigned to the server query listening socket.
    Default: ${sv_port}

  --sv-virtual-port=<value>
  --svcvp=<value>
    Server virtual base port. Similarly to --sv-port, the query port will
    be this value + 1.
    Default: ${sv_vport}

  --sv-logon-token=[steam server logon token]
  --svlt=[steam server logon token]
    Steam game server account's login token, created at:
    https://steamcommunity.com/dev/managegameservers
    Your steam account need not to be limited in order to create one,
    and you must use the _game_ App Id (ats=270880, ets2=227300)
    corresponding to the game server when registering the token.
    If installing both games, use [ats,ets2] comma-separated values
    to provide both tokens. Empty may work by creating non-persistent
    server Id, but it may not work as well.

  --sv-modlist=[comma-separated list of Steam IDs]
  --svml=[comma-separated list of Steam IDs]
    List of Steam ID of game moderators. Game moderators can kick, ban
    change the welcome message, rain probability and time of day.
    Default: empty

  --sv-player-damage=<true|false>
  --svpd=<true|false>
    Whether players can receive damage from other players' collisions.
    Default: ${sv_pdmg}

  --sv-traffic=<true|false>
  --svt=<true|false>
    Whether AI traffic in game is enabled.
    Default: ${sv_traffic}

  --sv-hide-in-companies=<true|false>
  --svhic=<true|false>
    Hide players whilst within company patios.
    Default: ${sv_cmp_hide}

  --sv-service-no-collision=<true|false>
  --svsnc=<true|false>
    Disable collisions for players in service shops.
    Default: ${sv_svc_nocoll}

  --sv-menu-no-collision=<true|false>
  --svmnc=<true|false>
    Disable collisions for players outside the game world
    (in menu, maps, jobs, also known as menu ghosting).
    Default: ${sv_menu_ghost}

  --sv-hide-colliding=<true|false>
  --svhc=<true|false>
    Hide colliding vehicles after teleport.
    Default: ${sv_hide_coll}

  --sv-force-speedlim=<true|false>
  --svfs=<true|false>
    Force truck speed limiter regardless of user settings. If false, whatever
    the player sets up is allowed. If true, will enforce the game's speed
    limiter settings.
    Default: ${sv_speedlim} (ats, ets2)

  --sv-optional-mods=<true|false>
  --svom=<true|false>
    Enable optional mods. If true, will not require players to have mods which
    manifest claims being optional. If false, all mods will be required to allow
    players to join.

  --sv-timezones=<0|1|2>, --svtz=<0|1|2>
    Set in-game time zone simulation. Not sure if this even works.
    Default: ${sv_tzs}

  --sv-name-tags=<true|false>
  --svnt=<true|false>
    Whether to show player Steam names floating above their trucks.
    Default: ${sv_nametags}

  --sv-max-vehicles=<value>
  --svmv=<value>
    Maximum amount of vehicles overall in the server.
    Default: ${sv_max_vehicles}

  --sv-max-ai-vehicles-player=<value>
  --svmaivp=<value>
    Maximum number of a given player's AI vehicles.
    Default: ${sv_max_controllable_vehicles}

  --sv-max-ai-vehicles-player-spawn=<value>
  --svmavps=<value>
    Maximum amount of vehicles a player can spawn at a time.
    Default: ${sv_max_spawnable_vehicles}"
}

function cf_boolchk() {
  local handle="${1}" value="${2}"

  if [[ ! "${value}" =~ ^(false|true)$ ]]; then
    echo "invalid."
    fail "Boolean config '${handle}' in invalid format: ${value}" 2
  fi
}

function cf_numchk() {
  local handle="${1}" value="${2}" minval="${3}" maxval="${4}"

  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "invalid."
    fail "Numeric config '${handle}' in invalid format: ${value}" 2
  elif [ "${value}" -lt "${minval}" -o "${value}" -gt "${maxval}" ]; then
    echo "out of range."
    fail "Numeric config '${handle}' outside [${minval}:${maxval}] range: ${value}" 2
  fi
}

function cf_strchk() {
  local handle="${1}" value="${2}" minlen="${3}" maxlen="${4}"

  if [[ ! "${value}" =~ ^\"[^\"]{${minlen},${maxlen}}\"$ ]]; then
    echo "invalid."
    fail "String config '${handle}' in invalid format: ${value}" 2
  fi
}

function loadconfig() {
  local cf="${1}" lines line handle value foundcnt=0 modcnt=0

  if [ ! -f "${cf}" ]; then
    fail "specified path does not exist or is not a file."
  fi

  echo -n "Config file: ${cf}
Loading server config from file: "

  IFS=$'\n'
  lines=($(cat "${cf}"))
  IFS="${_ifs}"

  echo -n "${#lines[@]} lines, "

  # We don't count empty lines (bash limitation) and consider a file with
  # zero moderators
  if [ ${#lines[@]} -lt 31 ]; then
    echo "too few."
    fail "The specified config file has too few lines to be a valid configuration file."
  elif [ ${#lines[@]} -gt 100 ]; then
    # one may want to raise this limit if they do have a huuge list of moderators (>~70)
    echo "too many."
    fail "The specified config file has too many lines to be a valid configuration file."
  fi

  sv_mods=""
  for line in "${lines[@]}"; do
    if [[ "${line}" =~ ^\ *([a-z][a-z_]+(|\[[0-9]+\])):\ *(true|false|\"[^\"]*\"||[a-fA-F0-9]+)$ ]]; then
      handle="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[3]}"

      case "${handle}" in
        lobby_name) # "chRoot-jailed Dedicated Server"
          cf_strchk "${handle}" "${value}" 4 63
          sv_name="${value:1:-1}";;
        description) # "This server was set up using mkscsjail.sh"
          cf_strchk "${handle}" "${value}" 4 63
          sv_desc="${value:1:-1}";;
        welcome_message) # "Be polite and respectful to fellow truckers."
          cf_strchk "${handle}" "${value}" 4 127
          sv_welcome="${value:1:-1}";;
        password) # ""
          cf_strchk "${handle}" "${value}" 0 63
          sv_pass="${value:1:-1}";;
        max_players) # 8
          ;; # unused, we always allow 8 players.
        max_vehicles_total) # 160
          cf_numchk "${handle}" "${value}" 1 500
          sv_max_vehicles="${value}";;
        max_ai_vehicles_player) # 80
          cf_numchk "${handle}" "${value}" 1 500
          sv_max_controllable_vehicles="${value}";;
        max_ai_vehicles_player_spawn) # 20
          cf_numchk "${handle}" "${value}" 1 500
          sv_max_spawnable_vehicles="${value}";;
        connection_virtual_port) # 102
          cf_numchk "${handle}" "${value}" 100 199
          sv_vport="${value}";;
        query_virtual_port) # 103
          ;; # unused, always sv_vport+1
        connection_dedicated_port) # 27015
          if [ "${scsgame}" == "both" ]; then
            cf_numchk "${handle}" "${value}" 1024 65532
          else
            cf_numchk "${handle}" "${value}" 1024 65534
          fi
          sv_port="${value}";;
        query_dedicated_port) # 27016
          ;; # unused, always sv_port+1
        server_logon_token) # 747C798B146FDBDB0E8C0337AD6AD1FE
          if [[ ! "${value}" =~ ^[0-9A-F]{32}$ ]]; then
            echo "invalid."
            fail "Token config '${handle}' in invalid format: ${value}"
          fi
          sv_token="${value}";;
        player_damage) # true
          cf_boolchk "${handle}" "${value}"
          sv_pdmg="${value}";;
        traffic) # true
          cf_boolchk "${handle}" "${value}"
          sv_traffic="${value}";;
        hide_in_company) # false
          cf_boolchk "${handle}" "${value}"
          sv_cmp_hide="${value}";;
        hide_colliding) # true
          cf_boolchk "${handle}" "${value}"
          sv_hide_coll="${value}";;
        force_speed_limiter) # false
          cf_boolchk "${handle}" "${value}"
          sv_speedlim="${value},${value}";;
        mods_optioning) # true
          cf_boolchk "${handle}" "${value}"
          sv_optmods="${value}";;
        timezones) # 2
          cf_numchk "${handle}" "${value}" 0 2
          sv_tzs="${value}";;
        service_no_collision) # false
          cf_boolchk "${handle}" "${value}"
          sv_svc_nocoll="${value}";;
        in_menu_ghosting) # false
          cf_boolchk "${handle}" "${value}"
          sv_menu_ghost="${value}";;
        name_tags) # false
          cf_boolchk "${handle}" "${value}"
          sv_nametags="${value}";;
        friends_only) # false
          ;; # ignored, it is not used in dedicated servers
        show_server) # true
          ;; # ignored, it is not used in dedicated servers
        moderator_list) # 1
          ;; # unused, we'll extract the count from how many moderator_list[i] we read
        moderator_list\[*\]) # 76561198025217746
          if [[ ! "${value}" =~ ^7656[0-9]{13}$ ]]; then
            echo "invalid."
            fail "Steam ID in config '${handle}' in invalid format: ${value}"
          fi
          modcnt="$(( 10#${modcnt} + 1 ))"
          if [ ${#sv_mods} -eq 0 ]; then
            sv_mods="${value}";
          else
            sv_mods="${sv_mods},${value}"
          fi;;
        *) fail "Unsupported setting in config file: ${handle}";;
      esac

      foundcnt=$(( 10#${foundcnt} + 1))
    fi
  done

  echo -n "${foundcnt} vars, ${modcnt} mods, "

  if [ ${foundcnt} -eq 0 ]; then
    echo "too few."
    fail "The specified config file had no valid configuration lines."
  fi

  echo "done."

  if [ ${sv_max_controllable_vehicles} -gt ${sv_max_vehicles} ]; then
    echo "Warning: Max controllable vehicles (${sv_max_controllable_vehicles}) > max vehicles (${sv_max_vehicles}).
Adjusting it."
    sv_max_controllable_vehicles="${sv_max_vehicles}"
  fi

  if [ ${sv_max_spawnable_vehicles} -gt ${sv_max_controllable_vehicles} ]; then
    echo "Warning: Max spawnable vehicles (${sv_max_spawnable_vehicles}) > max controllable vehicles (${sv_max_controllable_vehicles}).
Adjusting it."
    sv_max_spawnable_vehicles="${sv_max_controllable_vehicles}"
  fi
}

interactive=false
for arg in "${@}"; do
  case "${arg}" in
    --jaildir=*) jaildir="${arg#*=}";;
    --bind=*) bind_ip="${arg#*=}";;
    --numa-cpu=*) numa_nodes="${arg#*=}";;
    --numa-cores=*) numa_cpus="${arg#*=}";;
    --game=*) scsgame="${arg#*=}";;
    --ats|--amtrucks) scsgame="ats";;
    --ets|--ets2|--eutrucks) scsgame="ets2";;
    --both|--bothgames) scsgame="both";;
    --server-packages=*|--sp=*) sppath="${arg#*=}";;
    --load-config=*|--lc=*) loadconfig "${arg#*=}";;
    --sv-desc=*|--svd=*) sv_desc="${arg#*=}";;
    --sv-name=*|--svn=*) sv_name="${arg#*=}";;
    --sv-welcome=*|--svw=*) sv_welcome="${arg#*=}";;
    --sv-pass=*|--svpw=*) sv_pass="${arg#*=}";;
    --sv-port=*|--svpt=*) sv_port="${arg#*=}";;
    --sv-logon-token=*|--svlt=*) sv_token="${arg#*=}";;
    --sv-modlist=*|--svml=*) sv_mods="${arg#*=}";;
    --sv-player-damage=*|--svpd=*) sv_pdmg="${arg#*=}";;
    --sv-traffic=*|--svt=*) sv_traffic="${arg#*=}";;
    --sv-hide-in-companies=*|--svhic=*) sv_cmp_hide="${arg#*=}";;
    --sv-service-no-collision=*|--svsnc=*) sv_svc_nocoll="${arg#*=}";;
    --sv-menu-no-collision=*|--svmnc=*) sv_menu_ghost="${arg#*=}";;
    --sv-hide-colliding=*|--svhc=*) sv_hide_coll="${arg#*=}";;
    --sv-force-speedlim=*|--svfs=*) sv_speedlim="${arg#*=}";;
    --sv-optional-mods=*|--svom=*) sv_optmods="${arg#*=}";;
    --sv-timezones=*|--svtz=*) sv_tzs="${arg#*=}";;
    --sv-name-tags=*|--svnt=*) sv_nametags="${arg#*=}";;
    --sv-max-vehicles=*|--svmv=*) sv_max_vehicles="${arg#*=}";;
    --sv-max-ai-vehicles-player=*|--svmaivp=*) sv_max_controllable_vehicles="${arg#*=}";;
    --sv-max-ai-vehicles-player-spawn=*|--svmavps=*) sv_max_spawnable_vehicles="${arg#*=}";;
    --sv-virtual-port=*|--svvp=*) sv_vport="${arg#*=}";;
    --help) showhelp; exit 0;;
    *) echo "Invalid argument: ${arg}"; echo "For usage, run: ${0} --help"; exit 1;;
  esac
done

function aoeval() {
  local value="${1}"
  local ats="${2}"

  if [ "${value}" != "${value//,}" ]; then
    if ${ats}; then
      echo "${value%,*}"
    else
      echo "${value#*,}"
    fi
  else
    echo "${value}"
  fi
}

function atsval() { aoeval "${1}" true; }
function etsval() { aoeval "${1}" false; }

function enadis() {
  if ${1}; then
    echo "enabled"
  else
    echo "disabled"
  fi
}

function toggle() {
  if ${1}; then
    echo false
  else
    echo true
  fi
}

function chkbox() {
  if ${1}; then
    echo "x"
  else
    echo " "
  fi
}

savecache=false
function namefromsid() {
  local qry sid idx cached_sid userinfo name url
  sid=${1}
  idx=0
  for cached_sid in "${steamidcache[@]}"; do
    if [ "${cached_sid}" == "${sid}" ]; then
      echo -n "${steamnamecache[idx]} (cached)"
      return 0
    fi
    idx=$(( 10#${idx} + 1))
  done

  userinfo="$(curl -sL "https://steamcommunity.com/profiles/${sid}" | egrep "[^a-zA-Z0-9_]g_rgProfileData *= *\{" | sed -E "s/^.*ProfileData *=.*\"url\" *: *\"([^\"]+)\".*\"steamid\" *: *\"([^\"]+)\".*\"personaname\" *: *\"([^\"]+)\".*\$/\1|\2|\3/" 2>&1)"

  if [[ "${userinfo}" =~ ^[^\|]+/([^/]+)\/\|(7656[0-9]{13})\|(.+)$ ]]; then
    url="${BASH_REMATCH[1]}"
    if [ "${BASH_REMATCH[2]}" != "${sid}" ]; then
      fail "Steam ID in response doesn't match when querying a Steam ID."
    fi
    name="${BASH_REMATCH[3]}"
  else
    name="unknown"
    url=""
  fi
  savecache=true
  steamidcache+=("${sid}")
  steamurlcache+=("${url}")
  steamnamecache+=("${name}")

  echo -n "${name}"
}

function namefromsurl() {
  local qry url idx cached_sid cached_surl userinfo name url
  url=${1,,}
  idx=0
  for cached_surl in "${steamurlcache[@]}"; do
    if [ "${cached_surl}" == "${url}" ]; then
      echo -n "${steamnamecache[idx]} (cached)"
      return 0
    fi
    idx=$(( 10#${idx} + 1))
  done

  userinfo="$(curl -sL "https://steamcommunity.com/id/${url}" | egrep "[^a-zA-Z0-9_]g_rgProfileData *= *\{" | sed -E "s/^.*ProfileData *=.*\"url\" *: *\"([^\"]+)\".*\"steamid\" *: *\"([^\"]+)\".*\"personaname\" *: *\"([^\"]+)\".*\$/\1|\2|\3/" 2>&1)"

  if [[ "${userinfo//\\/}" =~ ^[^\|]+/([^/]+)/\|(7656[0-9]{13})\|(.+)$ ]]; then
    if [ "${BASH_REMATCH[1],,}" != "${url}" ]; then
      fail "Steam URL ID in response ('${BASH_REMATCH[1]}') doesn't match when querying a Steam URL ID."
    fi
    sid="${BASH_REMATCH[2]}"
    name="${BASH_REMATCH[3]}"

    savecache=true

    idx=0
    for cached_sid in "${steamidcache[@]}"; do
      if [ "${cached_sid}" == "${sid}" ]; then
        steamurlcache[idx]="${url}"
        if [ "${steamnamecache[idx]}" != "${name}" ]; then
          steamnamecache[idx]="${name}"
        fi
        echo -n "${steamnamecache[idx]} (cache updated)"
        return 0
      fi
      idx=$(( 10#${idx} + 1))
    done

    steamidcache+=("${sid}")
    steamurlcache+=("${url}")
    steamnamecache+=("${name}")
    echo -n "${name}"
    return 0
  else
    echo -n "not found"
    return 1
  fi
}

function mkcfg() {
  local ats=true
  if [ ${1} == "ets2" ]; then
    ats=false
  fi

  local rand="$(echo ${RANDOM} | md5sum | cut -b-7)"

  local modlist=()
  local mods=""
  if [ ! -z "${sv_mods}" ]; then
    modlist=($(echo ${sv_mods//,/ }))

    local idx=0
    local sid
    for sid in "${modlist[@]}"; do
      mods="${mods}
 moderator_list[${idx}]: ${sid}"
      idx=$(( 10#${idx} + 1))
    done
  fi

  local token="$(aoeval "${sv_token}" ${ats})"
  local speedlim="$(aoeval "${sv_speedlim}" ${ats})"

  local baseport="${sv_port}"

  if [ "${scsgame}" == "both" -a "${1}" == "ets2" ]; then
    baseport=$(( 10#${baseport} + 2 ))
  fi

  cat <<EOCF
SiiNunit
{
server_config : _mkscsjail.${rand::3}.${rand:3:4} {
 lobby_name: "${sv_name}"
 description: "${sv_desc}"
 welcome_message: "${sv_welcome}"
 password: "${sv_pass}"
 max_players: 8
 max_vehicles_total: ${sv_max_vehicles}
 max_ai_vehicles_player: ${sv_max_controllable_vehicles}
 max_ai_vehicles_player_spawn: ${sv_max_spawnable_vehicles}
 connection_virtual_port: ${sv_vport}
 query_virtual_port: $(( 10#${sv_vport} + 1 ))
 connection_dedicated_port: ${baseport}
 query_dedicated_port: $(( 10#${baseport} + 1 ))
 server_logon_token: ${token}
 player_damage: ${sv_pdmg}
 traffic: ${sv_traffic}
 hide_in_company: ${sv_cmp_hide}
 hide_colliding: ${sv_hide_coll}
 force_speed_limiter: ${speedlim}
 mods_optioning: ${sv_optmods}
 timezones: ${sv_tzs}
 service_no_collision: ${sv_svc_nocoll}
 in_menu_ghosting: ${sv_menu_ghost}
 name_tags: ${sv_nametags}
 friends_only: false
 show_server: true
 moderator_list: ${#modlist[@]}${mods}
}

}
EOCF
}

notoken_msg="none (non-persistent server id)"
function showcfg() {
  local game token atsv etsv asopts o oo

  if [ "${1}" == "+opts" ]; then
    o="true"
    oo=""
  else
    o=""
    oo="true"
  fi

  case "${scsgame}" in
    ats)
      game="ATS"
      token="$(atsval "${sv_token}")"
      token="${token:-${notoken_msg}}"
      ;;
    ets2)
      game="ETS2"
      token="$(etsval "${sv_token}")"
      token="${token:-${notoken_msg}}"
      ;;
    both)
      game="ATS & ETS2"
      atsv="$(atsval "${sv_token}")"
      etsv="$(etsval "${sv_token}")"
      token=" ats=${atsv:-${notoken_msg}}
                       ${o:+  }ets2=${etsv:-${notoken_msg}}"
      ;;
  esac

  echo -n "Current game configuration:
                 Game: ${game}
          Server name: ${o:+a)}${sv_name}
   Server description: ${o:+b)}${sv_desc}
      Welcome message: ${o:+c)}${sv_welcome}
             Password: ${o:+d)}${sv_pass:-<no password>}
   Server Login Token: ${o:+e)}${token}
 Time zone simulation: ${o:+f)}"
  case "${sv_tzs}" in
    0) echo "disabled";;
    1) echo "enabled - only time";;
    2) echo "enabled - show also current time zone";;
    *) echo "unknown";;
  esac

  echo "     Maximum vehicles: ${o:+g)}${sv_max_vehicles} (server total)
Controllable vehicles: ${o:+h)}${sv_max_controllable_vehicles} (per player, up to max)
   Spawnable vehicles: ${o:+i)}${sv_max_spawnable_vehicles} (per player, up to max)"

  if [ "${scsgame}" == "both" ]; then
    local ets2p=$(( 10#${sv_port} + 2))
    echo "          Server port: ${o:+j)}ATS:  ${sv_port} (connection), $(( 10#${sv_port} + 1 )) (query)
                       ${o:+  }ETS2: ${ets2p} (connection), $(( 10#${ets2p} + 1 )) (query)"
  else
    echo "          Server port: ${o:+j)}${sv_port} (connection), $(( 10#${sv_port} + 1 )) (query)"
  fi

  echo "  Server virtual port: ${o:+k)}${sv_vport} (connection), $(( 10#${sv_vport} + 1 )) (query)"

  case "${scsgame}" in
    ats) echo "[$(chkbox "$(aoeval "${sv_speedlim}" true)")] ${o:+l)}Force Speed Limiter";;
    ets2) echo "[$(chkbox "$(aoeval "${sv_speedlim}" false)")] ${o:+l)}Force Speed Limiter";;
    both)
      local asl="$(aoeval "${sv_speedlim}" true)"
      local esl="$(aoeval "${sv_speedlim}" false)"
      echo "  Force Speed Limiter: ${o:+l) }[$(chkbox "${asl}")] ats   [$(chkbox "${esl}")] ets2"
      ;;
  esac

# Two checkboxes per line: 34 chars in between
#    0        1         2         3         0        1         2         3
#[ ] 1234567890123456789012345678901234 [ ] 1234567890123456789012345678901234
#[$(chkbox "${sv_}")] 1234567890123456789012345678901234 [$(chkbox "${sv_}")] 1234567890123456789012345678901234

  echo "[$(chkbox "${sv_optmods}")] ${o:+m)}Optional mods${oo:+  }                    [$(chkbox "${sv_pdmg}")] ${o:+n)}Damage from players
[$(chkbox "${sv_svc_nocoll}")] ${o:+o)}Collisions disabled in service${oo:+  }   [$(chkbox "${sv_menu_ghost}")] ${o:+p)}Collisions disabled when in menu
[$(chkbox "${sv_cmp_hide}")] ${o:+q)}Hide players in companies' area${oo:+  }  [$(chkbox "${sv_nametags}")] ${o:+r)}Show player name tags in trucks
[$(chkbox "${sv_traffic}")] ${o:+s)}Enable AI traffic${oo:+  }                [$(chkbox "${sv_hide_coll}")] ${o:+t)}Hide teleported colliders
"

  if [ -z "${sv_mods}" ]; then
    echo ":: ${o:+(u) }No moderator set up."
  else
    local modlist=()
    local mods=""
    modlist=($(echo ${sv_mods//,/ }))
    echo -n ":: ${o:+(u) }${#modlist[@]} moderator"

    if [ ${#modlist[@]} -gt 1 ]; then
      echo -n "s"
    fi

    if [ "${1}" == "+opts" ]; then
      echo ""
    else
      echo ":"

      local pos=1
      local sid
      for sid in "${modlist[@]}"; do
        echo -n "${pos}. "
        # can't call from $() cause it won't update the cache (subshell)
        namefromsid "${sid}"
        echo " (${sid})"
        pos=$(( 10#${pos} + 1))
      done
    fi
  fi

  if [ ${#o} -gt 0 ]; then
    echo -n "
x) Accept changes and continue script execution.
z) Aborts/quits without changes.

Choose a field to edit: "
  fi
}

function showjailcfg() {
  echo -n "
Jail configuration:
a) Jail path: ${jaildir}
b) Bind to: "
  if [ "${bind_ip}" == "any" ]; then
    echo "No IP binding configured."
  else
    echo "Bind to ${bind_ip%:*} on ${bind_ip#*:}."
  fi
  echo -n "c) NUMA bindings: "
  if ! ${numa_enable}; then
    echo "disabled."
  else
    echo "Physical CPU #$(( 10#${numa_nodes} + 1)) - CPU Cores: ${numa_cpus}"
  fi

  echo -n "
x) Accept changes and continue script execution.
z) Aborts/quits without changes.

Choose a field to edit: "
}

function read_login_token_for_game() {
  if [ ${1} == "ats" ]; then
    echo "change ATS token."
  else
    echo "change ETS2 token."
  fi

  echo -n "
Enter token (empty for non-persistent): "
  read resp

  if [ ${#resp} -eq 0 ]; then
    if [ ${1} == "ats" ]; then
      sv_token=",$(etsval "${sv_token}")"
    else
      sv_token="$(atsval "${sv_token}"),"
    fi
    return 0;
  elif [ ${#resp} -ne 32 ]; then
    echo "Invalid token (must be empty or 32-character-long)."
    return 1
  elif [[ "${resp}" =~ ^[A-F0-9]+$ ]]; then
    if [ ${1} == "ats" ]; then
      sv_token="${resp},$(etsval "${sv_token}")"
    else
      sv_token="$(atsval "${sv_token}"),${resp}"
    fi
    return 0
  else
    echo "Invalid token (not in expected format)."
    return 1
  fi
}

function load_ip_config() {
  local iflns ipln

  IFS=$'\n'
  iflns=($(ip -4 addr | egrep "^ *inet [0-9\.]+/[0-9]+ (|.* ).*scope (host|global) (.+)\$"))
  IFS="${_ifs}"
  iplist=()
  for ipln in "${iflns[@]}"; do
    if [[ "${ipln}" =~ ^\ *inet\ ([0-9\.]+)/[0-9]+\ (|.*\ )scope\ (host|global)\ (.+)$ ]]; then
      # We ignore the loopback device.
      if [ "${BASH_REMATCH[1]}" != "127.0.0.1" ]; then
       iplist+=("${BASH_REMATCH[1]}:${BASH_REMATCH[4]}")
      fi
    fi
  done
}

function load_numa() {
  local numaout nl nodelines
  numaout="$(numactl --hardware)"

  IFS=$'\n'
  nodelines=($(echo "${numaout}" | egrep "^node [0-9]+ cpus: "))
  IFS="${_ifs}"

  numa_hardware_cpus=()
  for nl in "${nodelines[@]}"; do
    if [[ "${nl}" =~ ^node\ ([0-9]+)\ cpus:\ ([0-9\ ]+) ]]; then
      numa_hardware_cpus[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
    else
      fail "Error reading CPU core list off line: [${nl}]"
    fi
  done
}

# proper validation will be too overkill, so we'll leave it to numactl :P
function validate_numa() {
  local expnodes

  if $numa_enable; then
    if [ ${#numa_hardware_cpus[@]} -eq 0 ]; then
      load_numa

      if [ ${#numa_hardware_cpus[@]} -eq 0 ]; then
        fail "Unable to query NUMA CPU information."
      fi
    fi
    # 1-10,14,17,19-23
    if [[ ! "${numa_nodes}" =~ ^[0-9,-]+$ ]]; then
      echo "Invalid physical CPUs specification: ${numa_nodes}"
      numa_enable=false
      return 1
    fi

    if [[ ! "${numa_cpus}" =~ ^[0-9,-]+$ ]]; then
      echo "Invalid logical CPU cores specification: ${numa_cpus}"
      numa_enable=false
      return 1
    fi
  fi

  return 0
}

function jailcf_binding() {
  echo "config IP binding."

  if ! has_cmd "gcc"; then
    echo -n "Unable to locate GCC (GNU C Compiler) in this system.
Without GCC we are unable to build the IP-binding subsystem.
To set up specific IP binding, please install GCC.

Press any key to return..."
    read -sn1 null
    return 0
  fi

  while true; do
    echo -n "Current IP binding configuration: "
    if [ "${bind_ip}" == "any" ]; then
      echo "No IP binding."
    else
      echo "Bind to ${bind_ip%:*} on ${bind_ip#*:}."
    fi

    echo -n "
a) Choose new binding.
b) Back to jail configuration.

Choose an option [ab]: "

    while true; do
      read -sn1 resp

      case "${resp}" in
        a)
          echo "new binding."
          if [ ${#iplist[@]} -eq 0 ]; then
            load_ip_config
          fi

          if [ ${#iplist[@]} -eq 0 ]; then
            fail "Unable to enumerate network addresses."
          fi

          echo "Available IP addresses:"

          idx=1
          for ippair in "${iplist[@]}"; do
            echo "${idx}) ${ippair%:*} on ${ippair#*:}"
            idx="$(( 10#${idx} + 1 ))"
          done

          echo "a) No binding (binds to all IPs across all network interfaces)."

          while true; do
            echo -n "
Choose an option [1-$(( 10#${idx} -1 )),a]: "
            if [ ${idx} -le 10 ]; then
              read -sn1 resp
            else
              read resp
            fi

            if [ "${resp}" == "a" -o "${resp}" == "all" -o "${resp}" == "any" ]; then
              if [ ${idx} -le 10 ]; then
                echo "${resp}"
              fi
              bind_ip="any"
              break 2;
            elif [[ "${resp}" =~ ^[0-9]+$ ]]; then
              if [ ${idx} -le 10 ]; then
                echo "${resp}"
              fi
              if [ ${resp} -lt 1 -o ${resp} -ge ${idx} ]; then
                echo "The chosen option is not within the valid interval (1:$(( 10#${idx} -1 )))."
              else
                bind_ip="${iplist[resp-1]}"
                break 2;
              fi
            else
              if [ ${idx} -le 10 ]; then
                echo "${resp}"
              fi
              echo "Please enter a number between 1 and $(( 10#${idx} -1 )), or 'a'."
            fi
          done;;
        b) echo "back."; break 2;;
      esac
    done
  done
}

function jailcf_numa() {
  local resp cpucores cnt cpupos
  echo "config NUMA."

  if ! $(which numactl > /dev/null 2>&1); then
    echo -n "This system does not support NUMA configuration.
Please install 'numactl' and try this option again.

Press any key to return."
    read -sn1 resp
    echo ""
    return 0
  fi

  if [ ${#numa_hardware_cpus[@]} -eq 0 ]; then
    load_numa

    if [ ${#numa_hardware_cpus[@]} -eq 0 ]; then
      fail "Unable to query NUMA CPU information."
    fi
  fi

  while true; do
    echo "
Current NUMA hardware:
- Physical CPUs: ${#numa_hardware_cpus[@]}"

    cnt=1
    for cpucores in "${numa_hardware_cpus[@]}"; do
      echo "- CPU #${cnt}: ${cpucores}"
      cnt="$(( 10#${cnt} + 1 ))"
    done

    echo "
Current NUMA configuration:"

    if ${numa_enable} ]; then
      echo "- Bind to CPU #$(( 10#${numa_nodes} + 1 ))
- Bind to CPU cores: ${numa_cpus}

a) Change NUMA configuration"

    else
      echo "- NUMA is disabled.

a) Configure NUMA"
    fi

    echo -n "b) Back to jail configuration.

Choose an option [ab]: "

    while true; do
      read -sn1 resp

      case "${resp}" in
        a)
          if ${numa_enable}; then
            echo -n "change config.

Choose the Physical CPU (c to cancel, d to disable NUMA): "
          else
            echo -n "configure.

Choose the Physical CPU (c to cancel): "
          fi

          # TODO: support choosing a physical CPU interval
          while true; do
            read -sn1 resp
            if ${numa_enable} && [ "${resp}" == "d" ]; then
              echo "disable NUMA CPU binding."
              numa_enable=false
              break 2
            elif [ "${resp}" == "c" ]; then
              echo "cancel."
              break 2
            elif [[ "${resp}" =~ ^[1-9]$ ]]; then
              if [ ${#numa_hardware_cpus[resp-1]} -gt 0 ]; then
                cpupos="${resp}"
                echo "Physical CPU #${cpupos}.
CPU core index: ${numa_hardware_cpus[cpupos-1]}

If there's a gap in the index numbers it means the Ids after the gap are
logical cores, e.g. HyperThreading cores. It is wise to pair physical to
their logical corresponding cores.

Some interval examples:
- 1-3,11-13
- 1,4,6,11,14,16
- 2-6

Please choose the interval carefully, we won't validate the input until
the steam updater is called."

                while true; do
                  echo -n "
Choose a core interval (empty to cancel): "
                  read resp
                  if [ ${#resp} -eq 0 ]; then
                    break 3
                  elif [[ "${resp}" =~ ^[0-9,-]+$ ]]; then
                    numa_enable=true
                    numa_nodes="$(( 10#${cpupos} - 1))"
                    numa_cpus="${resp}"
                    break 3
                  else
                    echo "Invalid format."
                  fi
                done
              fi
            fi
          done;;
        b) echo "back."; break 2;;
      esac
    done
  done
}

function jailcf_path() {
  local input_path
  echo "Current jail path: ${jaildir}
Working directory: ${PWD}

Enter a path -- can be absolute or relative to the current working directory.
Examples: /opt/scsjail - scsjail - myjails/ets2
Empty to go back without changes."

  while true; do
    echo -n "
::> "
    read input_path
    if [ -z "${input_path}" ]; then
      echo "Empty path. Returning without changes."
      break
    else
      if [ "${input_path::1}" != "/" ]; then
        input_path="./${input_path}"
      fi
      if [ "${input_path: -1}" == "/" ]; then
        input_path="${input_path::-1}"
      fi
      if [ -d "${input_path}" ]; then
        echo "Directory already exists. We don't support updating an existing directory.
Please choose a non-existing directory so we can start anew."
        continue
      elif [ -e "${input_path}" ]; then
        echo "Path exists and is not a directory."
        continue
      elif [ ! -d "${input_path%/*}" ]; then
        echo "Invalid path. Upper-level directory '${input_path%/*}' does not exist or is not a directory."
        continue
      fi

      jaildir="${input_path}"
      break
    fi
  done
}

function jailcf_runner() {
  fail E_NOTIMPL
}

function jailcf_updater() {
  fail E_NOTIMPL
}

function jailchown_nl() {
  local usr="${1}" target="${2}"
  chown -R "${usr}:${u_grp}" "${jaildir}/${target}" || \
    failnl ", failed." "Unable to chown [${usr}:${u_grp}]: ${jaildir}/${target}"
}

function jaillns_nl() {
 local target="${1}" symlink="${2}"
 ln -s "${target}" "${jaildir}/${symlink}" || \
    failnl ", failed." "Unable to create symlink: ${jaildir}/${symlink} => ${target}"
}

function jailmd_nl() {
  local dir="${1}"
  mkdir "${jaildir}/${dir}" || failnl ", failed." "Unable to create directory: ${jaildir}/${dir}"
}

function jailmd_recursive_nl() {
  local dir="${1}"
  mkdir -p "${jaildir}/${dir}" || failnl ", failed." "Unable to create directory: ${jaildir}/${dir}"
}

function cfgedit_login_token() {
  local atsv etsv resp clearoption

  echo "
Edit server's Steam Game Server Account Login Token. This is required in order
to have a persistent server ID for the dedicated server, and the server may not
be able to start without this token.

Tokens can be generated at: https://steamcommunity.com/dev/managegameservers
provided your steam account fulfills its requirements (not being a limited
account).
"

  if [ "${scsgame}" == "both" ]; then
    while true; do
      atsv="$(atsval "${sv_token}")"
      etsv="$(etsval "${sv_token}")"
      echo "Steam Login Tokens:
a) ATS: ${atsv:-${notoken_msg}}
b) ETS2: ${etsv:-${notoken_msg}}"

      if [ ! -z "${atsv}${etsv}" ]; then
        clearoption=true
        echo "c) Clear all tokens."
      else
        clearoption=false
      fi

      echo -n "d) Done, go back to previous menu.

Choose an option [ab"
      ${clearoption} && echo -n "c"
      echo -n "d]: "

      while true; do
        read -sn1 resp

        case "${resp}" in
          a) read_login_token_for_game "ats"; break;;
          b) read_login_token_for_game "ets2"; break;;
          c) ${clearoption} && { echo "clear all tokens."; sv_token=","; break; };;
          d) echo "back."; break 2;;
        esac
      done
    done
  else
    read_login_token_for_game "${scsgame}" || sleep 3
  fi

  showcfg +opts
}

function cfgedit_maxpveh() {
  local resp
  echo "change maximum AI vehicles controllable by players.

This limits how many vehicles can be controlled by an individual player's AI.
Each player who logs in the game can gain control of AI vehicles to add traffic
surrounding them. Other players can see the AI vehicles going around and
eventually control them when the other player leaves.

This can be a number from 0 (zero) up to the maximum amount of vehicles allowed,
and has no effect if AI vehicles (traffic) is disabled in the server.

Current value: ${sv_max_controllable_vehicles}
Current maximum vehicles allowed: ${sv_max_vehicles}
"

  while true; do
    echo -n "Choose a new value (empty to keep value): "
    read resp;

    if [ -z "${resp}" ]; then
      echo "Keeping value: ${sv_max_controllable_vehicles}"
      break;
    elif [[ "${resp}" =~ ^[0-9]+$ ]]; then
      if [ ${resp} -gt ${sv_max_vehicles} ]; then
        echo "
Please enter a reasonable value. Values beyond ${sv_max_vehicles} exceeds the
maximum vehicles allowed in the server.
"
      else
        sv_max_controllable_vehicles="${resp}"
        if [ ${sv_max_spawnable_vehicles} -gt ${sv_max_controllable_vehicles} ]; then
          echo "Maximum spawnable vehicles: ${sv_max_spawnable_vehicles} => ${sv_max_controllable_vehicles}"
          sv_max_spawnable_vehicles=${sv_max_controllable_vehicles};
        fi
        break;
      fi
    else
      echo "
Value must be a number between 0 and ${sv_max_vehicles}.
"
    fi
  done

  showcfg +opts
}

function cfgedit_maxspveh() {
  local resp
  echo "change maximum AI vehicles players can spawn.

This limits how many AI vehicles can be spawned by an individual player. Each
player who logs in the game can spawn and control AI vehicles to add traffic
surrounding them. Other players can see the vehicles going around and
eventually gain control over them, when the other player leaves.

This can be a number from 0 (zero) up to the maximum amount of vehicles allowed
to be controlled by players, and has no effect if AI vehicles (traffic) is
disabled in the server.

Current value: ${sv_max_spawnable_vehicles}
Current maximum vehicles allowed: ${sv_max_controllable_vehicles}
"

  while true; do
    echo -n "Choose a new value (empty to keep value): "
    read resp;

    if [ -z "${resp}" ]; then
      echo "Keeping value: ${sv_max_spawnable_vehicles}"
      break;
    elif [[ "${resp}" =~ ^[0-9]+$ ]]; then
      if [ ${resp} -gt ${sv_max_controllable_vehicles} ]; then
        echo "
Please enter a reasonable value. Values beyond ${sv_max_controllable_vehicles} exceeds the
maximum controllable AI vehicles allowed in the server.
"
      else
        sv_max_spawnable_vehicles="${resp}"
        break;
      fi
    else
      echo "
Value must be a number between 0 and ${sv_max_controllable_vehicles}.
"
    fi
  done

  showcfg +opts
}

function cfgedit_maxveh() {
  local resp
  echo "change maximum allowed vehicles.

The maximum allowed vehicles is the sum of player vehicles + AI vehicles across
the whole game server. For instance, for 80 vehicles max, with 8 players online
each player would be able to spawn 9 AI vehicles or, say, one player once a
player spawned their 50 own AI vehicles, all other players would be able to,
combined, spawn up to 22 AI vehicles (22 + 8 + 50 = 80).

Having too many maximum vehicles could bottleneck the server (and clients')
connection. Having too many vehicles in the vicinity could hit very bad FPS of
a player as well.

Current value: ${sv_max_vehicles}
"

  while true; do
    echo -n "Choose a new value (empty to keep value): "
    read resp;

    if [ -z "${resp}" ]; then
      echo "Keeping value: ${sv_max_vehicles}"
      break;
    elif [[ "${resp}" =~ ^[0-9]+$ ]]; then
      if [ ${resp} -le 1 -o ${resp} -gt 500 ]; then
        echo "
Please enter a reasonable value. For less than 1 vehicles total, just disable
AI vehicles in hte server. Values beyond 500 should be overkill.
"
      else
        sv_max_vehicles="${resp}"

        if [ ${sv_max_controllable_vehicles} -gt ${sv_max_vehicles} ]; then
          echo "Maximum controllable vehicles: ${sv_max_controllable_vehicles} => ${sv_max_vehicles}"
          sv_max_controllable_vehicles=${sv_max_vehicles}
        fi
        if [ ${sv_max_spawnable_vehicles} -gt ${sv_max_controllable_vehicles} ]; then
          echo "Maximum spawnable vehicles: ${sv_max_spawnable_vehicles} => ${sv_max_controllable_vehicles}"
          sv_max_spawnable_vehicles=${sv_max_controllable_vehicles};
        fi
        break;
      fi
    else
      echo "
Value must be a number between 1 and 500.
"
    fi
  done

  showcfg +opts
}

function cfgedit_moderators() {
  local modlist mods pos sid resp retstat

  echo "edit moderator list."

  while true; do
    modlist=()
    mods=""
    if [ ${#sv_mods} -eq 0 ]; then
      echo "
- No moderators set up."
    else
      modlist=($(echo ${sv_mods//,/ }))
      echo -n "
- Listing ${#modlist[@]} moderator"

      if [ ${#modlist[@]} -gt 1 ]; then
        echo -n "s"
      fi

      echo ":"

      pos=1
      for sid in "${modlist[@]}"; do
        echo -n "${pos}. "
        # can't call from $() cause it won't update the cache (subshell)
        namefromsid "${sid}"
        echo " (${sid})"
        pos=$(( 10#${pos} + 1))
      done
    fi

    echo "
a) Add a moderator."
    if [ ${#modlist[@]} -gt 0 ]; then
      echo "b) Remove a moderator.
c) Clear all moderators.
z) Clear the Steam ID -> name cache."
    fi
    echo -n "d) Done, go back to previous menu.

Choose an option: "

    while true; do
      read -sn1 resp
      case "${resp}" in
        a)
          echo "add.

Enter below the new moderator's Steam ID. It can be either the public Steam URL
(e.g. https://steamcommunity.com/id/UserName), or the numeric Steam ID, a
number in the format [7656xxxxxxxxxxxxx] (17 characters), when the player
profile url is something like:
https://steamcommunity.com/profiles/7656xxxxxxxxxxxxx
"
          while true; do
            echo -n "Enter new moderator's Steam ID (empty to return): "
            read resp

            sid=""
            if [ ${#resp} -eq 0 ]; then
              break 2;
            elif [[ "${resp}" =~ ^7656[0-9]{13}$ ]]; then
              sid="${resp}"
            elif [ ${#resp} -gt 2 ]; then
              if [ ${#resp} -gt 30 -a "${resp::30}" == "https://steamcommunity.com/id/" ]; then
                resp="${resp:30}"
              elif [ "${resp}" != "${resp//\//}" ]; then
                echo "Invalid steam ID."
                continue
              fi

              echo -n "Querying Steam URL id: "
              namefromsurl "${resp}"
              retstat="${?}"
              echo ", done."

              if [ ${retstat} -eq 0 ]; then
                for ((pos=0; pos<${#steamurlcache[@]}; pos++)); do
                  if [ "${steamurlcache[pos]}" == "${resp}" ]; then
                    sid="${steamidcache[pos]}"
                  fi
                done
                if [ ${#sid} -eq 0 ]; then
                  fail "Couldn't find cached Steam ID after Steam URL ID query found it."
                fi
              else
                echo "Couldn't find Steam ID from the provided Steam URL ID."
                continue
              fi
            fi

            if [ ${#sid} -gt 0 ]; then
              if [[ "${sv_mods}" =~ (^|,)${sid}(,|$) ]]; then
                echo "Steam account already set as moderator."
                continue
              fi

              echo -n "
Steam user: "
              # first call must be outside subshell to ensure cache is updated
              namefromsid "${sid}"
              echo " (${sid})"

              if [ "$(namefromsid "${sid}")" == "unknown" ]; then
                echo "Warning: Steam user not found, is it really a valid Steam ID?"
              fi

              echo -n "Confirm adding steam user as moderator? [yn] "

              while true; do
                read -sn1 resp

                case "${resp}" in
                  y)
                    echo "yes."
                    if [ ${#modlist[@]} -eq 0 ]; then
                      sv_mods="${sid}"
                    else
                      sv_mods="${sv_mods},${sid}"
                    fi
                    echo "Steam user added to moderators list."
                    break 3;; # back to the main list to re-populate modlist[]
                  n) echo "no."; break;;
                esac
              done
            fi
          done;;
        b)
          if [ ${#modlist[@]} -gt 0 ]; then
            if [ ${#modlist[@]} -eq 1 ]; then
              echo "remove the last standing moderator."
              sv_mods=""
              break 2
            else
              echo "remove one of the existing moderators."

              while true; do
                echo -n "
Enter moderator position in the list or their Steam ID (empty to return): "
                read resp

                if [ ${#resp} -eq 0 ]; then
                  break;
                elif [[ "${resp}" =~ ^7656[0-9]{13}$ ]]; then
                  sid=""
                  for ((pos=0; pos < ${#modlist[@]}; pos++)); do
                    if [ "${modlist[pos]}" == "${resp}" ]; then
                      sid="${resp}" # just signal that an entry was found
                      modlist[pos]=""
                      break
                    fi
                  done
                  if [ ${#sid} -eq 0 ]; then
                    echo "The specified Steam ID is not among the moderators list."
                    continue;
                  else
                    sv_mods="${modlist[@]}"
                    sv_mods="${sv_mods//  / }"
                    sv_mods="${sv_mods// /,}"
                    break 2;
                  fi
                elif [[ "${resp}" =~ ^[0-9]+$ ]]; then
                  if [ ${resp} -gt ${#modlist[@]} ]; then
                    echo "There's no moderator at position #${resp}."
                    continue
                  else
                    modlist[${resp}-1]=""
                    sv_mods="${modlist[@]}"
                    sv_mods="${sv_mods//  / }"
                    sv_mods="${sv_mods// /,}"
                    break 2;
                  fi
                else
                  echo "The Steam ID or position must be a number."
                  continue;
                fi
              done
            fi
          fi;;
        c)
          if [ ${#modlist[@]} -gt 0 ]; then
            echo "clear moderator list."
            sv_mods=""
            break;
          fi;;
        d) echo "return to previous menu."; break 2;;
        z) echo "clear steam id cache."; steamidcache=(); steamnamecache=(); break;;
      esac
    done
  done

  showcfg +opts;
}

function cfgedit_password() {
  local newpass
  echo -n "change password.

Enter a password, at least 4 characters long, to require players to enter
your server.

An empty text will disable password.
Less than 4 characters returns without changing the current password.

Random password suggestion: $(echo "${RANDOM}${RANDOM}" | base64 | cut -b-8)

New password: "

  read newpass

  if [ ${#newpass} -eq 0 ]; then
    sv_pass=""
  elif [ ${#newpass} -gt 63 ]; then
    echo "Warning: truncating password to 63 characters."
    sv_pass="${newpass::63}"
    sv_pass="${sv_pass//\"/\'}"
  elif [ ${#newpass} -ge 4 ]; then
    sv_pass="${newpass//\"/\'}"
  else
    echo "Returning with no password changes."
  fi

  showcfg +opts
}

function cfgedit_port() {
  local newport maxport=65534
  if [ "${scsgame}" == "both" ]; then
    maxport=$(( 10#${maxport} - 2 ))
  fi

  echo "change listen port.

Enter a port number between 1024 and ${maxport}. This port will be used
by the game server to communicate with Steam and players.

An empty por number returns without changes to current port."

  if [ "${scsgame}" == "both" ]; then
    echo "
Base port: ${sv_port}
Ports for each game:
ATS: ${sv_port} (connection) $(( 10#${sv_port} + 1)) (query)
ETS2: $(( 10#${sv_port} + 2)) (connection) $(( 10#${sv_port} + 3)) (query)"
  else
    echo "
Current ports: ${sv_port} (connection) $(( 10#${sv_port} + 1)) (query)"
  fi

  while true; do
    echo -n "
Enter new port number [1024-${maxport}, empty to return]: "

    read newport

    if [ ${#newport} -eq 0 ]; then
      break
    elif [[ "${newport}" =~ ^[0-9]{1,5}$ ]]; then
      if [ "${newport}" -lt 1024 -o "${newport}" -gt "${maxport}" ]; then
        echo "Port number outside allowable interval."
      else
        sv_port="${newport}"
        break
      fi
    else
      echo "Invalid port number."
    fi
  done

  showcfg +opts
}

function cfgedit_server_desc() {
  local newdesc
  echo "change server description.

Enter a server description to be displayed to players.
An empty text will return without changes.
The description must be between 4 and 63 characters.
Current description: ${sv_desc}"

  while true; do
    echo -n "
New server description: "
    read newdesc

    if [ ${#newdesc} -eq 0 ]; then
      break
    elif [ ${#newdesc} -gt 63 ]; then
      echo "Warning: truncating server description to 63 characters."
      sv_desc="${newdesc::63}"
      sv_desc="${sv_desc//\"/\'}"
      break
    elif [ ${#newdesc} -ge 4 ]; then
      sv_desc="${newdesc//\"/\'}"
      break
    else
      echo "Invalid description input."
    fi
  done

  showcfg +opts
}

function cfgedit_server_name() {
  local newname
  echo "change server name.

Enter a server name to be displayed to players in the server listing.
An empty text will return without changes.
The name must be between 4 and 63 characters.
Current server name: ${sv_name}"

  while true; do
    echo -n "
New server name: "
    read newname

    if [ ${#newname} -eq 0 ]; then
      break
    elif [ ${#newname} -gt 63 ]; then
      echo "Warning: truncating server name to 63 characters."
      sv_name="${newname::63}"
      sv_name="${sv_name//\"/\'}"
      break
    elif [ ${#newname} -ge 4 ]; then
      sv_name="${newname//\"/\'}"
      break
    else
      echo "Invalid server name input."
    fi
  done

  showcfg +opts
}

function cfgedit_speed_limiter() {
  if [ "${scsgame}" != "both" ]; then
    echo "toggle force speed limit."

    if [ "${sv_speedlim}" == "${sv_speedlim//,/}" ]; then
      sv_speedlim="$(toggle ${sv_speedlim})"
    else
      local asl="$(atsval "${sv_speedlim}")" esl="$(etsval "${sv_speedlim}")"
      sv_speedlim="$(toggle "${asl}"),$(toggle "${esl}")"
    fi
  else
    local asl esl resp

    while true; do
      asl="$(atsval "${sv_speedlim}")" esl="$(etsval "${sv_speedlim}")"
      echo -n "
Force speed limit:
[$(chkbox "${asl}")] (a) American Truck Simulator.
[$(chkbox "${esl}")] (e) Euro Truck Simulator 2.
    (b) Toggle both.
    (d) Done, go back to previous menu.

Choose an option [aebn]: "

      while true; do
        read -sn1 resp
        case "${resp}" in
          a) echo "toggle ats."; sv_speedlim="$(toggle "${asl}"),${esl}"; break;;
          e) echo "toggle ets2."; sv_speedlim="${asl},$(toggle "${esl}")"; break;;
          b) echo "toggle both."; sv_speedlim="$(toggle "${asl}"),$(toggle "${esl}")"; break;;
          d) echo "back."; break 2;;
        esac
      done
    done
  fi
  showcfg +opts;
}

function cfgedit_toggle() {
  case "${1}" in
    optmods) echo "toggle optional mods."; sv_optmods="$(toggle ${sv_optmods})"; showcfg +opts;;
    pdmg) echo "toggle damage from players."; sv_pdmg="$(toggle ${sv_pdmg})"; showcfg +opts;;
    svc_nocoll) echo "toggle collisions in service areas."; sv_svc_nocoll="$(toggle ${sv_svc_nocoll})"; showcfg +opts;;
    menu_ghost) echo "toggle collisions when in menu."; sv_menu_ghost="$(toggle ${sv_menu_ghost})"; showcfg +opts;;
    cmp_hide) echo "toggle hide players in company patios."; sv_cmp_hide="$(toggle ${sv_cmp_hide})"; showcfg +opts;;
    nametags) echo "toggle name tags on trucks."; sv_nametags="$(toggle ${sv_nametags})"; showcfg +opts;;
    traffic) echo "toggle AI traffic."; sv_traffic="$(toggle ${sv_traffic})"; showcfg +opts;;
    hide_coll) echo "toggle hide teleported colliders."; sv_hide_coll="$(toggle ${sv_hide_coll})"; showcfg +opts;;
  esac
}

function cfgedit_tzemu() {
  local resp
  echo -n "change server time zone simulation setting.

Choose time zone simulation in the server.

Disabled:
  No time zone simulation at all. Everywhere in the map, the sun and time will
  be the same, no matter what.

Enabled - Only time
  Simulates time zone changes across the map, such as western positioned
  players would notice the sun rising a bit after players in east portions
  of the map. The time display also skews according to the political time
  zone you are -- but no specific time zone information is disclosed.

Enabled - Full information
  Like above, but full time zone information is displayed in time references in
  the game, like job delivery times.

a) Disabled
b) Enabled - Only time
c) Enabled - Full information

Current setting: "
  case "${sv_tzs}" in
    0) echo "Disabled (a)";;
    1) echo "Enabled - Only time (b)";;
    2) echo "Enabled - Full info (c)";;
  esac

  echo -n "
Choose the desired server time zone simulation setting: "

  while true; do
    read -sn1 resp
    case "${resp}" in
      a) echo "disable it."; sv_tzs=0; break;;
      b) echo "enable time only."; sv_tzs=1; break;;
      c) echo "enable full info."; sv_tzs=2; break;;
    esac
  done

  showcfg +opts
}

function cfgedit_welcome_msg() {
  local newwelcome_msg
  echo "change server welcome message.

Enter a server welcome message to be displayed to players as they join the
server.
An empty text will return without changes.
The welcome message must be no longer than 127 characters.
Current server welcome message:
${sv_welcome}
"

  while true; do
    echo -n "
New server welcome message: "
    read newwelcome_msg

    if [ ${#newwelcome_msg} -eq 0 ]; then
      break
    elif [ ${#newwelcome_msg} -gt 127 ]; then
      echo "Warning: truncating server welcome message to 127 characters."
      sv_welcome="${newwelcome_msg::127}"
      sv_welcome="${sv_welcome//\"/\'}"
      break
    else
      sv_welcome="${newwelcome_msg//\"/\'}"
      break
    fi
  done

  showcfg +opts
}

function cfgedit_virtual_port() {
  local newport

  echo "change virtual ports.

Enter a port number between 100 and 199. This port will be used for connection
to the server, but it's not really clear in SCS documentation.

An empty por number returns without changes to current virtual ports.

Current ports: ${sv_vport} (connection) $(( 10#${sv_vport} + 1)) (query)"

  while true; do
    echo -n "
Enter new virtual port number [100-199, empty to return]: "

    read newport

    if [ ${#newport} -eq 0 ]; then
      break
    elif [[ "${newport}" =~ ^[0-9]{3}$ ]]; then
      if [ "${newport}" -lt 100 -o "${newport}" -gt 199 ]; then
        echo "Virtual port number outside allowable interval."
      else
        sv_vport="${newport}"
        break
      fi
    else
      echo "Invalid virtual port number."
    fi
  done

  showcfg +opts
}

function deploy_deps() {
  local bitness ref="${1}" deplist dep idx newdep

  bitness="$(file -Lb "${ref}" | cut -b 5,6)"

  if [ "${bitness}" != "32" -a "${bitness}" != "64" ]; then
    failnl ", failed." "Unable to determmine if file is 32 or 64 bit: ${ref}"
  fi

  deplist=($(ldd "${ref}" | egrep " => " | sed -E "s/^.* => ([^ ]+) .*\$/\1/g"))

  for ((idx=0; idx < ${#deplist[@]}; idx++)); do
    dep="${deplist[idx]}"
    if [ ! -e "${jaildir}/lib${bitness}/${dep##*/}" ]; then
      cp -L "${dep}" "${jaildir}/lib${bitness}/." || \
        failnl ", failed." "Unable to copy: ${dep} => ${jaildir}/lib${bitness}/."
      for newdep in $(ldd "${dep}" | egrep " => " | sed -E "s/^.* => ([^ ]+) .*\$/\1/g"); do
        # this could incur a few duplicates in deplist, but it will be much lighter
        # than sweeping the list over again.
        if [ ! -e "${jaildir}/lib${bitness}/${newdep##*/}" ]; then
          deplist+=("${newdep}")
        fi
      done
    fi
  done
}

function deploy_solib() {
  local bitness="${1}" lib="${2}" srclibpath

  if [ -e "/lib${bitness}/${lib}" ]; then
    srclibpath="/lib${bitness}"
  elif [ -e "/usr/lib${bitness}/${lib}" ]; then
    srclibpath="/usr/lib${bitness}"
  else
    failnl ", failed." "Unable to locate ${bitness}-bit shared object file: ${lib}"
  fi

  cp -L "${srclibpath}/${lib}" "${jaildir}/lib${bitness}/." || \
    failnl ", failed." "Unable to copy: ${srclibpath}/${lib} => ${jaildir}/lib${bitness}/."

  deploy_deps "${srclibpath}/${lib}"
}

function has_cmd() {
  which "${1}" > /dev/null 2>&1
  return ${?}
}

function valid_spf() {
  local game="${1}" path="${2}/server_packages.sii" mapfile

  if [ ! -f "${path}" ]; then
    return 1
  fi

  mapfile="$(egrep "^ *map_name: *\"" "${path}" | head -n1 | cut -f2 -d\")"

  case "${game}" in
    ats|amtrucks)
      if [ "${mapfile}" == "/map/usa.mbd" ]; then
        return 0
      fi;;
    ets2|eurotrucks|ets)
      if [ "${mapfile}" == "/map/europe.mbd" ]; then
        return 0
      fi;;
  esac

  return 1
}

if [ $(id -u) -ne 0 ]; then
  # TODO: implement dry-run or script-prepare run mode to prepare everything
  # as normal user and allow to just performing the result of the fully checked
  # procedure as root.
  fail "I know that's scary, but this script is not meant to be run by non-root users."
fi

# check requisites for game
# server_packages.* (depending on which game(s) chosen)
echo -n "Checking for server_packages: "
if [ "${scsgame}" == "both" ]; then
  for game in ats ets2; do
    for ext in sii dat; do
      if [ ! -f "${sppath}/${game}/server_packages.${ext}" ]; then
        failnl "not found." "Unable to locate ${game^^} server_packages.${ext} file at: ${sppath}/${game}/"
      fi
    done

    valid_spf "${game}" "${sppath}/${game}" || \
      failnl "invalid." "The server_packages files at '${sppath}/${game}' don't seem to be for ${game^^}."
  done
else
  # This makes it so the same path that works with --both would work if a
  # single game was selected
  if [ ! -f "${sppath}/server_packages.sii" -a \
         -f "${sppath}/${scsgame}/server_packages.sii" ]; then
    echo -n "within ${scsgame}/, "
    sppath="${sppath}/${scsgame}"
  fi

  for ext in sii dat; do
    if [ ! -f "${sppath}/server_packages.${ext}" ]; then
      failnl "not found." "Unable to locate ${scsgame^^} server_packages.${ext} file at: ${sppath}/${scsgame}/"
    fi
  done

  valid_spf "${scsgame}" "${sppath}" || \
    failnl "invalid." "The server_packages files at '${sppath}' don't seem to be for ${scsgame^^}."
fi
echo "ok."

if [ -d "${jaildir}" ]; then
  fail "Refusing to overwrite existing directory: ${jaildir}"
elif [ -e "${jaildir}" ]; then
  fail "Jail path exists and is not a directory: ${jaildir}"
fi

echo -n "Checking for base solibs: "
for lib in "${lib32[@]}"; do
  if [ ! -f "/lib32/${lib}" -a ! -f "/usr/lib32/${lib}" ]; then
    failnl "failed." "Unable to locate required solib: [/usr]/lib32/${lib}"
  fi
done

for lib in "${lib64[@]}"; do
  if [ ! -f "/lib64/${lib}" -a ! -f "/usr/lib64/${lib}" ]; then
    failnl "failed." "Unable to locate required solib: [/usr]/lib64/${lib}"
  fi
done

for lib in "${libcommon[@]}"; do
  for bitlen in 32 64; do
    if [ ! -f "/lib${bitlen}/${lib}" -a ! -f "/usr/lib${bitlen}/${lib}" ]; then
      failnl "failed." "Unable to locate required solib: [/usr]/lib${bitlen}/${lib}"
    fi
  done
done
echo "ok."

echo -n "Checking runner/updater users: "
if ! egrep -q "^${u_grp}:" /etc/group; then
 echo "failed.
You can create the group with
  groupadd ${u_grp}
"
 fail "Group not found: ${u_grp}"
fi
for usr in "${u_upd}" "${u_run}"; do
  if ! egrep -q "^${usr}:" /etc/passwd; then
    echo "failed.
You can create the user with:
  useradd -c \"SCS Dedicated Servers\" -g ${u_grp} -d /tmp -s /bin/false ${usr}
"
    fail "User not found: ${usr}"
  fi
  if ! groups "${usr}" | egrep -q "(^| )${u_grp}( |\$)"; then
    failnl "failed." "User '${usr}' does not belong to the '${u_grp}' group."
  fi
done

echo "ok."

# TODO This is probably not really working :S
echo -n "Checking whether we have locale archives: "
if [ ! -e "${locale_path}" ]; then
  echo "not found."
  fail "Unable to locate 'locale-archives' at: ${locale_path}"
fi
echo "ok, ${locale_path}."

echo -n "Checking whether we have root SSL certificates: "
if [ ! -d "${sslcerts_path}" ]; then
  echo "not found."
  fail "Unable to locate SSL root certificates at: ${sslcerts_path}"
else
  if [ ! -e "${sslcerts_path}/DigiCert_Global_Root_CA.pem" ]; then
    echo -n "warn.
    
Warning: it looks like you may not have the steam's required root certificate
         for the DigiCert certificate authority. If you don't have the correct
         CA certificate, steamcmd client will be unable to install or update
         the game servers.

Press any key to continue..."
    read -sn1 null
  else
    echo "ok, ${sslcerts_path}/."
  fi
fi

if [ ! -z "${numa_nodes}${numa_cpus}" ]; then
  if [ ${#numa_nodes} -eq 0 ]; then
    fail "When --numa-cores is specified, --numa-cpu must also be specified."
  elif [ ${#numa_cpus} -eq 0 ]; then
    fail "When --numa-cpu is specified, --numa-cores must also be specified."
  elif [[ "${numa_nodes}" =~ ^[1-9]$ ]]; then
    # Currently, we expect user input to be processor position (1, 2, 3...)
    # but internally, numactl uses zero-based indexes, so let's subtract it
    # at once.

    if [ ${#numa_hardware_cpus[@]} -eq 0 ]; then load_numa; fi
    if [ "${numa_nodes}" -gt ${#numa_hardware_cpus[@]} ]; then
      echo "NUMA CPU count: ${#numa_hardware_cpus[@]}"
      fail "This system does not have physical CPU #${numa_nodes} to bind to."
    fi
    numa_nodes="$(( 10#${numa_nodes} - 1 ))"
  else
    fail "Invalid --numa-cpu value: ${numa_nodes}"
  fi

  if [[ ! "${numa_cpus}" =~ ^[0-9,-]+$ ]]; then
    fail "Invalid --numa-nodes value: ${numa_cpus}"
  fi

  numa_enable=true
else
  # just to make sure
  numa_enable=false
fi

if [ "${bind_ip}" != "any" ]; then
  if ! has_cmd "gcc"; then
    echo "Warning: Unable to set up binding to IP ${bind_ip%:*}: gcc not found."
    bind_ip="any"
  else
    if [[ ! "${bind_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:(.+)$ ]]; then
      fail "Invalid IP binding format: ${bind_ip}"
    else
      load_ip_config
      invalid_ip_cf=true
      for ippair in "${iplist[@]}"; do
        if [ "${bind_ip}" == "${ippair}" ]; then
          invalid_ip_cf=false
          break
        fi
      done

      if ${invalid_ip_cf}; then
        echo "Valid IPs per interfaces in this system:"
        for ippair in "${iplist[@]}"; do
          echo "${ippair}"
        done
        fail "Invalid IP/interface specified: ${bind_ip}"
      fi
    fi
  fi
fi

while true; do
  showjailcfg
  while true; do
    read -sn1 resp

    case "${resp}" in
      a) jailcf_path; break;;
      b) jailcf_binding; break;;
      c) jailcf_numa; break;;
      x) echo "continue."; break 2;;
      z) echo "quit."; echo "Aborting script on user request."; exit 0;;
    esac
  done
done

if [ -e "${usercachefile}" ]; then
  echo -n "Loading steam user-id map cache: "
  IFS=$'\n'
  cachelines=($(egrep "^[0-9]+:.+" "${usercachefile}"))
  IFS="${_ifs}"

  if [ ${#cachelines[@]} -eq 0 ]; then
    echo "no entries in saved cache."
  else
    echo -n "${#cachelines[@]} entr"
    if [ ${#cachelines[@]} -gt 1 ]; then
      echo -n "ies"
    else
      echo -n "y"
    fi
    for cacheline in "${cachelines[@]}"; do
      if [[ "${cacheline}" =~ ^([^:]+):([^:]+):(.+)$ ]]; then
        steamidcache+=("${BASH_REMATCH[1]}")
        steamurlcache+=("${BASH_REMATCH[2]}")
        steamnamecache+=("${BASH_REMATCH[3]}")
      elif [[ "${cacheline}" =~ ^[^:]+:.+$ ]]; then
        steamidcache+=("${cacheline%%:*}")
        steamurlcache+=("")
        steamnamecache+=("${cacheline#*:}")
      fi
    done
    echo ", done."
  fi
fi

while true; do
  showcfg +opts
  while true; do
    read -sn1 resp
    case "${resp}" in
      a) cfgedit_server_name;;
      b) cfgedit_server_desc;;
      c) cfgedit_welcome_msg;;
      d) cfgedit_password;;
      e) cfgedit_login_token;;
      f) cfgedit_tzemu;;
      g) cfgedit_maxveh;;
      h) cfgedit_maxpveh;;
      i) cfgedit_maxspveh;;
      j) cfgedit_port;;
      k) cfgedit_virtual_port;;
      l) cfgedit_speed_limiter;;
      m) cfgedit_toggle optmods;;
      n) cfgedit_toggle pdmg;;
      o) cfgedit_toggle svc_nocoll;;
      p) cfgedit_toggle menu_ghost;;
      q) cfgedit_toggle cmp_hide;;
      r) cfgedit_toggle nametags;;
      s) cfgedit_toggle traffic;;
      t) cfgedit_toggle hide_coll;;
      u) cfgedit_moderators;;
      x) echo "continue."; break 2;;
      z) echo "quit."; echo "Aborting script on user request."; exit 0;;
    esac
  done
done

# Jail configuration:
echo -n "Creating chroot() jail: mkdir"
mkdir "${jaildir}" || failnl ", failed." "Unable to create directory: ${jaildir}"

case "${scsgame}" in
  both) gamedirs=("${atsjaildir}" "${atsdatadir}" "${etsjaildir}" "${etsdatadir}");;
  ats) gamedirs=("${atsjaildir}" "${atsdatadir}");;
  ets2) gamedirs=("${etsjaildir}" "${etsdatadir}");;
  *) failnl ", failed." "Unable to determine which game dir to create; scsgame=${scsgame}.";;
esac

for dir in proc dev tmp bin etc etc/ssl etc/ssl/certs lib32 lib64 usr usr/lib64 usr/lib64/locale steam var var/lib "${gamedirs[@]}"; do
  jailmd_nl "${dir}"
done

chmod u+t,a+rwx "${jaildir}/tmp" || failnl ", failed." "Unable to adjust temp dir flags in: ${jaildir}/tmp"

echo -n ", symlinks"

jaillns_nl lib64 "lib"

for binln in "${binlnk[@]}"; do
  jaillns_nl "../${binln}" "bin/${binln##*/}"
done

for libln in "${lib32lnk[@]}"; do
  jaillns_nl "../${libln}" "lib32/${libln##*/}"
done

for libln in "${lib64lnk[@]}"; do
  jaillns_nl "../${libln}" "lib64/${libln##*/}"
done

echo -n ", solibs"

for lib in "${lib32[@]}" "${libcommon[@]}"; do
  deploy_solib 32 "${lib}"
done

for lib in "${lib64[@]}" "${libcommon[@]}"; do
  deploy_solib 64 "${lib}"
done

if [ "${bind_ip}" != "any" ]; then
  echo -n ", bindip"
  
  cat << EOSRC | gcc -o "${jaildir}/bin/bindip" -x c - || failnl ", failed." "Unable to build IP binding wrapper with gcc."
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
  if (argc < 2) {
    printf("usage: %s <command> [arguments ...]\n", argv[0]);
    return 1;
  }

  char x32elf[5] = { 0x7f, 0x45, 0x4c, 0x46, 0x01 };
  char filehd[5];

  FILE * fh = fopen(argv[1], "r");
  if (!fh) {
    printf("unable to locate: %s\n", argv[1]);
    exit(1);
  }

  int bytes_read = fread(filehd, 1, 5, fh);

  ushort is_x32elf = bytes_read == 5;
  if (is_x32elf)
    for (int i = 0; i < 5; i++)
      if (filehd[i] != x32elf[i]) {
        is_x32elf = 1 == 0;
        break;
      };
  fclose(fh);

  if (is_x32elf)
    setenv("LD_PRELOAD", "/lib32/bindip.so", 1);
  else
    setenv("LD_PRELOAD", "/lib64/bindip.so", 1);

  char* eargs[argc];
  for (int i=0; i<argc-1; i++) {
    eargs[i] = argv[i+1];
#ifdef DEBUG
    printf("arg #%i: %s\n", i+1, argv[i+1]);
#endif
  }
  eargs[argc-1]=NULL;

#ifdef DEBUG
  printf("eargs[%i]=NULL;\n", argc-1);
  printf("execv(\"%s\", + %i args)\n", argv[1], argc-1);
#endif
  int retstat = execv(argv[1], eargs);
#ifdef DEBUG
  printf("exit status: %i\n", retstat);
#endif
  if (retstat < 0) {
    return 1;
  } else {
    return retstat;
  }
}
EOSRC

  for bits in 32 64; do
    if [ ${bits} == 32 ]; then
      marg="-m${bits}"
    else
      marg=""
    fi
    
    # Credits for the c code below:
    # Copyright (C) 2000  Daniel Ryde (daniel@ryde.net), http://www.ryde.net/, GNU GLPL v2.1
    # Small amendment by Daniel Lange, 2010
    # With some extra modifications, basically formatting, and fixing "bait" bug.
    cat << EOSRC | gcc -nostartfiles -fpic ${marg} -shared -o "${jaildir}/lib${bits}/bindip.so" -ldl -D_GNU_SOURCE -x c - || failnl ", failed." "Unable to build ${bits}-bit IP binding routine overrider library with gcc."
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <dlfcn.h>

int (*real_bind)(int, const struct sockaddr*, socklen_t);
int (*real_connect)(int, const struct sockaddr*, socklen_t);

char *bind_addr_env;
unsigned long int bind_addr_saddr;
unsigned long int inaddr_any_saddr;
struct sockaddr_in local_sockaddr_in[] = { 0 };

void _init(void)
{
  const char *err;

  real_bind = dlsym(RTLD_NEXT, "bind");
  if ((err = dlerror()) != NULL) {
    fprintf(stderr, "dlsym (bind): %s\n", err);
  }

  real_connect = dlsym(RTLD_NEXT, "connect");
  if ((err = dlerror()) != NULL) {
    fprintf(stderr, "dlsym(connect): %s\n", err);
  }

  inaddr_any_saddr = htonl(INADDR_ANY);
  if (bind_addr_env = getenv("BIND_ADDR")) {
    bind_addr_saddr = inet_addr(bind_addr_env);
    local_sockaddr_in->sin_family = AF_INET;
    local_sockaddr_in->sin_addr.s_addr = bind_addr_saddr;
    local_sockaddr_in->sin_port = htons(0);
  }
}

int bind(int fd, const struct sockaddr *sk, socklen_t sl)
{
  static struct sockaddr_in *lsk_in;
  lsk_in = (struct sockaddr_in*)sk;
 if ((lsk_in->sin_family == AF_INET) && (lsk_in->sin_addr.s_addr == inaddr_any_saddr) && bind_addr_env) {
    lsk_in->sin_addr.s_addr = bind_addr_saddr;
  }
  return real_bind(fd, sk, sl);
}

int connect(int fd, const struct sockaddr *sk, socklen_t sl)
{
  static struct sockaddr_in *rsk_in;
  rsk_in = (struct sockaddr_in*)sk;
 if ((rsk_in->sin_family == AF_INET) && bind_addr_env) {
    real_bind(fd, (struct sockaddr *)local_sockaddr_in, sizeof(struct sockaddr));
  }
  return real_connect(fd, sk, sl);
}
EOSRC
  done
fi

echo -n ", dev"

for devinfo in "${devfiles[@]}"; do
  if [[ "${devinfo}" =~ ^([^:]+):([bcpu]):([1-9][0-9]*):([1-9][0-9]*)$ ]]; then
    if [ "${BASH_REMATCH[2]}" == "p" ]; then
      mknod "${jaildir}/dev/${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
      mknod "${jaildir}/dev/${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
    fi
  fi
done

# TODO: This seems not to be working and steamcmd still complains about:
# WARNING: setlocale('en_US.UTF-8') failed, using locale: 'C'. International characters may not work.
echo -n ", locale"
cp -L "${locale_path}" "${jaildir}/usr/lib64/locale/." || failnl ", vanished." "Locale-archive file vanished from system? Unable to copy: ${locale_path} => ${jaildir}/usr/lib64/locale/."

echo -n ", SSL certs"
cp -L "${sslcerts_path}/"* "${jaildir}/etc/ssl/certs/." || failnl ", vanished." "SSL root certificates vanished from system? Unable to copy: ${sslcerts_path}/* => ${jaildir}/etc/ssl/certs/."

echo -n ", steamcmd"

curl -sL "${steamcliurl}" | tar -C "${jaildir}/steam" -xz || \
  failnl ", failed." "Unable to fetch/extract SteamCMD bootstrapper from: ${steamcliurl}"

for dir in steam "${gamedirs[@]}"; do
  jailchown_nl "${u_upd}" "${dir}"
done

deploy_deps "${jaildir}/steam/linux32/steamcmd"

echo -n ", config"
case "${scsgame}" in
  both)
    mkcfg "ats" > "${jaildir}/${atsdatadir}/server_config.sii"
    mkcfg "ets2" > "${jaildir}/${etsdatadir}/server_config.sii";;  
  ats) mkcfg "${scsgame}" > "${jaildir}/${atsdatadir}/server_config.sii";;
  ets2) mkcfg "${scsgame}" > "${jaildir}/${etsdatadir}/server_config.sii";;
esac

echo -n ", server_packages"
case "${scsgame}" in
  both)
    cp -L "${sppath}/ats/server_packages."{sii,dat} "${jaildir}/${atsdatadir}/." || \
      failnl ", failed." "Unable to copy server_packages files: ${sppath}/ats/server_packages.{sii,dat} => ${jaildir}/${atsdatadir}/."
    cp -L "${sppath}/ets2/server_packages."{sii,dat} "${jaildir}/${etsdatadir}/." || \
      failnl ", failed." "Unable to copy server_packages files: ${sppath}/ets/server_packages.{sii,dat} => ${jaildir}/${etsdatadir}/."
    jailchown_nl "${u_run}" "${atsdatadir}"
    jailchown_nl "${u_run}" "${etsdatadir}";;
  ats)
    cp -L "${sppath}/server_packages."{sii,dat} "${jaildir}/${atsdatadir}/." || \
      failnl ", failed." "Unable to copy server_packages files: ${sppath}/server_packages.{sii,dat} => ${jaildir}/${atsdatadir}/."
    jailchown_nl "${u_run}" "${atsdatadir}";;
  ets2)
    cp -L "${sppath}/server_packages."{sii,dat} "${jaildir}/${etsdatadir}/." || \
      failnl ", failed." "Unable to copy server_packages files: ${sppath}/server_packages.{sii,dat} => ${jaildir}/${etsdatadir}/."
    jailchown_nl "${u_run}" "${etsdatadir}";;
esac

echo -n ", scripts"

numacmd=""
netnscmd=""
chroot_runcmd="chroot --userspec \"${u_run}:${u_grp}\" \"\${jailroot}\""
chroot_updcmd="chroot --userspec \"${u_upd}:${u_grp}\" \"\${jailroot}\""

update_script="#!/bin/bash

jailroot=\"\$(dirname \"\$(readlink -f \"\${BASH_SOURCE}\")\")\""

if ${numa_enable}; then
  numacmd="numactl --membind \${numa_nodes} --cpunodebind \${numa_nodes} --physcpubind \${numa_cpus} --"
  update_script+="
numa_nodes=\"${numa_nodes}\"
numa_cpus=\"${numa_cpus}\""
fi

if [ "${bind_ip}" != "any" ]; then
  bindipcmd="bindip"
  update_script+="
export BIND_ADDR=\"${bind_ip%:*}\"
"
fi

update_script+="
umountproc=false
function doproc() {
  if ! egrep -q \" \${jailroot}/proc proc \" /etc/mtab; then
    echo -n \"Mounting proc filesystem: \${jailroot}/proc\"
    mount -t proc -o rw,nosuid,nodev,noexec,relatime jailproc \"\${jailroot}/proc\" || {
      echo \", failed.\"
      echo \"Unable to mount proc filesystem in jail's /proc.\"
      exit 1
    }
    echo \", done.\"
    umountproc=true
  fi
}

function unproc() {
  if \${umountproc}; then
    echo -n \"Unmounting \${jailroot}/proc: \"
    umount \"\${jailroot}/proc\" || echo \"failed.\" && echo \"done.\"
  else
    echo \"Not touching /proc fs mounted for jail. You may want to unmount it with:
# umount \${jailroot}/proc\"
  fi
}

"
run_script="${update_script}"

# The command macros shouldn't change from this point on, so simplify it
jailruncmd="${numacmd} \\
  ${chroot_runcmd} \\
  ${bindipcmd} \\
   "

jailupdcmd="${numacmd} \\
  ${chroot_updcmd} \\
  ${bindipcmd} \\
   "

case "${scsgame}" in
  both)
    update_script+="
case \"\${1}\" in
  ats)
    fname=\"American Truck Simulator\"
    groot=\"/${atsjaildir}\"
    gid=${atsgid};;
  ets|ets2)
    fname=\"Euro Truck Simulator 2\"
    groot=\"/${etsjaildir}\"
    gid=${etsgid};;
  *) echo \"usage: \${0} [ats|ets2]\"; exit 1;;
esac
"
    run_script+="
case \"\${1}\" in
  ats)
    execpath=\"/${atsjaildir}/${atsbinpath}\"
  ets|ets2)
    execpath=\"/${etsjaildir}/${etsbinpath}\"
  *) echo \"usage: \${0} [ats|ets2]\"; exit 1;;
esac"
    ;;
  ats)
    update_script+="
fname=\"American Truck Simulator\"
groot=\"/${atsjaildir}\"
gid=${atsgid}"
    run_script+="
execpath=\"/${atsjaildir}/${atsbinpath}\""
    ;;
  ets2)
    update_script+="
fname=\"Euro Truck Simulator 2\"
groot=\"/${etsjaildir}\"
gid=${etsgid}"
    run_script+="
execpath=\"/${etsjaildir}/${etsbinpath}\""
    ;;
esac

update_script+="
retstat=42
retries=1
max_retries=5

doproc
output=\"\"
echo -n \"Updating \${fname}: \"
while [ \${retries} -le \${max_retries} -a \${retstat} -eq 42 ]; do
 output=\"\${output}Attempt \${retries}/\${max_retries}
\$(${jailupdcmd} /bin/steamcmd +force_install_dir \"\${groot}\" +login anonymous +app_update \${gid} +quit 2>&1)
\"
 retstat=\${?}

 if [ \${retstat} -eq 42 ]; then
  retries=\"\$(( 10#\${retries} + 1 ))\"
  echo -n \"steam request re-run, \"
 fi
done

if [ \${retstat} -ne 0 ]; then
 echo \"failed.

Output:
\${output}

- \${fname} was *not* updated.\"
 unproc
 exit \${retstat}
else
 echo \"done.\"
 unproc
fi
"

run_script+="

doproc
export XDG_DATA_HOME=\"/${datadir}\"
${jailruncmd} \"\${execpath}\" -nosingle
unproc
"

echo "${update_script}" > "${jaildir}/update.sh"
echo "${run_script}" > "${jaildir}/run.sh"

for script in "update.sh" "run.sh"; do
  chmod a+rx,go-w "${jaildir}/${script}" || \
    failnl ", failed." "Unable set script as executable: ${jaildir}/${script}"
done

echo ", done."

if [ "${scsgame}" == "both" ]; then
  "${jaildir}/update.sh" ats || fail "Unable to install ATS dedicated server."
  "${jaildir}/update.sh" ets2 || fail "Unable to install ETS2 dedicated server."
 
  echo -n "Creating server config"
else
  "${jaildir}/update.sh" || fail "Unable to install ${scsgame^^} dedicated server."
fi

echo -n "Deploying server solibs: "
case "${scsgame}" in
  both)
    deploy_deps "${jaildir}/${atsjaildir}/${atsbinpath}"
    deploy_deps "${jaildir}/${etsjaildir}/${etsbinpath}";;
  ats) deploy_deps "${jaildir}/${atsjaildir}/${atsbinpath}";;
  ets2) deploy_deps "${jaildir}/${etsjaildir}/${etsbinpath}";;
esac
echo "done."

if $savecache; then
  echo -n "New cached steam user-id entries, saving: "
  if [ -e "${usercachefile}" ]; then
    echo -n "rmold"
    rm "${usercachefile}" || failnl ", failed." "unable to remove cache file: ${usercachefile}"
    echo -n ", "
  fi
  idx=0
  for cacheline in "${steamidcache[@]}"; do
    echo -n "."
    echo "${cacheline}:${steamurlcache[idx]}:${steamnamecache[idx]}" >> "${usercachefile}"
    idx="$(( 10#${idx} + 1 ))"
  done
  echo " done."
fi

echo "Jail configured successfully at: ${jaildir}

To run the game server:
# ${jaildir}/run.sh

To check for game updates:
# ${jaildir}/update.sh"