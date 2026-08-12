# SROS EVPN DCI Policy Guide

Policies for **SROS SR-1 DCGW** in `clab-3-tier-leaf-spine-dcgw` with **EVPN RIC** control plane.

## SROS vs SRL (eda-dci-lab)

| Topic | SRL (`eda-dci-lab`) | SROS (this repo) |
|-------|---------------------|------------------|
| RIC `controlPlane` | `IPVPN` | `EVPN` |
| RT format | `target:1:100` | `target:100:100` |
| VPN route match | `protocol: BGP_IPVPN` (no family needed) | `BGP_VPN` / community, **no** `families:[IPv4]` (EDA has no vpn-ipv4 enum; IPv4≠vpn-ipv4). Never `BGP_IPVPN` on SROS. |
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
| `vpn-import-rt-100` | `target:100:100` | Hub RIC import (vnet-1) — **single-RT set** |
| `vpn-import-rt-102` | `target:102:102` | Hub RIC import (vnet-5) — **single-RT set** |

**Do not** use multi-member `vpn-import-rts` with `All` for hub OR-import on SROS (AND semantics; routes may sit in RIB-IN but not install). EDA rejects `matchSetOptions: Any` on SROS. Policy CR field is **`statements`** (plural).

SOO sets (`soo-1122`, `soo-2211`) and tag sets (`tag-10`, `tag-20`) are expected to exist in the namespace from the base lab deployment.

## Interconnect ↔ default leak (critical for L3 WAN)

Stitch routes live in the service-router interconnect BGP instance. WAN BGP peers attach to the **default** network instance (`system0`).

**EDA constraint:** on a single RIC, use **either** `importTarget`/`exportTarget` **or** `importPolicy`/`exportPolicy` — **not both**.

| RIC | Pattern |
|-----|---------|
| Spokes (vnet-1, vnet-5) | **Targets only** — `exportTarget` / `importTarget` (hub RT `101:101`) |
| Hub (vnet-2) | `exportTarget: target:101:101` + **`importPolicy: import-ric-vnet-2`** (no `importTarget`). Policy Accepts via `vpn-import-rt-100` and `vpn-import-rt-102` |

YAML: `services/dci-policies/policies/ric/import-ric-vnet-2.yaml`, `services/dci-policies/communitysets/vpn-import-rts.yaml` (defines the two single-RT sets).

The `export-dci-stitch-*` policies remain in the repo for optional/draft use but are **not** attached to live RIC CRs when using RT targets.

**VNet prerequisites on leaves** (see `scripts/apply-vnet-l3-prereqs-sros.sh`): enable service-router BGP on L3 DCI vnets (`vnet-1`, `vnet-2`). **Disable** IRB `hostRoutePopulate` and `evpnRouteAdvertisementType` on all IRB vnets (`vnet-1` … `vnet-7` where present) for the default **type-5 stitch** design (single-leaf-per-subnet + stitch prefixes / optional loopback `/32`). Fabric type-2 host MAC/IP advertisement is intentionally off in that design.

**Exception — multi-leaf same subnet:** when hosts span **multiple leaves on the same** L2/L3 subnet, **enable** IRB host-route populate / related EVPN host-route settings so host routes are advertised between leaves. Do **not** confuse this with loopback-OK / client-FAIL from **MSG/GBP** — check MicroSegmentation first for that symptom.

### Loopback Interface CRs (UI/API trap)

`type: Loopback` Interface CRs accept **only one member**. The Interfaces app rejects multi-member with `more than one members are provided for type [loopback]` (example tx `4570` on `loopback01` when adding `leaf-4/lo0` beside `leaf-1`). CRD OpenAPI allows a members list; the app script enforces one. Anycast `/32` on another leaf: create a **second** single-member Loopback Interface + a second VirtualNetwork `routedInterfaces` entry — do not multi-member one CR. Clean lab: `loopback01` → leaf-1 (`1.1.1.1`); `loopback02` → leaf-5 (`2.2.2.2`).

## WAN BGP address families (dual lab)

| AFI | Setting |
|-----|---------|
| `vpnIPv4Unicast` | **true** on WAN peers (L3 stitch) |
| `l2VPNEVPN` | often **disabled** on vpn-ipv4-only peers in dual lab — do **not** enable IPv4 AFI |

## Dual WAN policies (`*-dual`) — lessons

- VPRN: local = **EVPN-IFL**, remote = **BGP VPN**
- EDA `families` enum has **no vpn-ipv4**; never use `families:[IPv4]` for those peers
- SROS CommunitySet `matchSetOptions` is **All only** (no `Any`). Multi-member All = AND → **one single-member set + one Accept per RT**
- Never `BGP_IPVPN` on SROS; use `BGP_VPN` / community without family
- Prefer `defaultAction: Reject` with explicit Accepts
- Structure: **mode-specific** — EVPN-only or IPVPN-only Policies (no dual mix). See `services/dci-policies/wan/README.md`
- **`allow-export-bgp-vpn`:** conditional (EVPN RIC / leak missing). IPVPN RIC often works without
- No Policy `metadata.annotations`

## WAN import (`import-dci-services-dc-1-dual`)

Applied on DC1 DCI BGP peers (`dc-gw-1`, `dc-gw-2`).

| Block | Statement intent | Action |
|-------|------------------|--------|
| EVPN top | Own SOO (`soo-1122`) | Reject |
| EVPN top | L2 types 2–3 + import RTs | Accept + `tag-20` |
| EVPN top | L3 types 1–5 + stitch RTs | Accept + `tag-20` |
| EVPN top | All other EVPN | Reject |
| IPVPN bottom | Own SOO + `BGP_VPN` | Reject |
| IPVPN bottom | `BGP_VPN` / community per single RT | Accept + `tag-20` |

`import-dci-services-dc-2-dual` mirrors with `soo-2211` / `tag-10`.

## WAN export local (`export-dc-1-routes-and-add-soo-dual`)

On **`dcgw-1-dcgw-3`** (dc-gw-1). **EVPN top / IPVPN bottom**, `defaultAction: Reject`.

| Block | Statement intent | Action |
|-------|------------------|--------|
| EVPN | Imported EVPN + `tag-20` | Reject |
| EVPN | Local L2/L3 typed + export RTs | Accept + SOO |
| IPVPN | Imported `BGP_VPN` + `tag-20` | Reject |
| IPVPN | Local stitch RTs (`dci-rt-dc1-l3`, `dci-rt-vnet-5-stitch`) via `BGP_VPN` and community-only | Accept + SOO |

**dc-gw-2** (`dcgw-2-dcgw-4`) uses `export-wan-routes-only-dc-1-dual`: Accept import-tagged remotes (`tag-20`) only; default Reject.

## RIC export (`export-dci-stitch-dc1-vnet-1`)

Attached on `RouterInterconnect` for vnet-1. Exports **local** EVPN types **1–5** from the service router (no stitch-RT match on input). The stitch route-target (`target:100:100`, `target:101:101`, `target:102:102`, …) is applied by **`exportTarget` on the RIC CR**, not by the export policy match. WAN import/export policies then match those stitch RTs after interconnect ↔ default leak.

## Hub (`router-interconnect-vnet-2`)

On **EVPN RIC / SROS DCGW**, `importPolicy: multi-rt-import` does **not** import spoke routes into `router-2` (same class of issue as SRL DCGW — see `eda-dci-lab` `import-dci-hub-spoke-stitch` warning). Use **`importTarget: target:100:100`** for vnet-1 spoke import.

EDA allows only **one** `importTarget` per RIC. A second spoke RT (`target:102:102` for vnet-5) cannot be added via a second `RouterInterconnect` on the same `router-2` (transaction failure). vnet-5 ↔ hub over WAN may require a future EDA fix or IPVPN hub import; vnet-5 spoke still imports hub `target:101:101` via its own RIC.

## Apply order

1. Community sets
2. Configlets `allow-export-bgp-vpn-*` **if** EVPN RIC and vpn-ipv4 leak missing (skip under working IPVPN RIC)
3. RIC stitch export + hub import policies (if used)
4. WAN import/export `*-dual` policies
5. Patch BGP peers to `*-dual` names
