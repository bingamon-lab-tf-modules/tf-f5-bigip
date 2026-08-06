# 0003: One appliance per module instance; HA is an explicit input with an explicit role

**Status:** accepted
**Date:** 2026-08-06

## Context

With the provider passed in rather than configured inside the module (the house pattern — no
`tf-ntnx-*` module declares a `provider` block), one configured provider addresses one appliance.
So the module's cardinality has to be decided before its variables are shaped: a single device
means `variable "hostname"`, `variable "vlans"`; N devices means
`variable "devices" = map(object({...}))` with `for_each` providers.

OpenTofu 1.9+ supports `for_each` on providers, and this estate has it available — `AGENTS.md`
notes it explicitly. But lz-paas has deliberately not adopted it: `module/providers.tf` states
_"No for_each, no aliases - just one provider instance"_.

The deciding argument is that **an HA pair is not two independent devices**. DO's `DeviceTrust`
requires each peer to know the other's management address and credentials, and trust is
established from one side. A map of two devices does not describe that relationship — it
describes two unrelated appliances that happen to be configured together, and would silently
produce two standalone boxes rather than a pair.

Modelling HA as an emergent property of map membership would mean inferring the relationship from
the collection, hiding the asymmetry that actually matters inside the module.

## Decision

**One appliance per module instance. HA is an explicit optional input.**

1. Variables are flat and singular — `hostname`, `license`, `vlans`, `self_ips`, `routes`,
   `users`. The maps inside are keyed collections _within_ one device (ADR 0005), not collections
   of devices.
2. `var.ha` defaults to `null`. When set, it carries the peer address, peer credentials, device
   group name and type, the config-sync address and an optional failover unicast address — the
   relationship, named.
3. `var.ha.role` is `"owner"` or `"member"`, and it is required when `ha` is set. Only the owner
   emits the `DeviceGroup` class.
4. The landing zone instantiates the module once per appliance, with an aliased provider each.

### Why the role is explicit

DO will reconcile a device group asserted from both sides. Relying on that would work, and would
put the asymmetry inside DO's reconciliation behaviour where no reviewer can see it. An explicit
`role` puts it in the YAML, where a reviewer reading two config files can see which appliance
owns the group — and where a config declaring two owners, or none, is a check the landing zone
can fail on.

## Consequences

- **A second appliance is a second module block plus a second aliased provider**, not one more
  YAML key. That is the cost, and it is paid in the landing zone, once per appliance.
- **`for_each` providers stay unadopted.** They remain available at the _landing zone_ level
  later without touching this module — the module's interface does not bet on them either way.
- **Two config files must agree.** Each peer names the other; a mismatch is a real hazard. The
  landing zone's `checks.tf` asserts that exactly one `owner` exists and that the peer addresses
  are reciprocal.
- **HA credentials cross the boundary.** The owner's declaration contains the member's password
  in order to establish trust. That widens what the declaration holds and is part of why ADR 0006
  and lz-paas ADR 0032 exist.
- **A standalone appliance is the `ha = null` path**, which is genuinely simpler rather than a
  degenerate case of a pair — no `DeviceTrust`, no second declaration (ADR 0004).

## Re-evaluation trigger

- A third appliance joins, making a device group of more than two. `role` as a binary stops
  being sufficient; DO's device group model supports more members, and the input would need to
  become a list with one owner.
- lz-paas adopts `for_each` providers generally, at which point the landing zone could iterate
  devices even while this module stays singular — worth revisiting the ergonomics then, not the
  cardinality.
- DO changes how device trust is established, e.g. to a symmetric assertion where ownership is
  no longer meaningful.
