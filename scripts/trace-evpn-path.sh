#!/usr/bin/env bash
set -eu
NS=clab-3-tier-leaf-spine-dcgw

echo "======== VirtualNetwork nodes ========"
kubectl get virtualnetworks vnet-1 vnet-2 vnet-5 -n "$NS" \
  -o custom-columns=NAME:.metadata.name,NODES:.status.nodes,STATE:.status.operationalState

echo
echo "======== RouterInterconnect ========"
kubectl get routerinterconnects -n "$NS" \
  -o custom-columns=NAME:.metadata.name,CP:.spec.interconnectBGPInstance.controlPlane,NODES:.status.nodes,STATE:.status.operationalState

echo
echo "======== leaf-1 router-1 ========"
docker exec leaf-1 sr_cli 'info from state network-instance router-1 protocols bgp oper-state' 2>&1 || true
docker exec leaf-1 sr_cli 'info from state network-instance router-1 protocols bgp neighbor * session-state' 2>&1 | head -20 || true
docker exec leaf-1 sr_cli 'info from state network-instance router-1 route-table ipv4-unicast route * active' 2>&1 | head -25 || true

echo
echo "======== leaf-8 router-2 ========"
docker exec leaf-8 sr_cli 'info from state network-instance router-2 protocols bgp oper-state' 2>&1 || true
docker exec leaf-8 sr_cli 'info from state network-instance router-2 route-table ipv4-unicast route * active' 2>&1 | head -15 || true

echo
echo "======== WAN BGP peers ========"
kubectl get defaultbgppeers -n "$NS" \
  -o custom-columns=NAME:.metadata.name,EXPORT:.spec.exportPolicies,EVPN:.spec.l2VPNEVPN.enabled,VPN:.spec.vpnIPv4Unicast.enabled,STATE:.status.sessionState
