#!/usr/bin/env bash
# Apply SROS EVPN DCI policies to localhost kind lab (clab-3-tier-leaf-spine-dcgw).
set -eu
NS="${NS:-clab-3-tier-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")/../services/dci-policies" && pwd)"

echo "==> Namespace: $NS"
kubectl config current-context

echo "==> Community sets (SROS RT format)"
kubectl apply -f "$DIR/communitysets/"

echo "==> RIC stitch export + hub import"
kubectl apply -f "$DIR/policies/multi-rt-import.yaml"
kubectl apply -f "$DIR/policies/ric/"

echo "==> WAN import/export policies"
kubectl apply -f "$DIR/policies/import-dci-services-dc-1.yaml"
kubectl apply -f "$DIR/policies/import-dci-services-dc-2.yaml"
kubectl apply -f "$DIR/policies/export-wan-routes-only-dc-1.yaml"
kubectl apply -f "$DIR/policies/export-wan-routes-only-dc-2.yaml"
kubectl apply -f "$DIR/policies/export-dc-1-routes-and-add-soo.yaml"
kubectl apply -f "$DIR/policies/export-dc-2-routes-and-add-soo.yaml"

if [[ "${PATCH_PEERS:-1}" == "1" ]]; then
  echo "==> Patch DCI BGP peers (primary/secondary export split)"
  # BGP peer CR names (dcgw-*-bgp-peer) — node names may be dc-gw-* on SROS containers.
  kubectl patch defaultbgppeer dcgw-1-dcgw-3-bgp-peer -n "$NS" --type=json \
    --patch-file="$DIR/bgp-peers/dcgw-1-dcgw-3-import-export-patch.json" || true
  kubectl patch defaultbgppeer dcgw-2-dcgw-4-bgp-peer -n "$NS" --type=json \
    --patch-file="$DIR/bgp-peers/dcgw-2-dcgw-4-import-export-patch.json" || true
  kubectl patch defaultbgppeer dcgw-3-dcgw-1-bgp-peer -n "$NS" --type=json \
    --patch-file="$DIR/bgp-peers/dcgw-3-dcgw-1-import-export-patch.json" || true
  kubectl patch defaultbgppeer dcgw-4-dcgw-2-bgp-peer -n "$NS" --type=json \
    --patch-file="$DIR/bgp-peers/dcgw-4-dcgw-2-import-export-patch.json" || true
  for peer in dcgw-1-dcgw-3-bgp-peer dcgw-2-dcgw-4-bgp-peer \
              dcgw-3-dcgw-1-bgp-peer dcgw-4-dcgw-2-bgp-peer; do
    kubectl patch defaultbgppeer "$peer" -n "$NS" --type=json \
      --patch-file="$DIR/bgp-peers/wan-enable-vpnv4-patch.json" || true
  done
fi

echo "==> Status"
kubectl get communitysets -n "$NS" 2>/dev/null | grep -E 'dci-rt|vpn-import' || true
kubectl get policies.routingpolicies.eda.nokia.com -n "$NS" 2>/dev/null \
  | grep -E 'import-dci|export-dc|export-wan|multi-rt|export-dci-stitch' || \
  kubectl get policy -n "$NS" 2>/dev/null | grep -E 'import-dci|export-dc|export-wan|multi-rt|export-dci-stitch' || true

echo "==> VNet L3 prerequisites (BGP on DCI vnets; disable IRB host-route populate)"
bash "$(dirname "$0")/apply-vnet-l3-prereqs-sros.sh"

echo "==> RouterInterconnect stitch policies"
bash "$(dirname "$0")/apply-ric-policies-sros.sh"

echo "Done."
