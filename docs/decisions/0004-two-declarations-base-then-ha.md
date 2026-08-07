# 0004: Two DO resources — `base`, then `ha` gated behind it

**Status:** accepted
**Date:** 2026-08-06

## Context

An HA pair is in scope from the MVP (ADR 0003), and each module instance renders a declaration
for one appliance. That creates a sequencing problem the module has to answer rather than leave
to the caller.

Device trust cannot form until **both** peers have their VLANs and self-IPs up — trust is
established over a self-IP, which does not exist until the base onboarding lands. But
`bigip_do` applies asynchronously (the provider polls the DO task endpoint until it completes),
so two module instances applying concurrently will each assert trust against a peer that may not
yet be configured.

A single declaration per device cannot express that ordering. Both instances contain everything,
both start at once, and whether trust forms depends on which appliance happened to finish its
VLAN configuration first.

There is a second, independent reason to split. `do_json` is an opaque string (ADR 0001), so any
change to any field re-sends the entire declaration. With one declaration, adjusting a failover
address re-pushes the licence, the provisioning levels and every VLAN — a large blast radius for
a small change, against an appliance where re-pushing a licence is not free.

## Decision

**Each module instance renders two DO resources.**

1. `bigip_do.base` — `System`, `License`, `Provision`, `DNS`, `NTP`, `VLAN`, `SelfIp`, `Route`,
   `User`. Everything that describes the appliance in isolation.
2. `bigip_do.ha` — `DeviceTrust`, `DeviceGroup` (owner only, per ADR 0003), `ConfigSync`,
   failover and mirror addresses. Created only when `var.ha != null`, and depending on
   `bigip_do.base` so it can never precede it within an instance.
3. Cross-instance ordering is an explicit handshake, not `depends_on` between modules: the module
   publishes an output indicating base onboarding is complete, and accepts an input carrying the
   peer's. The landing zone wires one into the other in its own root, so the ordering is visible
   in one file.

The handshake is a value reference, which creates an ordinary OpenTofu edge. It is deliberately
not module-level `depends_on` — lz-paas ADR 0024 measured that expanding to the cross-product of
both modules' resources, taking a 23.7 s plan to never-completing at 13 links. At two instances
with few resources each the cost would be negligible, but the pattern is established as
value-reference and there is no reason to deviate.

## Consequences

- **Trust is asserted only after both appliances are onboarded**, which is the property the split
  exists for.
- **Blast radius is bounded.** An HA tweak re-sends the HA declaration alone; the licence and
  VLANs are untouched.
- **Two DO tasks per appliance**, so onboarding takes two polling cycles rather than one. For a
  once-per-appliance operation this is not a cost worth optimising.
- **One more output and one more input** on the module surface, existing solely to carry
  ordering. That is honest — the ordering is real and something has to express it — but it is
  surface that a standalone appliance never uses.
- **A standalone appliance has `count = 0` on `bigip_do.ha`**, so the HA path is genuinely absent
  rather than rendered empty. ADR 0007 asserts this in tests.
- **Partial failure is possible and visible.** If `base` succeeds and `ha` fails, the appliance is
  onboarded but unpaired — a legible state to retry from, which one combined declaration would
  have made ambiguous.

## Re-evaluation trigger

- The provider marks `bigip_do` as supporting incremental declarations, or DO gains per-class
  idempotency that makes re-sending the whole declaration free. The blast-radius half of the
  argument would go; the ordering half would remain.
- Device groups grow past two members (ADR 0003's trigger), which changes the handshake from one
  peer to several and may justify a third declaration or a different shape entirely.
- The landing zone adopts a readiness poller rather than relying on the two-phase apply, which
  would change where ordering is enforced but not that `ha` follows `base`.
