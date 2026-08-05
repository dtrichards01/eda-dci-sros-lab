#!/usr/bin/env bash
# Apply RouterInterconnect stitch RT targets (targets OR policies — not both per EDA).
set -eu
NS="${NS:-clab-3-tier-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POL="$ROOT/services/dci-policies"
RIC="$ROOT/services/l3/router-interconnect"

echo "==> Hub import policy (hub RIC only)"
kubectl apply -f "$POL/policies/multi-rt-import.yaml"
kubectl apply -f "$POL/policies/ric/import-dci-hub-stitch.yaml"

echo "==> RouterInterconnect (exportTarget/importTarget — no exportPolicy on spokes)"
for f in router-interconnect-vnet-1.yaml router-interconnect-vnet-2.yaml router-interconnect-vnet-5.yaml; do
  echo "--- $f ---"
  kubectl apply -f "$RIC/$f"
done

echo "==> Strip conflicting policy fields from RIC CRs (EDA: targets OR policies)"
kubectl patch routerinterconnect router-interconnect-vnet-1 -n "$NS" --type=json \
  -p='[{"op":"remove","path":"/spec/interconnectBGPInstance/exportPolicy"},{"op":"remove","path":"/spec/interconnectBGPInstance/importPolicy"}]' 2>/dev/null || true
kubectl patch routerinterconnect router-interconnect-vnet-5 -n "$NS" --type=json \
  -p='[{"op":"remove","path":"/spec/interconnectBGPInstance/exportPolicy"},{"op":"remove","path":"/spec/interconnectBGPInstance/importPolicy"}]' 2>/dev/null || true
kubectl patch routerinterconnect router-interconnect-vnet-2 -n "$NS" --type=json \
  -p='[{"op":"remove","path":"/spec/interconnectBGPInstance/exportPolicy"},{"op":"remove","path":"/spec/interconnectBGPInstance/importPolicy"}]' 2>/dev/null || true

echo "==> Wait for interconnect intent"
sleep 25

echo "==> Verify RIC"
kubectl get routerinterconnects -n "$NS" -o custom-columns=\
NAME:.metadata.name,\
IMPORT:.spec.interconnectBGPInstance.importPolicy,\
EXPORT:.spec.interconnectBGPInstance.exportPolicy,\
IT:.spec.interconnectBGPInstance.importTarget,\
ET:.spec.interconnectBGPInstance.exportTarget,\
STATE:.status.operationalState
