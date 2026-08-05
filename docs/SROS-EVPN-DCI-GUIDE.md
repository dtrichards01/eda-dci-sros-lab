# SROS EVPN DCI Policy Guide

Policies for **SROS SR-1 DCGW** in `clab-3-tier-leaf-spine-dcgw` with **EVPN RIC** control plane.

## SROS vs SRL (eda-dci-lab)

| Topic | SRL (`eda-dci-lab`) | SROS (this repo) |
|-------|---------------------|------------------|
| RIC `controlPlane` | `IPVPN` | `EVPN` |
| RT format | `target:1:100` | `target:100:100` |
| VPN route match | `protocol: BGP_IPVPN` | `protocol: BGP_VPN` + `families: [IPv4]` |
| WAN fabric leak | Needs `reject-all-local/remote-evpn` | **Not required** — remote WAN RIB shows DCGW system IPs only |
| Namespace | `clab-srl-leaf-spine-dcgw` | `clab-3-tier-leaf-spine-dcgw` |
| DCGW nodes | `dcgw-1` … `dcgw-4` | `dc-gw-1` … `dc-gw-4` |

## Underlay / fabric isolation

On SRL Talos lab, WAN export policies use blanket `reject-all-local-evpn` / `reject-all-remote-evpn` to stop fabric EVPN (leaf/spine system routes, IMET, etc.) from crossing the DCI.

**On SROS SR-1 this is unnecessary.** Observed behavior on the localhost lab:

- Remote WAN EVPN RIB contains **remote DCGW system addresses** (expected for underlay reachability).
- Remote **leaf/spine** fabric EVPN does **not** appear on the WAN path without explicit policy to allow it.

Policies here use **positive stitch-RT matching** plus SOO/tag loop prevention — not fabric deny-lists.

## Community sets

| Name | Members | Use |
|------|---------|-----|
| `dci-rt-dc1-l3` | `target:100:100` | vnet-1 stitch |
| `dci-rt-dc2-l3` | `target:101:101` | vnet-2 / hub stitch |
| `dci-rt-vnet-5-stitch` | `target:102:102` | vnet-5 spoke |
| `dci-rt-l2-export-dc1` | `target:300:300` | vnet-3 BDI export |
| `dci-rt-l2-export-dc2` | `target:301:301` | vnet-4 BDI export |
| `dci-rt-l2-import-dc1` | `target:301:301` | DC1 imports remote L2 |
| `dci-rt-l2-import-dc2` | `target:300:300` | DC2 imports remote L2 |
| `vpn-import-rts` | `100:100`, `102:102` | Hub `multi-rt-import` |

SOO sets (`soo-1122`, `soo-2211`) and tag sets (`tag-10`, `tag-20`) are expected to exist in the namespace from the base lab deployment.

## Interconnect ↔ default leak (critical for L3 WAN)

On **EVPN RIC** (this lab — do not switch to IPVPN), stitch routes live in the service-router interconnect BGP instance. WAN BGP peers attach to the **default** network instance (`system0`).

Use **`exportTarget` / `importTarget`** on spoke `RouterInterconnect` CRs — EDA leaks tagged routes between interconnect and `default` so WAN export policies can match them.

**EDA constraint:** on a single RIC, use **either** `importTarget`/`exportTarget` **or** `importPolicy`/`exportPolicy` — **not both**. Spokes use RT targets only; hub vnet-2 uses `exportTarget` + `importPolicy: multi-rt-import` (no `importTarget`).

The `export-dci-stitch-*` policies remain in the repo for optional/draft use but are **not** attached to live RIC CRs when using RT targets.

**VNet prerequisites on leaves** (see `scripts/apply-vnet-l3-prereqs-sros.sh`): enable service-router BGP on L3 DCI vnets (`vnet-1`, `vnet-2`). **Disable** IRB `hostRoutePopulate` and `evpnRouteAdvertisementType` on all IRB vnets (`vnet-1` … `vnet-7` where present). L3 DCI uses stitch RT type-5 prefixes (and optional loopback `/32` routes); fabric type-2 host MAC/IP advertisement is intentionally off.

## WAN BGP address families

| AFI | Setting |
|-----|---------|
| `l2VPNEVPN` | **true** on all four WAN peers |
| `vpnIPv4Unicast` | **true** on all four WAN peers (L3 stitch via `BGP_VPN`) |

## WAN import (`import-dci-services-dc-1`)

Applied on DC1 DCI BGP peers (`dc-gw-1`, `dc-gw-2`).

| # | Statement | Action |
|---|-----------|--------|
| 1 | EVPN + `soo-1122` | Reject (same-site loop) |
| 2 | EVPN type-2 + `dci-rt-l2-import-dc1` | Accept, tag `tag-20` |
| 3 | EVPN type-3 + `dci-rt-l2-import-dc1` | Accept, tag `tag-20` |
| 4 | EVPN types 1–5 + `dci-rt-dc2-l3` | Accept, tag `tag-20` |
| 5 | EVPN types 1–5 + `dci-rt-vnet-5-stitch` | Accept, tag `tag-20` |
| 6 | All other EVPN | Reject |
| 7 | `BGP_VPN` + IPv4 + `dci-rt-dc2-l3` | Accept, tag `tag-20` |

`import-dci-services-dc-2` mirrors with DC2 SOO (`soo-2211`), tag `tag-10`, and DC1 RTs.

## WAN export (`export-dc-1-routes-and-add-soo`)

Secondary link (e.g. `dc-gw-2` ↔ `dc-gw-4`). **No** `reject-all-local-evpn` — SROS does not leak fabric EVPN to WAN by default.

| # | Statement | Action |
|---|-----------|--------|
| 1 | Imported EVPN + `tag-20` | Reject |
| 2 | Imported `BGP_VPN` IPv4 + `tag-20` | Reject |
| 3 | Local EVPN type-2 + `dci-rt-l2-export-dc1` | Accept + SOO |
| 4 | Local EVPN type-3 + `dci-rt-l2-export-dc1` | Accept + SOO |
| 5 | Local EVPN types 1–5 + `dci-rt-dc1-l3` | Accept + SOO |
| 6 | Local EVPN types 1–5 + `dci-rt-vnet-5-stitch` | Accept + SOO |
| 7 | Local `BGP_VPN` IPv4 + stitch RTs | Accept + SOO |

Primary links use `export-wan-routes-only-dc-*` (reject locally tagged routes, accept imported remote).

## RIC export (`export-dci-stitch-dc1-vnet-1`)

Attached on `RouterInterconnect` for vnet-1. Exports **local** EVPN types **1–5** from the service router (no stitch-RT match on input). The stitch route-target (`target:100:100`, `target:101:101`, `target:102:102`, …) is applied by **`exportTarget` on the RIC CR**, not by the export policy match. WAN import/export policies then match those stitch RTs after interconnect ↔ default leak.

## Hub (`router-interconnect-vnet-2`)

On **EVPN RIC / SROS DCGW**, `importPolicy: multi-rt-import` does **not** import spoke routes into `router-2` (same class of issue as SRL DCGW — see `eda-dci-lab` `import-dci-hub-spoke-stitch` warning). Use **`importTarget: target:100:100`** for vnet-1 spoke import.

EDA allows only **one** `importTarget` per RIC. A second spoke RT (`target:102:102` for vnet-5) cannot be added via a second `RouterInterconnect` on the same `router-2` (transaction failure). vnet-5 ↔ hub over WAN may require a future EDA fix or IPVPN hub import; vnet-5 spoke still imports hub `target:101:101` via its own RIC.

**WAN export (DC1):** local stitch routes are exported on **`dcgw-1-dcgw-3`** (`export-dc-1-routes-and-add-soo`); `dcgw-2-dcgw-4` uses `export-wan-routes-only-dc-1` for imported remote routes.

## Apply order

1. Community sets
2. RIC stitch export + hub import policies
3. WAN import/export policies
4. Patch BGP peers (see `scripts/apply-dci-policies-sros.sh`)
