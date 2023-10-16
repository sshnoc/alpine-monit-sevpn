#!/usr/bin/env bash

#
# https://github.com/siomiz/SoftEtherVPN
# https://marketsplash.com/tutorials/bash-shell/bash-shell-arguments/
# https://middleware.io/blog/docker-cleanup/
# https://www.thorsten-hans.com/how-to-build-multi-arch-docker-images-with-ease/
#

if [ -r $(dirname $0)/.env ] ; then
  source $(dirname $0)/.env
fi

PLATFORM=${PLATFORM:-linux/arm64,linux/amd64}
NAME=${NAME:-alpine-monit}

function help() {
  cat<<EOF

This scripts builds a devel Docker image for the $PLATFORM platform. Check the
docker directory for the Dockerfile.

Options:

    -p PLATFORM    Build for PLATFORM (eg.: amd64, arm64) [$PLATFORM]
    -n NAME        Name of the image is NAME:PLATFORM [$NAME]

Example:

    ./build.sh -p arm64 && ./build.sh -p amd64

Multi-arch:

    https://www.thorsten-hans.com/how-to-build-multi-arch-docker-images-with-ease/

EOF
  exit 1
}

# Multiplatform needs a repo and a --push

function platform_build_docker() {
  local _target_dir=./docker
  local _dockerfile=${_target_dir}/Dockerfile
  local _name=${NAME}

  # Need for multiarch
  # docker buildx create --name mybuilder --bootstrap --use

  # git_rev=$(git rev-parse --short HEAD)
  git_rev=$(git log --pretty=oneline --abbrev-commit)
  build_date=$(date +"%Y-%m-%d %H:%M:%S")

  echo "export GIT_REV=\"$git_rev\"" > ./docker/prerun.sh
  echo "export BUILD_DATE=\"$build_date\"" >> ./docker/prerun.sh
  echo "export IMAGE_NAME=\"$NAME\"" >> ./docker/prerun.sh

  echo
  echo "Building Docker Image"
  echo "Command: docker build $@ --platform ${PLATFORM} -t ${_name} -f ${_dockerfile} ${_target_dir}"
  docker build $@ --platform ${PLATFORM} -t ${_name} -f ${_dockerfile} ${_target_dir}
  echo
}

function main() {
  verbose=false
  while getopts ":vhp:n:d:" opt; do
    case ${opt} in
      h )
        help
        ;;
      p )
        PLATFORM=$OPTARG
        ;;
      n )
        NAME=$OPTARG
        ;;
      # \? )
      #   echo "Invalid option: -$OPTARG" 1>&2
      #   exit 1
      #   ;;
    esac
  done

  shift $((OPTIND-1))
  OTHERARGS=$@
  platform_build_docker $OTHERARGS
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi