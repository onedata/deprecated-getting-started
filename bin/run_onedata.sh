#!/bin/bash

REPO_ROOT="${PWD//getting-started*}getting-started/"
ONEZONE_CONFIG_DIR="${PWD}/config_onezone/"
ONEPROVIDER_CONFIG_DIR="${PWD}/config_oneprovider/"
ONEPROVIDER_DATA_DIR="${PWD}/oneprovider_data/"
SPACES_DIR="${PWD}/myspaces/"
AUTH_CONF="bin/config/auth.conf"
AUTH_PATH="${REPO_ROOT}${AUTH_CONF}"
ZONE_COMPOSE_FILE="docker-compose-onezone.yml"
PROVIDER_COMPOSE_FILE="docker-compose-oneprovider.yml"

DEBUG=0;

docker_compose_sh=("docker-compose" "-p" "${SCENARIO_NAME}")

#Default coordinates
GEO_LATITUDE="50.068968"
GEO_LONGITUDE="19.909444"

#Default Onezone
ZONE_FQDN="beta.onedata.org"

# Error handling.
# $1 - error string
die() {
  echo "${0##*/}: error: $*" >&2
  exit 1
}

print_docker_compose_file() {
  local compose_file_name=$1
  echo "The docker compose file with substituted variables be used:
BEGINING===="

  # http://mywiki.wooledge.org/TemplateFiles
  LC_COLLATE=C
  while read -r; do
    while [[ $REPLY =~ \$(([a-zA-Z_][a-zA-Z_0-9]*)|\{([a-zA-Z_][a-zA-Z_0-9]*)\})(.*) ]]; do
      if [[ -z ${BASH_REMATCH[3]} ]]; then   # found $var
        printf %s "${REPLY%"${BASH_REMATCH[0]}"}${!BASH_REMATCH[2]}"
      else # found ${var}
        printf %s "${REPLY%"${BASH_REMATCH[0]}"}${!BASH_REMATCH[3]}"
      fi
      REPLY=${BASH_REMATCH[4]}
    done
    printf "%s\n" "$REPLY"
  done < "${compose_file_name}"
  echo "====END"
}

# As the name suggests
usage() {
  echo "Usage: ${0##*/}  [-h] [ --zone  | --provider ] [ --clean ] [ --debug ]

Onezone usage: ${0##*/} --zone 
Oneprovider usage: ${0##*/} --provider [ --provider-fqdn <fqdn> ] [ --zone-fqdn <fqdn> ] [ --provider-data-dir ] [ --set-lat-long ]

Example usage:
${0##*/} --provider --provider-fqdn 'myonedataprovider.tk' --zone-fqdn 'myonezone.tk' --provider-data-dir '/mnt/super_fast_big_storage/' --provider-conf-dir '/etc/oneprovider/'

Options:
  -h, --help           display this help and exit
  --zone               starts onezone service
  --provider           starts oneprovider service
  --provider-fqdn      FQDN for oneprovider      
  --zone-fqdn          FQDN for onezone (defaults to beta.onedata.org)
  --provider-data-dir  a directory where provider will store users raw data
  --provider-conf-dir  directory where provider will configuration its files
  --set-lat-long       sets latitude and longitude from reegeoip.net service based on your public ip's
  --clean              clean all onezone, oneprivder and oneclient configuration and data files - provided all docker containers using them have been shutdown
  --debug              write to STDOUT the docker-compose config and commands that would be executed
  --detach             run container in background and print container name"
  exit 0
}

get_log_lat(){
  ip="$(curl http://ipinfo.io/ip)"
  read -r GEO_LATITUDE GEO_LONGITUDE <<< $(curl freegeoip.net/xml/"$ip" | grep -E "Latitude|Longitude" | cut -d '>' -f 2 | cut -d '<' -f 1)
}

debug() {
  set -o posix ; set
}

check_if_clean() {

  [[ -d "$ONEZONE_CONFIG_DIR" ]] && return 1
  [[ -d "$ONEPROVIDER_CONFIG_DIR" ]] && return 1
  [[ -d "$ONEPROVIDER_DATA_DIR" ]] && return 1
 
  [[ $(docker ps -aqf 'name=onezone') != "" ]] && return 1
  [[ $(docker ps -aqf 'name=oneprovider') != "" ]] && return 1
    
  return 0
}

clean() {
  
  echo "The cleaning procedure will need to run commands using sudo, in order to remove volumes created by docker. Please provide a password if needed."
  # Make sure only root can run our script
  
  #if [ "$(whoami)" != root ]; then
  # echo "This script must be run as root!" 1>&2
  # exit 1
  #fi

  [[ $(git status --porcelain "$ZONE_COMPOSE_FILE") != ""  ]] && echo "Warrning the file $ZONE_COMPOSE_FILE has changed, the cleaning procedure may not work!"
  [[ $(git status --porcelain "$PROVIDER_COMPOSE_FILE") != ""  ]] && echo "Warrning the file $PROVIDER_COMPOSE_FILE has changed, the cleaning procedure may not work!"
 
  echo "Removing provider and/or zone config dirs..."
  sudo rm -rf "${ONEZONE_CONFIG_DIR}"
  sudo rm -rf "${ONEPROVIDER_CONFIG_DIR}"
  

  echo "Removing provider data dir..."
  sudo rm -rf "${ONEPROVIDER_DATA_DIR}"
  
  echo "Removing Onedata containers..."
  if (docker rm -vf 'onezone-1' 2>/dev/null) ; then
    echo Removed onezone container onezone-1.
  fi

  if (docker rm -vf 'oneprovider-1' 2>/dev/null) ; then
    echo Removed onezone container onezone-1.
  fi

  echo "This is the output of 'docker ps -a' command, please make sure that there are no onedata containers listed!"
  docker ps -a

  clean_scenario
}

batch_mode_check() {
  local service=$1
  local compose_file_name=$2

  grep 'ONEPANEL_BATCH_MODE: "true"' "$compose_file_name" > /dev/null
  if [[ $? -eq 0 ]] ; then

    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    RESET="$(tput sgr0)"
  
    echo -e "${RED}IMPORTANT: After each start wait for a message: ${GREEN}Congratulations! ${service} has been successfully started.${RESET}"
    echo -e "${RED}To ensure that the ${service} is completely setup.${RESET}"
  fi
}

handle_onezone() {
  local n=$1
  local compose_file_name=$2
  local compose_up_opts=$3

  mkdir -p "$ONEZONE_CONFIG_DIR"


  if [[ $DEBUG -eq 1 ]]; then
    docker_compose_sh_local() {
      echo ZONE_DOMAIN_NAME="$ZONE_DOMAIN_NAME" PROVIDER_FQDN="$PROVIDER_FQDN" ZONE_FQDN="$ZONE_FQDN" AUTH_PATH="$AUTH_PATH" ONEZONE_CONFIG_DIR="$ONEZONE_CONFIG_DIR" ${docker_compose_sh[*]} "$@"
    }
    print_docker_compose_file "$compose_file_name"
  else 
    docker_compose_sh_local() {
      ZONE_DOMAIN_NAME="$ZONE_DOMAIN_NAME" PROVIDER_FQDN="$PROVIDER_FQDN" ZONE_FQDN="$ZONE_FQDN" AUTH_PATH="$AUTH_PATH" ONEZONE_CONFIG_DIR="$ONEZONE_CONFIG_DIR" ${docker_compose_sh[*]} "$@"
    }
  fi
  
  batch_mode_check "onezone" "$compose_file_name"
  docker_compose_sh_local -f "$compose_file_name" pull
  docker_compose_sh_local -f "$compose_file_name" up $compose_up_opts
} 

handle_oneprovider() {
  local n=$1
  local compose_file_name=$2
  local oneprovider_data_dir=$3
  local compose_up_opts=$4

  mkdir -p "$ONEPROVIDER_CONFIG_DIR"
  mkdir -p "$oneprovider_data_dir"


  if [[ $DEBUG -eq 1 ]]; then
    docker_compose_sh_local() {
      echo GEO_LATITUDE="$GEO_LATITUDE" GEO_LONGITUDE="$GEO_LONGITUDE" PROVIDER_FQDN="$PROVIDER_FQDN" ZONE_FQDN="$ZONE_FQDN" ONEPROVIDER_CONFIG_DIR="$ONEPROVIDER_CONFIG_DIR" ONEPROVIDER_DATA_DIR="$oneprovider_data_dir" ${docker_compose_sh[*]} "$@"
    }
    docker_compose_sh_local="echo ${docker_compose_sh_local}"
    print_docker_compose_file "$compose_file_name"
  else
    docker_compose_sh_local() {
      GEO_LATITUDE="$GEO_LATITUDE" GEO_LONGITUDE="$GEO_LONGITUDE" PROVIDER_FQDN="$PROVIDER_FQDN" ZONE_FQDN="$ZONE_FQDN" ONEPROVIDER_CONFIG_DIR="$ONEPROVIDER_CONFIG_DIR" ONEPROVIDER_DATA_DIR="$oneprovider_data_dir" ${docker_compose_sh[*]} "$@"
    }
  fi

  batch_mode_check "oneprovider" "$compose_file_name"
  docker_compose_sh_local -f "$compose_file_name" pull
  docker_compose_sh_local -f "$compose_file_name" up $compose_up_opts
} 

main() {

  if (( ! $# )); then
    usage
  fi

  local oneprovider_data_dir=$ONEPROVIDER_DATA_DIR
  local n=1
  local service
  local clean=0
  local get_log_lat_flag=0
  local compose_up_opts

  while (( $# )); do
      case $1 in
          -h|-\?|--help)   # Call a "usage" function to display a synopsis, then exit.
              usage
              exit 0
              ;;
          --zone)      
              service="onezone"
              ;;
          --provider)       
              service="oneprovider"
              ;;
          --provider-data-dir)       
              oneprovider_data_dir=$2
              shift
              ;;
          --provider-conf-dir)       
              ONEPROVIDER_CONFIG_DIR=$2
              shift
              ;;
          --clean)    
              clean=1
              ;;
          --debug)
              DEBUG=1
              ;;      
          --zone-fqdn)
              ZONE_FQDN=$2
              shift
              ;;
          --provider-fqdn)
              PROVIDER_FQDN=$2
              shift
              ;;
          --set-lat-long)
              get_log_lat_flag=1
              ;;
	  --keep-old-dockers)
	      keep_old_dockers=$2
	      shift
	      ;;
          --detach)
              compose_up_opts="-d"
              ;;
          -?*)
              printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
              exit 1
              ;;
          *)
              die "no option $1"
              ;;
      esac
      shift
  done

  check_if_clean
  if [[ $? -eq 1 ]]; then
    if [[ -z "$keep_old_dockers" ]]; then
      echo "We detected configuration files, data and docker containers from a previous Onedata deployment. 
Would you like to keep them (y) or start a new deployment (n)?"
      read -r agree_to_clean
      if [[ $agree_to_clean == 'n' ]]; then
        clean
      fi
    fi
  fi

  if [[ $keep_old_dockers -eq 'n' ]];then
    clean
  fi

  if [[ $clean -eq 1 ]]; then
    clean
    exit 0
  fi

  if [[ $get_log_lat_flag -eq 1 ]]; then
    get_log_lat
  fi

  local compose_file_name="docker-compose-${service}.yml"

  if [[ $service == "onezone" ]]; then
    handle_onezone "$n" "$compose_file_name" "$compose_up_opts"
  fi

  if [[ $service == "oneprovider" ]]; then
    handle_oneprovider "$n" "$compose_file_name" "$oneprovider_data_dir" "$compose_up_opts"
  fi

  if [[ $clean -eq 1 ]]; then
    debug
    exit 0
  fi
}


