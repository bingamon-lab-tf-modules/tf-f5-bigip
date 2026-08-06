# 0006: The declaration is `sensitive()`; a redacted summary carries reviewability

**Status:** accepted
**Date:** 2026-08-06
**Relates to:** [lz-paas ADR 0032](https://github.com/bingamon-lab/lz-paas/blob/trunk/docs/decisions/0032-state-encryption-for-all-modes.md)
(state at rest — the other half of this problem)

## Context

The DO declaration necessarily contains secrets. `License` takes a registration key as a literal;
`User` takes passwords as literals; and on the owner of an HA pair, `DeviceTrust` carries the
peer's password too (ADR 0003). DO offers no indirection to an external secret store.

The provider makes that worse than it needs to be. In `resource_bigip_do.go`, `do_json` is
declared `Required` with a `StateFunc` that normalises the JSON — and **no `Sensitive: true`**.
Only `bigip_password` and `bigip_token_auth` carry that flag. So by default the declaration is:

- written to state in cleartext, and
- **printed in full in `tofu plan` and `tofu apply` output**.

The second is the sharper exposure. State sits behind backend credentials; CI logs are
comparatively easy to over-share, and a GitHub Actions plan would carry a licence key and two
passwords in plain view.

Marking a value `sensitive()` in Terraform redacts it from plan and apply output even when the
target attribute is not itself declared sensitive. That closes the console leak for one line. It
does **not** encrypt state — that is a backend-level concern, decided estate-wide in lz-paas ADR 0032.

The cost of redaction is that a sensitive value shows as `(sensitive value)` with no diff at all.
A reviewer loses every signal about what an apply is about to change on the appliance — which,
for a module whose entire output is one document, means losing all review signal.

## Decision

**Render through `sensitive()`, and publish a non-secret summary alongside it.**

1. `do_json = sensitive(jsonencode(local.base_declaration))` on `bigip_do.base`, and the same
   over `local.ha_declaration` on `bigip_do.ha`.
2. `output "declaration_summary"` — **not** sensitive — carrying the shape of the declaration and
   none of its contents: the class names present, VLAN names and tags, self-IP addresses and
   their VLAN keys, route destinations, provisioning levels, usernames, the device group name and
   this device's role.
3. Nothing secret may enter that output, ever. It carries the _names_ of credentials, never
   values — the same rule `tf-ntnx-nkp/module/outputs.tf` states for its contract: _"NOTHING HERE
   MAY BE SECRET. Outputs land in OpenTofu state and in `tofu output`"_.
4. `output "summary"` follows the shape `tf-ntnx-nkp` established, so a reader moving between the
   two modules finds the same affordance.

Encryption and redaction are both required and neither substitutes for the other: encryption
protects state at rest and does nothing for console output; `sensitive()` protects console output
and does nothing for state.

## Consequences

- **A licence key and two passwords no longer appear in CI logs.**
- **The declaration diff is invisible in a plan.** `declaration_summary` is the only review
  surface for what an apply will do. If it omits a field, that field changes unreviewed — which
  makes the summary's coverage a real correctness concern, not cosmetic.
- **The summary is a second thing to keep in step with the renderer.** A new class added to the
  declaration and not to the summary is silently unreviewable. ADR 0007's golden-declaration test
  asserts both, so they drift together or not at all.
- **Secrets are still in state**, unencrypted at the OpenTofu layer until lz-paas ADR 0032's
  migration lands. New states are encrypted at birth, so `load-balancer.tfstate` is never written
  in the clear — but that is the consuming repo's guarantee, not this module's.
- **`sensitive()` propagates.** Any output derived from the declaration inherits the mark, so the
  summary is built from `local` inputs rather than by decomposing the rendered JSON. Using
  `nonsensitive()` to unwrap it would defeat the decision.

## Re-evaluation trigger

- The provider marks `do_json` as `Sensitive`. The explicit wrapper becomes redundant, though
  harmless — and the plan-diff loss would then be unavoidable rather than chosen.
- DO gains indirection to an external secret store, letting the declaration carry references
  instead of literals. That would remove the problem at its root and is the outcome worth
  watching for.
- OpenTofu gains structured redaction — diffing a sensitive value while masking only the secret
  leaves — which would restore plan reviewability and retire `declaration_summary`.
