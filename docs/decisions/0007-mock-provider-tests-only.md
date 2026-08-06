# 0007: Mock-provider unit tests only; integration deferred and named as a gap

**Status:** accepted
**Date:** 2026-08-06

## Context

This module is unusual among its siblings. `tf-ntnx-net` and `tf-ntnx-vm` create resource graphs
worth testing for shape and wiring; this module creates one or two resources whose entire value
is a correctly-rendered JSON document (ADR 0001). The rendering _is_ the module.

That makes the risk profile lopsided. A wrong `SelfIp.allowService`, a missing `DeviceTrust`
field or an unresolved `vlan_key` fails slowly and opaquely — minutes into an apply, reported by
the appliance, in a message that frequently does not name the offending field. All of it is
trivially detectable at plan time.

The estate's convention is `module/tests/*.tftest.hcl` with `mock_provider` and a dummy provider
block, offline throughout. `tf-ntnx-nkp/module/tests/validation.tftest.hcl` is the closest
precedent and states the split directly: _"Cross-variable rules land in local.validation_errors
and are asserted through the output; single-variable rules raise from their validation {} block
and are asserted with expect_failures."_

Integration testing would need a licensed BIG-IP, credentials in CI and roughly fifteen minutes
per run. It is not a realistic CI gate for a lab estate.

## Decision

**MVP ships mock-provider unit tests at `module/tests/`, and no integration test.**

1. **Golden-declaration test.** A full fixture — both HA roles, three VLANs, self-IPs, routes,
   users — asserting the decoded declaration matches expected structure. Because `do_json` is
   `sensitive()` (ADR 0006), assertions use `nonsensitive(jsondecode(...))` against **dummy**
   secrets, so nothing real is exposed by the unwrap.
2. **The summary is asserted in the same test**, so `declaration_summary` cannot drift from the
   declaration it describes (ADR 0006's stated risk).
3. **Negative tests per validation rule**, using `var.enforce_validation = false` and asserting
   `output.validation_errors` (ADR 0005): a `self_ip` referencing a missing `vlan_key`, an
   `ha.role` outside `owner|member`, `ha` set without a role, an unknown module name in
   `provisioning`, a malformed address, and an override touching a deny-listed class.
4. **One test proves the gate itself works** — `enforce_validation` left `true` with a bad input,
   asserting the precondition fires. Without it, every other negative test could pass against a
   permanently disabled hard stop.
5. **HA-absent test.** `ha = null` asserts `bigip_do.ha` has `count = 0` and that the base
   declaration contains no `DeviceGroup` or `DeviceTrust`.
6. Repository layout follows the siblings: tests live at `module/tests/`, not the template's
   top-level `tests/`.

## Consequences

- **Nothing in this suite proves DO will accept the declaration.** DO validates its schema
  server-side; a structurally plausible declaration that DO rejects passes every test here. This
  is the central gap and it is not mitigated by more unit tests.
- **The mitigation is procedural.** The two-phase apply (lz-paas ADR 0030) puts a human in front
  of the first onboarding run of any appliance, which is where a rejected declaration surfaces.
  That is weaker than a test and it is what the MVP has.
- **A validation rule without a negative test is assumed working.** Every rule that can stop a
  plan gets a failing case, following `tf-ntnx-nkp`'s convention — otherwise a rule that never
  fires is indistinguishable from one that always passes.
- **Tests run offline and fast**, so they are a usable inner loop and a real CI gate.
- **The golden fixture is a maintenance cost.** Every new class changes it, which is the point —
  the diff shows what the rendering change actually did to the output.

The assumption flagged here has since been **verified**: the provider does ship the DO JSON
schema at `schemas/doschema.json`. It was used during implementation as the authority for every
class and property name the renderer emits, which removes a whole category of error these tests
would otherwise have to guess at.

Automated validation against it remains unimplemented. OpenTofu has no JSON-schema primitive, so
it needs an external data source or a build step, and the schema is not vendored here. Worth
doing if a declaration is ever rejected in the field; not worth doing pre-emptively.

## Re-evaluation trigger

- A DO declaration is rejected by an appliance despite passing every test. That is the signal to
  invest in schema validation or a real integration test, and the rejected declaration becomes
  the first fixture.
- A permanent lab BIG-IP becomes available for CI, making integration testing cheap enough to
  add — at which point it supplements these tests rather than replacing them.
- A build step or external data source makes JSON-schema validation cheap, at which point
  `schemas/doschema.json` can gate the render at plan time rather than only informing it.
