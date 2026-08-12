#!/usr/bin/env bash
# L3 VNet prerequisites: service-router BGP on DCI vnets; disable IRB host-route / EVPN-MAC adv.
#
# Default design = type-5 stitch (single-leaf-per-subnet): disable hostRoutePopulate.
# If hosts span MULTIPLE leaves on the SAME subnet, do NOT apply the IRB-disable patches
# for that vnet — enable hostRoutePopulate / related EVPN host-route params instead.
# Do not confuse that case with MSG/GBP client blocks (loopback OK / client FAIL).
set -eu
NS="${NS:-clab-3-tier-leaf-spine-dcgw}"
PATCH="$(cd "$(dirname "$0")/../services/vnets/patches" && pwd)"

echo "==> Patch vnet-1..7: disable IRB hostRoutePopulate + evpnRouteAdvertisementType (type-5 stitch default)"
for v in 1 2 3 4 5 6 7; do
  case "$v" in
    1) patch="$PATCH/vnet-1-l3-dci.json" ;;
    2) patch="$PATCH/vnet-2-l3-dci.json" ;;
    5) patch="$PATCH/vnet-5-l3-dci.json" ;;
    *) patch="$PATCH/vnet-${v}-irb-disable.json" ;;
  esac
  if kubectl get virtualnetwork "vnet-$v" -n "$NS" &>/dev/null; then
    echo "--- vnet-$v ($patch)"
    kubectl patch virtualnetwork "vnet-$v" -n "$NS" --type=json --patch-file="$patch" || true
  else
    echo "--- vnet-$v (not in namespace, skip)"
  fi
done

echo "==> Wait for service intent"
sleep 20

echo "==> VirtualNetwork state (L3 DCI vnets)"
kubectl get virtualnetworks vnet-1 vnet-2 vnet-5 -n "$NS" 2>/dev/null \
  -o custom-columns=NAME:.metadata.name,NODES:.status.nodes,STATE:.status.operationalState || true
