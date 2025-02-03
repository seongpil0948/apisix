#!/bin/bash

docker-compose \
  -p docker-apisix  \
  -f docker/docker-compose-arm64.yml  up -d

