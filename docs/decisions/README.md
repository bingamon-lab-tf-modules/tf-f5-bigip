# Architecture Decision Records

This directory is this module's **decision log**: one file per decision, recording the context,
the choice, its consequences, and the event that would reopen it — so a future contributor reads
_why_ before re-litigating.

Decisions here are **module-internal**. Anything about where this module sits in the estate —
which landing zone consumes it, which lz-cli mode it runs in, which config plane holds its
inputs — lives in the consuming repo's log instead:

- [lz-paas ADR 0030](https://github.com/bingamon-lab/lz-paas/blob/trunk/docs/decisions/0030-load-balancer-is-its-own-mode.md) — the `load_balancer` landing zone, mode and state
- [lz-paas ADR 0031](https://github.com/bingamon-lab/lz-paas/blob/trunk/docs/decisions/0031-f5-config-plane.md) — the `f5` config plane
- [lz-paas ADR 0032](https://github.com/bingamon-lab/lz-paas/blob/trunk/docs/decisions/0032-state-encryption-for-all-modes.md) — state encryption
- [lz-paas ADR 0033](https://github.com/bingamon-lab/lz-paas/blob/trunk/docs/decisions/0033-bigip-management-address-is-static-config.md) — the management address

## Format

Lightweight [MADR](https://adr.github.io/madr/)-style, matching lz-paas: filenames are
`NNNN-<kebab-slug>.md` (zero-padded, monotonic, never renumbered), and every ADR carries
**Status**, **Date**, **Context**, **Decision**, **Consequences** and **Re-evaluation trigger**.

Reversing a decision means a new ADR with `Status: accepted`; the old one becomes
`Status: superseded-by-NNNN`.

## Index

- [0001](0001-declarative-onboarding-is-the-spine.md) — Declarative Onboarding is the mechanism, rendered from typed variables (accepted)
- [0002](0002-day-0-scope-cis-owns-day-2.md) — Scope stops at CIS-ready; all `ltm_*`/`gtm_*` belong to CIS (accepted)
- [0003](0003-one-device-per-instance-explicit-ha.md) — One appliance per module instance; HA is an explicit input with an explicit role (accepted)
- [0004](0004-two-declarations-base-then-ha.md) — Two DO resources: `base`, then `ha` gated behind it (accepted)
- [0005](0005-typed-keyed-maps-with-guarded-escape-hatch.md) — Typed keyed maps in, one escape hatch, module-owned keys refused (accepted)
- [0006](0006-declaration-is-sensitive-summary-is-not.md) — `do_json` is `sensitive()`; a redacted summary carries reviewability (accepted)
- [0007](0007-mock-provider-tests-only.md) — Mock-provider unit tests only; integration deferred and named as a gap (accepted)
