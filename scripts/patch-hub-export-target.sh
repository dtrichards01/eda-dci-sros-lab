#!/usr/bin/env bash
set -eu
NS="${NS:-clab-3-tier-leaf-spine-dcgw}"
kubectl patch routerinterconnect router-interconnect-vnet-2 -n "$NS" --type=json \
  -p '[{"op":"remove","path":"/spec/interconnectBGPInstance/exportTarget"}]'
