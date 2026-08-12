# DCI control-plane troubleshooting (EVPN vs IPVPN)

Short tech note for **SRL** (`eda-dci-lab`) and **SROS** (`eda-dci-sros-lab`) DCGW labs.


| Lab  | Namespace                     | DCGW names          | Typical RIC                         |
| ---- | ----------------------------- | ------------------- | ----------------------------------- |
| SRL  | `clab-srl-leaf-spine-dcgw`    | `dcgw-1`…`dcgw-4`   | **IPVPN**                           |
| SROS | `clab-3-tier-leaf-spine-dcgw` | `dc-gw-1`…`dc-gw-4` | **EVPN** or **IPVPN** (mode switch) |


---

## 1. Decision tree — which control plane?

```
What is RouterInterconnect.interconnectBGPInstance.controlPlane?
├─ IPVPN  → WAN should use vpnIPv4 / VPNv4 policies (IPVPN mode)
└─ EVPN   → WAN should use l2VPNEVPN / EVPN stitch policies (EVPN mode)

What is enabled on DefaultBGPPeer?
├─ vpnIPv4Unicast only  → attach IPVPN import/export pair
├─ l2VPNEVPN only       → attach EVPN import/export pair
└─ both / mixed          → avoid dual-mixed Policies; split peers or pick one mode
```

**Do not mix EVPN + IPVPN match statements in one Policy** (SROS lesson). Use mode-specific pairs.

### Policies to attach (SROS — current)


| Mode  | DC1                                               | DC2                                               |
| ----- | ------------------------------------------------- | ------------------------------------------------- |
| EVPN  | `import-dci-evpn-dc-1` / `export-dci-evpn-dc-1`   | `import-dci-evpn-dc-2` / `export-dci-evpn-dc-2`   |
| IPVPN | `import-dci-ipvpn-dc-1` / `export-dci-ipvpn-dc-1` | `import-dci-ipvpn-dc-2` / `export-dci-ipvpn-dc-2` |


Peer fields: `importPolicies` / `exportPolicies`. Details: `services/dci-policies/wan/README.md`.

### Policies (SRL — typical)


| Role         | Examples                                                               |
| ------------ | ---------------------------------------------------------------------- |
| Import       | `import-dci-services-dc-1` / `import-dci-services-dc-2`                |
| Export       | `export-dc-*-routes-and-add-soo`, `export-wan-routes-only-dc-*`        |
| Fabric block | `reject-all-local-evpn` / `reject-all-remote-evpn` **required** on SRL |


Match protocol: `BGP_IPVPN` (SRL), not SROS `BGP_VPN`.

---



## 2. Where to look on the DCGW



### Layers (both platforms)


| Layer              | What                       | Where                                                              |
| ------------------ | -------------------------- | ------------------------------------------------------------------ |
| Fabric             | Leaf/spine EVPN-VXLAN      | Inside DC; VTEPs / system IPs                                      |
| Service VRF        | Customer / stitch prefixes | SRL: `network-instance router-*` · SROS: `service vprn "router-*"` |
| Interconnect (RIC) | Leak service ↔ WAN         | Same DCGW; RT targets on RIC CR                                    |
| WAN BGP            | DCGW ↔ DCGW                | SRL/SROS: **default / Base** NI + `DefaultBGPPeer`                 |




### SROS checkpoints


| Check                        | Expect                                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| VPRN route-table             | Local fabric often **EVPN-IFL**; remote WAN often **BGP VPN**                                                                                                                                                |
| Base `vpn-ipv4` (IPVPN mode) | Sent/received/active > 0 toward WAN peer                                                                                                                                                                     |
| Base EVPN (EVPN mode)        | Stitch types/RTs only — not full remote leaf fabric                                                                                                                                                          |
| `allow-export-bgp-vpn`       | Often needed for **EVPN RIC** leak; usually **not** for **IPVPN RIC** (auto EVPN↔IPVPN when both instances present). Changes may need VPRN bounce                                                            |
| Policy match                 | Never `families:[IPv4]` for vpn-ipv4. SROS CommunitySet `matchSetOptions` = **All only** (EDA rejects `Any`); multi-member = AND → **one Accept per single-RT set**. Policy CR field = `statements` (plural) |
| Hub import                   | `import-ric-vnet-2` + `vpn-import-rt-100`/`102`. RIB-IN without VPRN install → All/AND mistake                                                                                                               |
| Loopback Interface           | **One member only** per CR (`type: Loopback`) — not multi-member                                                                                                                                               |




### SRL checkpoints


| Check     | Expect                                                               |
| --------- | -------------------------------------------------------------------- |
| WAN EVPN  | **No** remote leaf/spine system IPs (blocked by `reject-all-*-evpn`) |
| WAN VPNv4 | Stitch prefixes; NH = **remote DCGW system IP** (`nextHopSelf`)      |
| Fabric    | EVPN/VXLAN stays site-local                                          |


---



## 3. Validate MPLS vs VXLAN transport


| Domain                       | Typical transport | How to confirm                                                                         |
| ---------------------------- | ----------------- | -------------------------------------------------------------------------------------- |
| **Fabric** (leaf↔spine↔DCGW) | **VXLAN** (EVPN)  | MAC/IP routes, VTEP NH, VXLAN interfaces / tunnels                                     |
| **WAN** (DCGW↔DCGW)          | **MPLS / LDP**    | VPNv4 or EVPN over WAN with NH = DCGW system `/32`; LDP FEC / tunnel table toward peer |


**Pass (WAN MPLS):** remote stitch prefix present; BGP NH = remote DCGW system; LDP/tunnel to that `/32` in forwarding.  
**Fail pattern:** NH = remote **leaf VTEP** over WAN (fabric leak / wrong AFI/policy).

---



## 4. Command cheat sheet



### SROS (classic CLI / container)

```text
# WAN control plane
show router bgp summary
show router bgp neighbor <wan-peer-ip>
show router bgp routes vpn-ipv4
show router bgp routes vpn-ipv4 neighbor <wan-peer-ip> advertised-routes
show router bgp routes vpn-ipv4 neighbor <wan-peer-ip> received-routes
show router bgp routes evpn
show router bgp routes evpn neighbor <wan-peer-ip> summary

# Service VRF
show router "<service-name>" route-table
show router "router-1" route-table

# Underlay / MPLS
show router tunnel-table
show router ldp bindings
show router mpls lsp detail
```

gNMI (lab): family-prefix `.../bgp/neighbor[ip-address=...]/statistics/family-prefix/vpn-ipv4`.

### SRL (`sr_cli`)

```text
# WAN BGP
show network-instance default protocols bgp neighbor
show network-instance default protocols bgp routes l3vpn-ipv4-unicast summary
show network-instance default protocols bgp routes l3vpn-ipv4-unicast prefix <p>
show network-instance default protocols bgp neighbor <ip> advertised-routes evpn summary
show network-instance default protocols bgp neighbor <ip> received-routes evpn summary

# Service VRF
show network-instance router-1 route-table ipv4-unicast

# MPLS / tunnels
show network-instance default protocols ldp ipv4 fec
show network-instance default tunnel-table

# Fabric VXLAN (on leaf or DCGW as applicable)
show network-instance <ni> protocols bgp-evpn
show tunnel vxlan
```

Examples from `docs/L3VPN-DCI-GUIDE.md` / `docs/L2-DCI-GUIDE.md` (SRL) and on-box SROS shows above.

### EQL / YANG state paths (verified on `clab-3-tier-leaf-spine-dcgw`, 2026-08-12)

**Roots:** SRL = `.namespace.node.srl.`* · SROS = `.namespace.node.sros.state.*` (not `.sros.router` / `.sros.service` without `state`).  
**Autocomplete:** `GET /core/query/v1/eql/autocomplete?query=<path.>`.  
**Filter tip:** bare tables work; some `where` clauses returned empty in this lab — prefer `fields [...]` and filter on `.namespace.node.name` / NI / `service-name` client-side if needed.


| What               | SRL EQL (live)                                                                                     | SROS EQL (live)                                                                                                                                           | Notes                                                                      |
| ------------------ | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| IP route table     | `.namespace.node.srl.network-instance.route-table.ipv4-unicast.route`                              | Base: `.namespace.node.sros.state.router.route-table.unicast.ipv4.route` · VPRN: `.namespace.node.sros.state.service.vprn.route-table.unicast.ipv4.route` | Field `ipv4-prefix`. VPRN `protocol` = `evpn-ifl` / `bgp-vpn`              |
| EVPN type-5        | `...bgp-rib.afi-safi.evpn.local-rib.ip-prefix-route` (+ `rib-in-out.rib-in-post` / `rib-out-post`) | **No per-route EVPN RIB in EQL** — use CLI `show router bgp routes evpn` / neighbor `family-prefix.evpn` stats                                            | mcp-client old path missing `afi-safi` + used plural `-routes`             |
| EVPN type-2 MAC-IP | `...bgp-rib.afi-safi.evpn.local-rib.mac-ip-route` (+ rib-in/out)                                   | FDB schema: `.namespace.node.sros.state.service.vpls.fdb.mac` (0 rows if no VPLS MACs)                                                                    | Fabric type-2 on SRL leaves                                                |
| MAC table          | `...bridge-table.mac-table.mac`                                                                    | `.namespace.node.sros.state.service.vpls.fdb.mac`                                                                                                         | SRL mac-vrf                                                                |
| BGP / VPNv4        | Neighbor + EVPN RIB as above; L3VPN AFI only if present                                            | Neighbor `...bgp.neighbor.statistics.family-prefix.{evpn,vpn-ipv4}` + `...bgp.statistics.routes-per-family.{evpn,vpn-ipv4}`                               | SROS `bgp.rib` EQL has ipv4/ipv6/label only — **not** evpn/vpn-ipv4 routes |
| LDP / tunnel       | Fabric VXLAN: `.namespace.node.srl.tunnel.vxlan-tunnel.vtep`                                       | `.namespace.node.sros.state.router.ldp.bindings.active.prefixes` (+ nested `.in-label` / `.out-label`) · `.namespace.node.sros.state.router.tunnel-table.ipv4.tunnel` | WAN MPLS on SROS Base; labels are nested lists (leaf `label`)              |


**LDP binding fields (verified autocomplete + live rows, 2026-08-12):**

| Path | Useful fields |
|------|---------------|
| `...ldp.bindings.active.prefixes` | `ip-prefix`, `fec-type`, `operation-type`, `flags` |
| `...ldp.bindings.active.prefixes.in-label` | `label`, `id` (+ parent `ip-prefix` / `operation-type` keys) |
| `...ldp.bindings.active.prefixes.out-label` | `label`, `next-hop`, `interface-name`, `status`, `metric`, `mtu` |

`in-label` / `out-label` are **not** scalars on the prefixes row — query the nested tables (or `fields […, in-label, out-label]` will silently omit them).

### WAN prefix over LDP validation (SROS EVPN lab)

Practical chain (read-only EQL; ns `clab-3-tier-leaf-spine-dcgw`):

1. **Installed in VRF** — VPRN route-table (`protocol` often `evpn-ifl` for both local fabric and remote stitch on this lab):

```eql
.namespace.node.sros.state.service.vprn.route-table.unicast.ipv4.route
fields [ .namespace.node.name, .namespace.node.sros.state.service.vprn.service-name, ipv4-prefix, protocol ]
```

2. **Resolving tunnel = LDP** — nested nexthop (remote loopback / VNet `/24` should show `nexthop-tunnel-type = ldp` toward remote DCGW system IP; local fabric stays `vxlan`):

```eql
.namespace.node.sros.state.service.vprn.route-table.unicast.ipv4.route.nexthop.resolving-nexthop
```

3. **WAN advertisement (no per-route EVPN RIB in EQL)** — peer `family-prefix.evpn` counts + CLI `show router bgp routes evpn ip-prefix` (gNMI/SSH if `sr_cli` fails).

```eql
.namespace.node.sros.state.router.bgp.neighbor.statistics.family-prefix.evpn
fields [ .namespace.node.name, .namespace.node.sros.state.router.bgp.neighbor.ip-address, received, active, sent ]
```

4. **LDP FEC + labels** for that NH `/32` — tunnel-table `protocol=ldp`, then in/out label:

```eql
.namespace.node.sros.state.router.tunnel-table.ipv4.tunnel
fields [ .namespace.node.name, ipv4-prefix, protocol, next-hop, metric ]

.namespace.node.sros.state.router.ldp.bindings.active.prefixes.out-label
.namespace.node.sros.state.router.ldp.bindings.active.prefixes.in-label
```

**Live sample (`dc-gw-1` / `router-1`, 2026-08-12):** `2.2.2.2/32` + `172.16.102.0/24` → `nexthop-ip=11.0.0.14`, `nexthop-tunnel-type=ldp` (local `1.1.1.1/32` → VXLAN `11.0.0.4`). Tunnel `11.0.0.14/32` `protocol=ldp` NH `12.0.0.1`. Out-label push `label=524283`; in-label swap `label=524279`.

---



## 5. Quick isolation order

1. Confirm **RIC controlPlane** and **peer AFI** agree (EVPN vs IPVPN).
2. Confirm **correct Policy pair** attached (`importPolicies` / `exportPolicies`).
3. On DCGW: service route-table protocols + WAN RIB (vpn-ipv4 **or** EVPN).
4. Confirm WAN NH is **DCGW system**, then LDP/tunnel to that NH (MPLS) — see **WAN prefix over LDP validation** above.
5. Loopback Interface: one member per CR only

Related: `docs/L3VPN-DCI-GUIDE.md` (SRL), `docs/SROS-EVPN-DCI-GUIDE.md` (SROS), `services/dci-policies/wan/README.md` (SROS mode policies).