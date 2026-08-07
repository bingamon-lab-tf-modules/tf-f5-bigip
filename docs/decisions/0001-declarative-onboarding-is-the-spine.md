# 0001: Declarative Onboarding is the mechanism, rendered from typed Terraform variables

**Status:** accepted
**Date:** 2026-08-06

## Context

`terraform-provider-bigip` offers two ways to configure an appliance, and they do not overlap
cleanly.

**Imperative resources.** `bigip_net_vlan`, `bigip_net_selfip`, `bigip_net_route`,
`bigip_sys_provision`, `bigip_sys_dns`, `bigip_sys_ntp`, `bigip_sys_bigiplicense`,
`bigip_cm_device`, `bigip_cm_devicegroup`. Real Terraform resources with per-field drift
detection and a working `destroy`.

**`bigip_do`.** One F5 Declarative Onboarding declaration submitted as a JSON string, covering
`System`, `License`, `Provision`, `VLAN`, `SelfIp`, `Route`, `DNS`, `NTP`, `User`, `DeviceTrust`,
`DeviceGroup`, `ConfigSync` and about twenty more classes.

Two facts settled it.

**The provider has no user resource.** There is no `bigip_user`, `bigip_auth` or equivalent —
`bigip_partition` is the only match for user/role/auth/partition in the resource set. The CIS
service account the whole module exists to hand over cannot be created imperatively at all. Only
`bigip_do` (or `bigip_command`, which is an unmanaged shell escape) can create it.

**HA trust is materially harder imperatively.** `bigip_cm_device` + `bigip_cm_devicegroup` can
express a device group, but DO's `DeviceTrust`/`DeviceGroup`/`ConfigSync` classes are the path F5
documents and supports, and they converge idempotently rather than requiring the ordering to be
hand-built.

Against that, DO costs real Terraform affordances: `do_json` is an opaque string, so drift is
detected at whole-declaration granularity and never per field, and **DO has no delete** — the
provider documents that `terraform destroy` empties state without reverting the appliance.

For a Day-0 onboarding module (ADR 0002) those costs are tolerable. The declaration changes once
per appliance lifetime, and un-onboarding a BIG-IP is not a real operation: the recovery path is
to rebuild the VE from the OVA, which makes `destroy` semantics close to moot.

The alternative considered and rejected was rendering a _contract_ and having an `lz-cli` hook
execute it, as `tf-ntnx-nkp` does for `nkp create cluster` under lz-paas ADR 0018. That ADR's
reasons do not transfer: `nkp create cluster` is _"a 30-45 minute imperative command with no
values file, no idempotency and no state tracking"_. DO is declarative, idempotent, takes a
values file (the declaration _is_ one), finishes in minutes, and has a first-party Terraform
resource. The only shared property is secrets-in-state, addressed in ADR 0006 and lz-paas ADR 0032.

## Decision

**`bigip_do` is the module's spine, and consumers never see JSON.**

1. The module exposes ordinary typed HCL variables — `hostname`, `license`, `provisioning`,
   `dns`, `ntp`, `vlans`, `self_ips`, `routes`, `users`, `ha`.
2. `locals.tf` renders them into one DO declaration and `jsonencode`s it. All the JSON lives in
   one place, and it is generated, never hand-written by a caller.
3. `bigip_partition` is used imperatively for the CIS partition, because DO has **no Partition
   class** and CIS requires its partition to exist before it starts.
4. Rendering rules are fixed, because `do_json` is opaque and a perpetual diff is the obvious
   failure mode: the declaration is assembled in one well-ordered local, and nothing is
   interpolated from a source whose iteration order is not deterministic. `jsonencode` sorts
   object keys, and the provider's `StateFunc` normalises the JSON string, so the two together
   make this manageable — but it is a stated rule, not an accident.
5. `tenant_name` is not used. The provider marks it `Deprecated: "this attribute is no longer in
use"`.

## Consequences

- **The CIS service account is expressible.** This was the blocking constraint, and it is why the
  decision was not close.
- **`tofu destroy` does not un-configure an appliance.** State empties, the box keeps its
  configuration. Documented in `docs/spec.md` as expected behaviour, not a bug to fix.
- **Drift detection is coarse.** Any change to any field re-sends the whole declaration, and a
  change made on the appliance by hand is invisible until the next apply overwrites it. ADR 0004
  bounds the blast radius by splitting base from HA.
- **The module owns a rendering contract.** Its correctness _is_ the module — which is why ADR
  0007 makes the rendered declaration the primary test subject.
- **Adding a DO class is additive.** New classes are new typed variables plus a branch in the
  same renderer, not a redesign. ADR 0005's escape hatch covers the gap in the meantime.
- **DO schema errors surface only against a live appliance.** Nothing in a plan proves DO will
  accept what was rendered. Named as a known gap in ADR 0007.

## Re-evaluation trigger

- The provider gains a `bigip_user` resource, removing the constraint that decided this. The
  imperative path would then be viable and worth re-costing against DO's coarse drift detection.
- `do_json` gains structured typing, or the provider adopts the plugin framework with a typed
  declaration attribute — either would remove the opaque-string cost.
- F5 deprecates Declarative Onboarding in favour of a successor (as AS3 supersedes iApps for
  application delivery). Re-evaluate before the next major TMOS jump.
