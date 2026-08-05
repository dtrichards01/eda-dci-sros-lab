#!/usr/bin/env bash
set -eu

echo "======== leaf-1 router-1 bgp-evpn ========"
docker exec leaf-1 sr_cli 'info from state network-instance router-1 protocols bgp-evpn bgp-instance 1' 2>&1 | head -50

echo
echo "======== leaf-1 router-1 bgp neighbors ========"
docker exec leaf-1 sr_cli 'info from state network-instance router-1 protocols bgp neighbor' 2>&1 | head -40

echo
echo "======== leaf-1 default bgp (fabric) ========"
docker exec leaf-1 sr_cli 'info from state network-instance default protocols bgp neighbor' 2>&1 | head -30

echo
echo "======== Policy deployments on dc-gw ========"
kubectl get policydeployments -n clab-3-tier-leaf-spine-dcgw 2>/dev/null | grep -iE 'export-dci|import-dci|router-interconnect' | head -20 || true
kubectl get transactionresults -n eda-system --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -8

echo
echo "======== dc-gw-1 container entry ========"
docker exec dc-gw-1 sh -c 'ls /opt/nokia 2>/dev/null; ps aux 2>/dev/null | head -5' 2>&1 | head -15
