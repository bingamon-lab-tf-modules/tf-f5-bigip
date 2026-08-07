# 0005: Typed keyed maps in, one escape hatch, module-owned keys refused

**Status:** accepted
**Date:** 2026-08-06

## Context

The module takes typed variables and renders a DO declaration (ADR 0001). Two shape questions
follow.

**How collections reference each other.** DO's `SelfIp` names its VLAN by name. Expressed as a
free string, a typo is discovered by the appliance minutes into an apply. `tf-ntnx-net` solved
the identical problem with keyed maps and `*_key` cross-references — `subnet_key`, `vpc_key` —
precisely because _"subnet ext_ids are per-Prism Central UUIDs, so a literal is neither portable
nor knowable before the first apply"_. The portability argument does not transfer, but the
checkability one does, and more strongly: a `vlan_key` that does not exist in `var.vlans` is a
plan-time error, and keyed maps give stable `for_each` addresses.

**What happens when a caller needs a class the module does not render.** DO has around thirty
classes; the MVP renders eleven (ADR 0002). Without an escape hatch, every deferred class blocks
on a module release, and the pressure is to fork.

`tf-ntnx-nkp` has already solved that, and also demonstrated the hazard. It accepts
`var.extra_args`, and its `argv_create_base` marks certain flags _"Module-owned. Not settable by
the caller, refused in extra_args."_ An unguarded hatch lets a caller silently contradict a typed
input, and the contradiction wins or loses depending on merge order — a class of bug that is
invisible in review because both halves look correct in isolation.

## Decision

**Keyed maps with `*_key` cross-references, and one merged escape hatch with a deny-list.**

1. Collections are `map(object({...}))` keyed by a caller-chosen name: `vlans`, `self_ips`,
   `routes`, `users`, `partitions`.
2. Cross-references use keys, not names — `self_ips[*].vlan_key` refers into `var.vlans`. A key
   that does not resolve is a validation error naming both the self-IP and the missing VLAN.
3. `var.do_declaration_overrides` (default `{}`) is merged over the rendered declaration before
   `jsonencode`. Merging is **two-level** — at the declaration root and at the `Common` tenant
   level — which is enough to add or wholly replace a class, and deliberately does not reach
   inside one. A recursive deep merge (lz-paas ADR 0011) would need a submodule for a capability
   the hatch does not need: its purpose is whole classes the module does not yet render.
4. **Module-owned classes are refused in the hatch**: `License`, `User`, `DeviceTrust`,
   `DeviceGroup`, `ConfigSync`. An override touching any of them fails validation with a message
   naming the class and the typed variable that owns it. These are the classes where a silent
   contradiction is most damaging — credentials, licensing, and the HA relationship.
5. Validation follows the `tf-ntnx-nkp` shape: each category computes a `*_errors` list in
   `locals.tf`, they aggregate into `local.validation_errors`, and **one** precondition on a
   `terraform_data` anchor reports them together — _"instead of making the operator re-plan per
   typo"_.
6. `var.enforce_validation` (default `true`) is a declared test seam, copied from
   `tf-ntnx-nkp/module/variables.tf`, so tests can assert _which_ error fired rather than dying
   on the precondition. `output "validation_errors"` exposes the list for the same reason.

## Consequences

- **Reference typos are caught at plan time**, in the module, with a message naming both ends —
  rather than by the appliance, mid-apply.
- **The hatch keeps callers off forks**, at the cost of a path that variable validation cannot
  see. Anything set through it is unvalidated by construction; the deny-list bounds the damage to
  classes where being wrong is recoverable.
- **The deny-list is a maintenance obligation.** Every class promoted from the hatch to a typed
  variable must be added to it in the same change, or the hatch silently keeps winning.
- **One precondition means one failure message** listing every problem, which is the behaviour
  worth having and also means a single unrelated error blocks the whole plan.
- **`enforce_validation` is a footgun if misused.** It is documented as _test seam only_, exactly
  as `tf-ntnx-nkp` documents it; set false in a real configuration, it disables every hard stop.
- **The interface matches its siblings.** A reader who knows `tf-ntnx-net`'s `subnet_key` and
  `tf-ntnx-nkp`'s validation anchor already knows this module's conventions.

## Re-evaluation trigger

- The hatch is being used for the same class repeatedly across environments. That is the signal
  to promote it to a typed variable and add it to the deny-list.
- The hatch is used to contradict a typed input despite the deny-list — meaning the list is
  incomplete, and the question becomes whether an allow-list is the safer default.
- OpenTofu gains cross-variable validation strong enough to express the key references
  declaratively, retiring the hand-rolled `*_errors` aggregation.
