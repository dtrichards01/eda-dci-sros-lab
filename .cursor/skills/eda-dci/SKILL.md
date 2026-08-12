---
name: eda-dci
description: >-
  Nokia EDA DCI lab work — SRL IPVPN and SROS EVPN routing policies, vnet stitch
  RTs, WAN BGP, IRB prerequisites, client connectivity debugging, and Talos/clab
  topology. Use for eda-dci-lab, eda-dci-sros-lab, eda-dci-evpn-lab, cross-DC
  ping failures, RouterInterconnect, community sets, SOO/tag policies, platform
  restore, eda-platform-restore.sh. Not for branch vcluster / CX / Talos rebuild
  work (use eda-branch).
---

# EDA DCI — SROS lab notes (repo skill)

Full cross-lab skill: `~/.cursor/skills/eda-dci/`.

## SROS-specific rules

- No `reject-all-local-evpn` on WAN — fabric EVPN does not leak by default
- **Hub vnet-2 import:** `import-ric-vnet-2` + `vpn-import-rt-100` / `vpn-import-rt-102` (one Accept per RT). SROS CommunitySet is **All only** (no `Any`); multi-member All = AND. Policy field = **`statements`**. Do not use multi-member `vpn-import-rts` for OR import.
- RIC: targets **or** policies, never both on same interconnect (hub: `exportTarget` + `importPolicy`)
- **Client↔client blocked while loopbacks work:** MSG/GBP on `vnet-1` (`red-blue-green`)
- **Loopback Interface:** one member only (`type: Loopback`). App rejects multi-member (`more than one members are provided for type [loopback]`, tx `4570`). Anycast → separate Interface CRs + separate VN `routedInterfaces`. Clean: `loopback01`→leaf-1 (`1.1.1.1`), `loopback02`→leaf-5 (`2.2.2.2`).
- **Multi-leaf same subnet:** enable IRB `hostRoutePopulate` / related EVPN host-route params for host reachability — **not** a substitute for the GBP golden rule.
- **Do not mix EVPN + IPVPN in one Policy.** Use mode pairs under `services/dci-policies/wan/policies/`:
  - EVPN: `import-dci-evpn-dc-{1,2}` / `export-dci-evpn-dc-{1,2}`
  - IPVPN: `import-dci-ipvpn-dc-{1,2}` / `export-dci-ipvpn-dc-{1,2}`
- Peer fields: **`importPolicies` / `exportPolicies`**. No Policy `metadata.annotations`.
- Never `families:[IPv4]` for vpn-ipv4; never `BGP_IPVPN` on SROS.
- **`allow-export-bgp-vpn`:** conditional (EVPN RIC / missing leak); usually not needed under IPVPN RIC.
- `*-dual` and legacy mixed policies are **obsolete**.
- Tech note: `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` (EVPN vs IPVPN, DCGW checks, CLI).

## Keep this skill updated

Update this file and `~/.cursor/skills/eda-dci/` (Windows + WSL `/home/clab/.cursor/skills/eda-dci/`) when lessons change.
