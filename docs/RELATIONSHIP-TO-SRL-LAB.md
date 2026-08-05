# Relationship to eda-dci-lab (SRL)

| Repo | Platform | Control plane | Primary use |
|------|----------|---------------|-------------|
| [eda-dci-lab](https://github.com/dtrichards01/eda-dci-lab) | SRL DCGW | IPVPN RIC | Production-style L3 VPNv4 + L2 EVPN hybrid on Talos |
| **eda-dci-sros-lab** | SROS SR-1 DCGW | EVPN RIC | Localhost kind lab — EVPN-centric stitch policies |
| [eda-dci-evpn-lab](../eda-dci-evpn-lab) | SRL (trial) | EVPN RIC | Paused — platform gaps on L3 EVPN |

## What transfers directly

- Service topology (vnet-1..5, BDI 300/301, SOO values, tag-10/20 loop model)
- Policy *intent* (stitch RT allow-list, SOO on export, remote tagging on import)
- WAN primary/secondary split (`export-wan-routes-only` vs `export-dc-*-routes-and-add-soo`)

## What must change for SROS

1. **Namespace** → `clab-3-tier-leaf-spine-dcgw`
2. **RT format** → `target:100:100` not `target:1:100`
3. **VPN match** → `BGP_VPN` + `families: [IPv4]`
4. **RIC policies** → EVPN types 1–5 on export (not IPVPN-only)
5. **Fabric isolation** → omit `reject-all-local/remote-evpn` on WAN (SROS default behavior)
6. **BGP peer CR names** → `dcgw-*-bgp-peer` (node containers may be `dc-gw-*`)

## Sync workflow

Develop policies here against localhost SROS lab. Once validated, port *concepts* back to `eda-dci-lab` only where the SRL IPVPN model needs the same stitch behavior (e.g. L2 type-2/3 rules).
