#!/usr/bin/env bash
set -eu
for c in dc-gw-1 dc-gw-2 dc-gw-3 dc-gw-4; do
  echo "======== $c ========"
  docker exec "$c" sr_cli -c "show router bgp summary" 2>&1 | head -20 || true
  echo "--- evpn routes (grep target) ---"
  docker exec "$c" sr_cli -c "show router bgp routes evpn-ipv4 detail" 2>&1 | grep -E "target:|Route Type|MAC|IP Prefix|Advertised|Received" | head -30 || true
  echo "--- vpn-ipv4 ---"
  docker exec "$c" sr_cli -c "show router bgp routes vpn-ipv4 detail" 2>&1 | grep -E "target:|Prefix|Advertised|Received" | head -20 || true
done
