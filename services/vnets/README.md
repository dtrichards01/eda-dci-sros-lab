# VNet patches

JSON patches applied by `scripts/apply-vnet-l3-prereqs-sros.sh` to `VirtualNetwork` CRs in the lab namespace.

## Policy

**Disable** on every IRB-backed vnet (`vnet-1` … `vnet-7`):

| Field | Setting |
|-------|---------|
| `hostRoutePopulate.dynamic.populate` | `false` |
| `hostRoutePopulate.evpn.populate` | `false` |
| `hostRoutePopulate.evpn.datapathProgramming` | `false` |
| `hostRoutePopulate.static.populate` | `false` |
| `evpnRouteAdvertisementType.arpDynamic` | `false` |
| `evpnRouteAdvertisementType.arpStatic` | `false` |
| `evpnRouteAdvertisementType.ndDynamic` | `false` |
| `evpnRouteAdvertisementType.ndStatic` | `false` |

L3 DCI reachability uses **stitch route-target type-5** prefixes (subnet and optional loopback `/32` routes on `routedInterfaces`). Fabric EVPN type-2 host MAC/IP ads are not used for WAN stitch.

## Patch files

| File | VNet | Notes |
|------|------|-------|
| `vnet-1-l3-dci.json` | vnet-1 | DC1 spoke + BGP AS 65401 + IRB disable |
| `vnet-2-l3-dci.json` | vnet-2 | DC2 hub + BGP AS 65402 + IRB disable |
| `vnet-3-irb-disable.json` | vnet-3 | L2 BDI — patch only if IRB exists |
| `vnet-4-irb-disable.json` | vnet-4 | L2 BDI — patch only if IRB exists |
| `vnet-5-l3-dci.json` | vnet-5 | DC1 spoke IRB disable |
| `vnet-6-irb-disable.json` | vnet-6 | IRB disable (if deployed) |
| `vnet-7-irb-disable.json` | vnet-7 | IRB disable (if deployed) |
| `irb-disable-host-evpn-adv.json` | — | Shared IRB-disable fragment (reference) |

Patches use `replace` on paths that must already exist on the `VirtualNetwork` CR (after initial EDA deploy). Apply on the platform via the script or `kubectl patch` per vnet.

## Apply

```bash
bash scripts/apply-vnet-l3-prereqs-sros.sh
```

The script skips vnets not present in the namespace.
