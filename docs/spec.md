# tf-f5-bigip — specification

Terraform/OpenTofu module that carries an F5 BIG-IP Virtual Edition from a booted OVA to the
point where F5 Container Ingress Services can take over.

Decisions behind this spec are recorded in [`docs/decisions/`](decisions/README.md). Estate-level
decisions — which landing zone consumes this, which lz-cli mode it runs in, where its config
lives — are in `lz-paas/docs/decisions/` (ADRs 0030–0033).

---

## 1. Scope

**In.** Day-0 onboarding of one BIG-IP appliance: identity, licensing, module provisioning, DNS
and NTP, VLANs, self-IPs, routes, local users, high-availability pairing, and the LTM partition
that CIS is pointed at.

**Out, permanently.** Every `ltm_*` and `gtm_*` resource, `bigip_as3`, `bigip_fast_*`,
`bigip_waf_policy`, `bigip_vcmp_guest`. CIS owns application delivery; two controllers writing the
same LTM objects would revert each other continuously (ADR 0002).

**Out, deferred to v0.2+.** `ManagementRoute`, `RouteDomain`, `Trunk`, SNMP, remote syslog,
`HTTPD`/`SSHD` hardening, LDAP/AD authentication, `TrafficControl`, `DagGlobals`,
`FirewallPolicy`. Each is additive to the same renderer.

**Not this module's job.** Deploying the VE. That is `tf-ntnx-vm` via the `compute_databases`
landing zone, which already carries `ovas`, `ova_downloads`, `ova_deployments` and cloud-init
`user_data`. This module never touches the `nutanix` provider.

### Acceptance condition

"Ready for NKP" means: appliance licensed; LTM provisioned; VLANs and self-IPs up; default route
present; time synchronised; the CIS partition exists; and the CIS service account can
authenticate into that partition.

---

## 2. Mechanism

F5 Declarative Onboarding, via `bigip_do`, rendered from typed HCL variables (ADR 0001). Callers
never write JSON.

Two facts forced it. The provider has **no user resource** — `bigip_partition` is the only
partition/user/role/auth resource in the set — so the CIS service account cannot be created
imperatively at all. And DO's `DeviceTrust`/`DeviceGroup`/`ConfigSync` are the supported path for
HA, converging idempotently rather than requiring hand-built ordering.

Accepted costs:

- **`do_json` is an opaque string.** Drift is whole-declaration, never per field. A change made
  on the appliance by hand is invisible until an apply overwrites it.
- **DO has no delete.** `tofu destroy` empties state and leaves the appliance configured. This is
  expected behaviour, not a defect — the recovery path for a BIG-IP is rebuilding the VE from the
  OVA.

`bigip_partition` is used imperatively, because DO has no Partition class and CIS requires its
partition to pre-exist.

### Rendering rules

The declaration is assembled in one well-ordered local and `jsonencode`d once. Nothing is
interpolated from a source whose iteration order is not deterministic. `jsonencode` sorts object
keys and the provider's `StateFunc` normalises the JSON string; together these prevent perpetual
diffs, but the rule is stated rather than assumed. `tenant_name` is not used — the provider marks
it `Deprecated`.

**Every class in a DO tenant shares one key namespace.** VLAN and user keys render bare, because
they are the object's name on the appliance and `self_ips[*].vlan_key` resolves against the VLAN
key. Self IPs and routes are referenced by nothing, so they render prefixed (`selfip_<key>`,
`route_<key>`) and cannot collide. A VLAN and a user sharing a key — or either colliding with a
tenant property or a class this module renders — is a validation error, because `merge()` would
otherwise resolve it silently.

---

## 3. Cardinality and HA

One appliance per module instance (ADR 0003). The landing zone instantiates the module once per
appliance with an aliased provider.

An HA pair is a _relationship_, not two independent devices: DO's `DeviceTrust` requires each peer
to know the other's address and credentials, and trust is established from one side. So HA is an
explicit optional `var.ha` block carrying peer address, peer credentials, device group name and
type, config-sync address and an optional failover unicast address — plus `ha.role`, `"owner"` or
`"member"`. Only the owner emits `DeviceGroup`.

The role is explicit so the asymmetry is visible in YAML and reviewable, rather than hidden in
DO's reconciliation behaviour.

---

## 4. Resources

| Resource                    | Condition            | Contents                                                                                   |
| --------------------------- | -------------------- | ------------------------------------------------------------------------------------------ |
| `terraform_data.validation` | always               | the single aggregate precondition                                                          |
| `bigip_do.base`             | always               | tenant `hostname`, `License`, `Provision`, `DNS`, `NTP`, `VLAN`, `SelfIp`, `Route`, `User` |
| `terraform_data.peer_gate`  | `var.ha != null`     | carries `peer_base_complete` so trust waits on the peer                                    |
| `bigip_do.ha`               | `var.ha != null`     | `DeviceTrust`, `ConfigSync`, `FailoverUnicast`, `DeviceGroup` (owner only)                 |
| `bigip_partition`           | per `var.partitions` | the CIS handover seam                                                                      |

`bigip_do.ha` depends on `bigip_do.base` within an instance. Across the pair, ordering is an
explicit output→input handshake wired in the landing zone's root — a value reference, never
module-level `depends_on` (lz-paas ADR 0024 measured that as unusable). Splitting base from HA
also bounds blast radius: adjusting a failover address does not re-push the licence and VLANs
(ADR 0004).

---

## 5. Interface

```hcl
hostname          string                   # required
license           object({ reg_key, add_on_keys, overwrite })   # sensitive
provisioning      map(string) = { ltm = "nominal" }
dns               object({ name_servers, search })
ntp               object({ servers, timezone })   # timezone lives here, per the DO schema
vlans             map(object({ tag, mtu, cmp_hash, interfaces }))
self_ips          map(object({ address, vlan_key, allow_service, traffic_group }))
routes            map(object({ network, gw, mtu }))
users             map(object({ password, shell, partition_access }))
ha                object({ role, local_username, local_password,
                           peer_address, peer_username, peer_password,
                           config_sync_ip, device_group_name, device_group_type,
                           device_group_owner, members, auto_sync,
                           save_on_auto_sync, network_failover,
                           full_load_on_sync,
                           failover_address, failover_port })      = null
peer_base_complete        string = null    # HA ordering handshake
partitions        map(object({ description, route_domain_id }))
do_declaration_overrides  any  = {}
enforce_validation        bool = true      # test seam only
```

Collections are keyed maps and cross-reference by key — `self_ips[*].vlan_key` refers into
`var.vlans` — following `tf-ntnx-net`'s `subnet_key`/`vpc_key` convention. An unresolved key is a
plan-time error naming both ends (ADR 0005).

`NTP` is not optional padding: device trust fails on clock skew, with an error that does not
mention time.

**Only `license` is marked `sensitive`.** `users` and `ha` are not, deliberately: a sensitive
variable taints everything derived from it, including the `declaration_summary` output that ADR
0006 requires. Their secrets are still covered — values arrive already marked from the caller's
SOPS data, and `do_json` is wrapped in `sensitive()` regardless. Variable values are not written
to state, so what this trades away is plan-output exposure, which the wrapper closes.

### Escape hatch

`do_declaration_overrides` is merged over the rendered declaration before `jsonencode`, so a
deferred DO class does not block on a module release. Merging is **two-level** — at the
declaration root and at the `Common` tenant level — which is enough to add or wholly replace a
class, and deliberately does not reach inside one. **Module-owned classes are refused**:
`License`, `User`, `DeviceTrust`, `DeviceGroup`, `ConfigSync`. An override touching one fails
validation naming the class and the typed variable that owns it — following `tf-ntnx-nkp`'s
_"Module-owned. Not settable by the caller, refused in extra_args"_ precedent.

Anything set through the hatch is unvalidated by construction. Promoting a class to a typed
variable means adding it to the deny-list in the same change.

---

## 6. Validation

Each category computes a `*_errors` list in `locals.tf`; they aggregate into
`local.validation_errors`; one precondition on `terraform_data.validation` reports them together,
so a plan surfaces every problem at once instead of one per re-plan.

`var.enforce_validation` (default `true`) is a declared **test seam only** — set false in a real
configuration and every hard stop is disabled. `output "validation_errors"` exposes the list so
tests can assert precisely which rule fired.

Both conventions are lifted from `tf-ntnx-nkp`.

---

## 7. Outputs

| Output                | Sensitive | Purpose                                                                                                          |
| --------------------- | --------- | ---------------------------------------------------------------------------------------------------------------- |
| `declaration_summary` | no        | class names, VLAN names/tags, self-IP addresses, routes, provisioning levels, usernames, device group name, role |
| `summary`             | no        | compact description of the appliance                                                                             |
| `validation_errors`   | no        | every error found; empty on a valid config                                                                       |
| `base_complete`       | no        | ordering handshake for the HA peer                                                                               |

**Nothing secret may enter an output, ever** — outputs land in state and in `tofu output`. They
carry the _names_ of credentials, never values, following `tf-ntnx-nkp/module/outputs.tf`.

`declaration_summary` exists because the declaration is redacted (§8): it is the only review
surface for what an apply will change. A class present in the declaration but missing from the
summary changes unreviewed, so the two are asserted together in tests.

---

## 8. Secrets

The declaration necessarily contains the licence registration key, the admin and CIS passwords,
and — on an HA owner — the peer's password. DO's `License` and `User` classes take literals with
no indirection.

`do_json` is **not** marked `Sensitive` in the provider schema (verified in
`resource_bigip_do.go`; only `bigip_password` and `bigip_token_auth` are). Untreated, the
declaration is printed in full in plan and apply output and written to state in cleartext.

Two independent mitigations, neither substituting for the other (ADR 0006):

1. **`do_json = sensitive(jsonencode(...))`** — redacts plan and apply console output, closing
   the CI-log exposure. Does nothing for state.
2. **State encryption** — lz-paas ADR 0032, estate-wide, `pbkdf2` via `TF_ENCRYPTION`. Protects
   state at rest. Does nothing for console output.

Secret _values_ reach the module as variables from SOPS material in
`config/<env>/f5/<device>.sops.json` (lz-paas ADR 0031).

---

## 9. Testing

Mock-provider unit tests at `module/tests/`, offline, no live appliance (ADR 0007):

- **golden-declaration test** — full fixture, both HA roles, asserting the decoded declaration
  and `declaration_summary` together, via `nonsensitive(jsondecode(...))` against dummy secrets;
- **negative test per validation rule**, with `enforce_validation = false`, asserting
  `output.validation_errors`;
- **one test with `enforce_validation = true`** proving the gate itself fires;
- **HA-absent test** — `bigip_do.ha` has `count = 0`, no `DeviceGroup`/`DeviceTrust` in base.

### Known gap

Nothing here proves DO will **accept** the declaration. DO validates its schema server-side; a
structurally plausible declaration that DO rejects passes every test. The MVP mitigation is
procedural — the two-phase apply puts a human in front of the first onboarding run.

**Verified during implementation:** the provider does ship the DO JSON schema, at
`schemas/doschema.json` (~205 KB, _"F5 Declarative Onboarding base declaration"_). It was used as
the authority for every class and property name the renderer emits, rather than memory — which is
why `timezone` sits on `NTP` and not on a `System` class.

Automated plan-time validation against it is still **not** implemented: OpenTofu has no
JSON-schema primitive, so it would need an external data source or a build step, and the schema
is not vendored into this repo. The gap is narrower than it was — the shapes are right by
construction — but DO acceptance remains unproven until a live apply.

---

## 10. Consumed by

`lz-paas`, landing zone `load_balancer`:

- **Landing zone** — `module/landing_zones/load_balancer/`, gated by `lz_enable_load_balancer`,
  pinned by tag (`?ref=v0.1.0`). Takes `providers = { bigip = bigip }` and no `nutanix` provider.
- **Mode** — its own lz-cli mode, state `lz-paas/<env>/load-balancer.tfstate` (lz-paas ADR 0030).
- **Config plane** — `module/config/<env>/f5/<device>.yaml` + `.sops.json` (lz-paas ADR 0031).
- **Management address** — declared statically in that YAML, applied to the VE by cloud-init at
  OVA deploy, and read directly by `provider "bigip"`. Not discovered, because a provider
  configuration cannot take a plan-time-unknown value (lz-paas ADR 0033).

Deployment is two-phase by construction: `compute_databases` deploys the VE in the main mode,
then `--load-balancer` onboards it. A VE takes minutes from power-on to a responsive REST
endpoint, and the mode split is the readiness gate for the MVP. A fixed `tf-sleep` is explicitly
rejected — a constant is a false claim about a variable duration.

---

## 11. Known limitations

- `tofu destroy` does not un-configure an appliance (§2).
- Drift is detected at whole-declaration granularity, never per field (§2).
- A plan shows `(sensitive value)` for the declaration; `declaration_summary` is the review
  surface (§7).
- Secrets are in state; protection depends on the consuming repo's encryption (§8).
- No integration test — DO acceptance is unproven until a live apply (§9).
- The declared management address and reality can diverge; a `check` in the landing zone detects
  it, but only once the address is reachable (lz-paas ADR 0033).
