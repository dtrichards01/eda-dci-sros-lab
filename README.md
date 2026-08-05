# EDA DCI SROS Lab

SROS **SR-1** DCGW routing policies for the localhost EDA lab (`kind-eda-demo-wsl2`).

| Item | Value |
|------|-------|
| EDA UI | https://127.0.0.1:9443 |
| kubectl context | `kind-eda-demo-wsl2` (WSL) |
| Namespace | `clab-3-tier-leaf-spine-dcgw` |
| DCGW | SROS 7750 SR-1 `25.10.r1` (`dc-gw-1` … `dc-gw-4`) |
| Fabric | SRL `26.3.1` leaves/spines |

## Why a separate repo?

[`eda-dci-lab`](https://github.com/dtrichards01/eda-dci-lab) targets **SRL DCGW** with **IPVPN** RIC control plane and `target:1:NNN` route-targets. This lab uses **EVPN** RIC on SROS and different policy match syntax (`BGP_VPN` + `families: IPv4`, RT format `target:100:100`).

**SROS does not need extra WAN policies to block remote leaf/spine system addresses** — the platform appears to restrict fabric EVPN to the local site by default. Policies here focus on **stitch RT allow-lists**, **SOO loop prevention**, and **remote tagging** — not underlay isolation.

## Service model (EVPN RIC)

| Tier | Virtual networks | Interconnect CR | Stitch RT (SROS) |
|------|------------------|-----------------|------------------|
| L3 (IRB) | `vnet-1`, `vnet-2` | `RouterInterconnect` | `target:100:100`, `target:101:101` |
| Hub/spoke | `vnet-5` on DC1 | `RouterInterconnect` | `target:102:102` |
| L2 (BD) | `vnet-3`, `vnet-4` | `BridgeDomainInterconnect` | `target:300:300` / `target:301:301` |

- **RIC:** `controlPlane: EVPN` on SROS DCGW service routers.
- **WAN:** EVPN (`l2VPNEVPN`) + **VPN-IPv4** (`vpnIPv4Unicast`) — hybrid for L3 stitch + L2 type-2/3.
- **IRB host routes:** disabled on all vnets (`hostRoutePopulate` / `evpnRouteAdvertisementType` off). Use type-5 stitch prefixes and routed loopbacks for L3 reachability testing.

## Layout

```
services/dci-policies/
  communitysets/sros-service-rts.yaml   # RT community sets (SROS format)
  policies/
    import-dci-services-dc-{1,2}.yaml   # WAN import (EVPN + BGP_VPN)
    export-dc-{1,2}-routes-and-add-soo.yaml
    export-wan-routes-only-dc-{1,2}.yaml
    multi-rt-import.yaml                # Hub RIC import
    ric/export-dci-stitch-*.yaml        # Per-vnet RIC export (EVPN types 1–5)
scripts/
  apply-dci-policies-sros.sh
  apply-vnet-l3-prereqs-sros.sh          # BGP + disable IRB host-route populate
services/vnets/patches/                  # Per-vnet JSON patches (vnet-1..7)
docs/
  SROS-EVPN-DCI-GUIDE.md
  RELATIONSHIP-TO-SRL-LAB.md
```

## Quick start (WSL)

```bash
cd ~/Documents/eda-dci-sros-lab   # or sync from Windows path
export KUBECONFIG=~/.kube/config   # kind-eda-demo-wsl2
bash scripts/apply-dci-policies-sros.sh
```

## WAN peer → policy map

| Peer (BGP CR name) | Import | Export |
|--------------------|--------|--------|
| `dcgw-1-dcgw-3-bgp-peer` | `import-dci-services-dc-1` | `export-wan-routes-only-dc-1` |
| `dcgw-2-dcgw-4-bgp-peer` | `import-dci-services-dc-1` | `export-dc-1-routes-and-add-soo` |
| `dcgw-3-dcgw-1-bgp-peer` | `import-dci-services-dc-2` | `export-wan-routes-only-dc-2` |
| `dcgw-4-dcgw-2-bgp-peer` | `import-dci-services-dc-2` | `export-dc-2-routes-and-add-soo` |

Node containers are named `dc-gw-*`; BGP peer CRs use `dcgw-*`.

See [docs/SROS-EVPN-DCI-GUIDE.md](docs/SROS-EVPN-DCI-GUIDE.md) for policy statement details.
