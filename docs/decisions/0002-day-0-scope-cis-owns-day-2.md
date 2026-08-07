# 0002: Scope stops at CIS-ready; application delivery belongs to CIS, permanently

**Status:** accepted
**Date:** 2026-08-06

## Context

`terraform-provider-bigip` ships roughly eighty resources. They fall into two populations with
opposite lifecycles.

**Day-0 onboarding** — `sys_provision`, `sys_bigiplicense`, `sys_dns`, `sys_ntp`, `net_vlan`,
`net_selfip`, `net_route`, `cm_device`, `cm_devicegroup`, `partition`. Applied once per
appliance, owned by the platform.

**Day-2 application delivery** — `ltm_pool`, `ltm_node`, `ltm_virtual_server`, `ltm_monitor`, the
profile family, `ltm_policy`, `ltm_irule`, `ssl_*`, and the whole `gtm_*` family. Applied
continuously, once per application onboarded.

In this estate the second population already has an owner. F5 Container Ingress Services is
deployed through the NKP platform catalogue — `nkp-platform-apps` is registered in
`module/config/bingamon-nkp/nkp/nkp-mgmt-dev.yaml` as _"SOE applications — the ones every cluster
gets, F5 BIG-IP among them"_. CIS watches Kubernetes `Service` and `Ingress` objects and creates
virtual servers, pools and nodes to match.

Two controllers writing the same LTM objects is not a scoping preference — it is a fight. CIS
reconciles continuously against cluster state; Terraform reconciles against a state file. Each
would revert the other, on its own schedule, and the resulting flapping would be attributed to
whichever ran most recently.

## Decision

**This module carries a BIG-IP from booted OVA to CIS-ready, and stops.**

MVP renders these DO classes: tenant-level `hostname`, `License`, `Provision`, `DNS`, `NTP`
(which also carries the timezone, per the DO schema), `VLAN`, `SelfIp`, `Route`, `User`, and — because an HA pair is in scope from the start
(ADR 0003) — `DeviceTrust`, `DeviceGroup`, `ConfigSync`. Plus `bigip_partition` imperatively, the
seam CIS is pointed at.

`NTP` is not optional padding. Device trust fails on clock skew, so an unsynchronised pair fails
to form a device group with an error that does not mention time.

**Deferred to v0.2+** — additive to the same renderer, not a redesign: `ManagementRoute`,
`RouteDomain`, `Trunk`, `SnmpAgent`, `SnmpTrapDestination`, `SnmpUser`, `SyslogRemoteServer`,
`HTTPD`, `SSHD`, `Authentication` + `RemoteAuthRole` (LDAP/AD), `TrafficControl`, `DagGlobals`,
`FirewallPolicy`.

**Never in this module** — not "later", but out of scope by design: every `ltm_*` resource, every
`gtm_*` resource, `bigip_as3`, `bigip_fast_*`, `bigip_waf_policy`, `bigip_vcmp_guest`.

The boundary is the partition. Terraform creates it and hands over the credentials; everything
inside it is CIS's.

## Consequences

- **The two controllers cannot collide**, because their object sets are disjoint and the boundary
  is enforced by a partition rather than by convention.
- **A licence key is now a module input.** `License` is in MVP, sourced as a regKey from SOPS
  (lz-paas ADR 0031). It is also the input most likely to fail badly: a wrong key fails minutes
  into an onboarding run, from the appliance, with a message that does not name the field.
- **GTM/DNS load balancing is unavailable through this module.** If the estate ever wants it,
  that is a new decision about a new owner, not an extension of this one.
- **"Ready for NKP" is a testable claim** — licensed, provisioned with LTM, VLANs and self-IPs
  up, routed, time-synchronised, partition present, CIS account able to authenticate into it.
  `docs/spec.md` states it as the acceptance condition.
- **The deferred list is genuinely deferred.** SNMP, syslog and SSH hardening are lab hygiene the
  estate will want; they are not on the path to CIS-ready and do not block v0.1.0.

## Re-evaluation trigger

- The estate needs a virtual server that CIS cannot express — a non-Kubernetes workload fronted
  by the same appliance. That is a real gap, and the answer is most likely a _separate_ module
  with its own partition, not widening this one.
- CIS is dropped from the platform catalogue, removing the second controller and with it the
  reason the boundary exists.
- F5 ships Day-0 onboarding inside CIS, which would make this module redundant rather than
  merely bounded.
