# DCI control-plane troubleshooting (EVPN vs IPVPN)

Short tech note for **SRL** (`eda-dci-lab`) and **SROS** (`eda-dci-sros-lab`) DCGW labs.

| Lab | Namespace | DCGW names | Typical RIC |
|-----|-----------|------------|-------------|
| SRL | `clab-srl-leaf-spine-dcgw` | `dcgw-1`…`dcgw-4` | **IPVPN** |
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

| Mode | DC1 | DC2 |
|------|-----|-----|
| EVPN | `import-dci-evpn-dc-1` / `export-dci-evpn-dc-1` | `import-dci-evpn-dc-2` / `export-dci-evpn-dc-2` |
| IPVPN | `import-dci-ipvpn-dc-1` / `export-dci-ipvpn-dc-1` | `import-dci-ipvpn-dc-2` / `export-dci-ipvpn-dc-2` |

Peer fields: `importPolicies` / `exportPolicies`. Details: `services/dci-policies/wan/README.md`.

### Policies (SRL — typical)

| Role | Examples |
|------|----------|
| Import | `import-dci-services-dc-1` / `import-dci-services-dc-2` |
| Export | `export-dc-*-routes-and-add-soo`, `export-wan-routes-only-dc-*` |
| Fabric block | `reject-all-local-evpn` / `reject-all-remote-evpn` **required** on SRL |

Match protocol: **`BGP_IPVPN`** (SRL), not SROS `BGP_VPN`.

---

## 2. Where to look on the DCGW

### Layers (both platforms)

| Layer | What | Where |
|-------|------|--------|
| Fabric | Leaf/spine EVPN-VXLAN | Inside DC; VTEPs / system IPs |
| Service VRF | Customer / stitch prefixes | SRL: `network-instance router-*` · SROS: `service vprn "router-*"` |
| Interconnect (RIC) | Leak service ↔ WAN | Same DCGW; RT targets on RIC CR |
| WAN BGP | DCGW ↔ DCGW | SRL/SROS: **default / Base** NI + `DefaultBGPPeer` |

### SROS checkpoints

| Check | Expect |
|-------|--------|
| VPRN route-table | Local fabric often **EVPN-IFL**; remote WAN often **BGP VPN** |
| Base `vpn-ipv4` (IPVPN mode) | Sent/received/active > 0 toward WAN peer |
| Base EVPN (EVPN mode) | Stitch types/RTs only — not full remote leaf fabric |
| `allow-export-bgp-vpn` | Often needed for **EVPN RIC** leak; usually **not** for **IPVPN RIC** (auto EVPN↔IPVPN when both instances present). Changes may need VPRN bounce |
| Policy match | Never `families:[IPv4]` for vpn-ipv4. SROS CommunitySet `matchSetOptions` = **All only** (EDA rejects `Any`); multi-member = AND → **one Accept per single-RT set**. Policy CR field = **`statements`** (plural) |
| Hub import | `import-ric-vnet-2` + `vpn-import-rt-100`/`102`. RIB-IN without VPRN install → All/AND mistake |
| Client FAIL / loopback OK | Check **MSG/GBP** (`MicroSegmentationPolicy` targeting `vnet-1`) before IRB |
| Multi-leaf same subnet | Hosts on multiple leaves of one subnet need IRB **`hostRoutePopulate`** / related EVPN host-route params (fabric host reachability) — orthogonal to GBP |
| Loopback Interface | **One member only** per CR; multi-member rejected by Interfaces app (`more than one members are provided for type [loopback]`) |

### SRL checkpoints

| Check | Expect |
|-------|--------|
| WAN EVPN | **No** remote leaf/spine system IPs (blocked by `reject-all-*-evpn`) |
| WAN VPNv4 | Stitch prefixes; NH = **remote DCGW system IP** (`nextHopSelf`) |
| Fabric | EVPN/VXLAN stays site-local |

---

## 3. Validate MPLS vs VXLAN transport

| Domain | Typical transport | How to confirm |
|--------|-------------------|----------------|
| **Fabric** (leaf↔spine↔DCGW) | **VXLAN** (EVPN) | MAC/IP routes, VTEP NH, VXLAN interfaces / tunnels |
| **WAN** (DCGW↔DCGW) | **MPLS / LDP** | VPNv4 or EVPN over WAN with NH = DCGW system `/32`; LDP FEC / tunnel table toward peer |

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

---

## 5. Quick isolation order

1. Confirm **RIC controlPlane** and **peer AFI** agree (EVPN vs IPVPN).
2. Confirm **correct Policy pair** attached (`importPolicies` / `exportPolicies`).
3. On DCGW: service route-table protocols + WAN RIB (vpn-ipv4 **or** EVPN).
4. Confirm WAN NH is **DCGW system**, then LDP/tunnel to that NH (MPLS).
5. If loopback OK but client FAIL (SROS): check **GBP/MSG** before IRB.
6. Multi-leaf hosts on same subnet: confirm IRB host-route populate is enabled (separate from GBP).
7. Loopback Interface: one node/member per CR — do not multi-member.

Related: `docs/L3VPN-DCI-GUIDE.md` (SRL), `docs/SROS-EVPN-DCI-GUIDE.md` (SROS), `services/dci-policies/wan/README.md` (SROS mode policies).
