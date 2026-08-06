# tf-f5-bigip

## Table of Contents

## Overview

A description of the module goes here.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_bigip"></a> [bigip](#requirement\_bigip) | >= 1.28.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_bigip"></a> [bigip](#provider\_bigip) | 1.28.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [bigip_do.base](https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/do) | resource |
| [bigip_do.ha](https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/do) | resource |
| [bigip_partition.this](https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/partition) | resource |
| [terraform_data.peer_gate](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dns"></a> [dns](#input\_dns) | DNS resolver configuration. Null omits the DNS class. | <pre>object({<br/>    name_servers = optional(list(string), [])<br/>    search       = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_do_declaration_overrides"></a> [do\_declaration\_overrides](#input\_do\_declaration\_overrides) | Last-resort overrides merged over the rendered base declaration, for DO classes this module<br/>does not yet render as typed variables.<br/><br/>Merging is TWO-LEVEL: keys are merged at the declaration root, and at the `Common` tenant<br/>level. It is sufficient to add or wholly replace a class; it does NOT merge within a class.<br/><br/>Module-owned classes are refused: License, User, DeviceTrust, DeviceGroup, ConfigSync.<br/>Anything set here is invisible to variable validation, by construction. | `any` | `{}` | no |
| <a name="input_enforce_validation"></a> [enforce\_validation](#input\_enforce\_validation) | Fail the plan when validation errors exist. Test seam only — leave true in every real configuration. | `bool` | `true` | no |
| <a name="input_ha"></a> [ha](#input\_ha) | High-availability pairing. Null produces a standalone appliance and no second declaration. See ADR 0003 for why the owner/member asymmetry is explicit rather than inferred. | <pre>object({<br/>    role           = optional(string)<br/>    local_username = optional(string, "admin")<br/>    local_password = string<br/>    peer_address   = string<br/>    peer_username  = optional(string, "admin")<br/>    peer_password  = string<br/><br/>    config_sync_ip = string<br/><br/>    device_group_name  = optional(string, "failover-group")<br/>    device_group_type  = optional(string, "sync-failover")<br/>    device_group_owner = optional(string)<br/>    members            = optional(list(string), [])<br/>    auto_sync          = optional(bool, true)<br/>    save_on_auto_sync  = optional(bool, false)<br/>    network_failover   = optional(bool, true)<br/>    full_load_on_sync  = optional(bool, false)<br/><br/>    failover_address = optional(string)<br/>    failover_port    = optional(number, 1026)<br/>  })</pre> | `null` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | Fully-qualified hostname for the appliance. Becomes the DO tenant hostname and, on an HA owner, the default device group owner. | `string` | n/a | yes |
| <a name="input_license"></a> [license](#input\_license) | BYOL registration key. Null leaves licensing alone, for an appliance licensed outside Terraform. Only the `regKey` licence type is supported; BIG-IQ licence pools are out of MVP scope. | <pre>object({<br/>    reg_key     = string<br/>    add_on_keys = optional(list(string), [])<br/>    overwrite   = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_ntp"></a> [ntp](#input\_ntp) | NTP servers and the appliance timezone. Null omits the NTP class. | <pre>object({<br/>    servers  = optional(list(string), [])<br/>    timezone = optional(string, "UTC")<br/>  })</pre> | `null` | no |
| <a name="input_partitions"></a> [partitions](#input\_partitions) | LTM partitions, keyed by partition name. This is the CIS handover seam: DO has no Partition class, and CIS requires its partition to exist before it starts (ADR 0001). | <pre>map(object({<br/>    description     = optional(string)<br/>    route_domain_id = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_peer_base_complete"></a> [peer\_base\_complete](#input\_peer\_base\_complete) | Ordering handshake (ADR 0004). The landing zone wires the peer module's `base_complete` output into this input, so device trust is only asserted after both appliances have finished base onboarding. Ignored when var.ha is null. | `string` | `null` | no |
| <a name="input_provisioning"></a> [provisioning](#input\_provisioning) | BIG-IP modules to provision, keyed by module name, valued by provisioning level. CIS requires `ltm` at `nominal` or better. | `map(string)` | <pre>{<br/>  "ltm": "nominal"<br/>}</pre> | no |
| <a name="input_routes"></a> [routes](#input\_routes) | Static routes, keyed by name. `network` defaults to 'default', which is DO's spelling of the default route. | <pre>map(object({<br/>    gw      = string<br/>    network = optional(string, "default")<br/>    mtu     = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_self_ips"></a> [self\_ips](#input\_self\_ips) | Self IPs, keyed by name. `address` carries a prefix length (e.g. '10.10.10.5/24'); `vlan_key` refers to a key of var.vlans. | <pre>map(object({<br/>    address       = string<br/>    vlan_key      = string<br/>    allow_service = optional(list(string), ["default"])<br/>    traffic_group = optional(string, "traffic-group-local-only")<br/>  }))</pre> | `{}` | no |
| <a name="input_users"></a> [users](#input\_users) | Local users, keyed by username. `partition_access` maps a partition name to a role; the CIS service account normally needs admin on the partition it manages. | <pre>map(object({<br/>    password         = string<br/>    shell            = optional(string, "tmsh")<br/>    partition_access = optional(map(string), { "all-partitions" = "admin" })<br/>  }))</pre> | `{}` | no |
| <a name="input_vlans"></a> [vlans](#input\_vlans) | VLANs to create, keyed by VLAN name. The key is the name DO assigns, and is what `self_ips[*].vlan_key` refers to. | <pre>map(object({<br/>    tag      = optional(number)<br/>    mtu      = optional(number, 1500)<br/>    cmp_hash = optional(string, "default")<br/>    interfaces = list(object({<br/>      name   = string<br/>      tagged = optional(bool)<br/>    }))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_base_complete"></a> [base\_complete](#output\_base\_complete) | Ordering handshake (ADR 0004). Wire this into the HA peer module's `peer_base_complete` input so device trust is only asserted once both appliances have finished base onboarding. |
| <a name="output_declaration_summary"></a> [declaration\_summary](#output\_declaration\_summary) | What the rendered declaration contains, with no secrets: classes present, VLAN names and<br/>tags, self IP addresses, routes, provisioning levels, usernames, partitions, and the HA<br/>role and device group.<br/><br/>This is the review surface. `do_json` is redacted (ADR 0006), so a plan shows<br/>"(sensitive value)" with no diff — a change visible nowhere else is visible here. |
| <a name="output_partition_names"></a> [partition\_names](#output\_partition\_names) | Names of the LTM partitions created, for pointing CIS at its partition. |
| <a name="output_summary"></a> [summary](#output\_summary) | Compact description of what this appliance will be. |
| <a name="output_validation_errors"></a> [validation\_errors](#output\_validation\_errors) | Every configuration error found, aggregated. Empty on a valid configuration; a non-empty list fails the plan via the precondition in main.tf. Exposed so it can be asserted directly in tests. |
<!-- END_TF_DOCS -->
