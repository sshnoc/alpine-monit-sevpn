#!/usr/bin/env bash

if [ -r $(dirname $0)/.env ] ; then
  source $(dirname $0)/.env
fi

docker exec -it $NAME ${*:-/bin/sh}
