##################################################
# Golden declaration
#
# This module's entire value is a correctly-rendered DO declaration, so the
# declaration IS the test subject (ADR 0007). A wrong allowService or a missing
# DeviceTrust field fails slowly and opaquely against a real appliance, and is
# free to catch here.
#
# do_json is sensitive() (ADR 0006), so assertions unwrap it with nonsensitive().
# Every credential below is a placeholder and no appliance exists — the unwrap
# exposes nothing.
#
# The summary is asserted alongside the declaration in the same runs, because a
# class present in one and missing from the other changes unreviewed.
##################################################

mock_provider "bigip" {}

variables {
  hostname = "bigip-01.test.invalid"

  license = {
    reg_key = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEEEE"
  }

  provisioning = {
    ltm = "nominal"
  }

  dns = {
    name_servers = ["192.0.2.53", "192.0.2.54"]
    search       = ["test.invalid"]
  }

  ntp = {
    servers  = ["192.0.2.123"]
    timezone = "UTC"
  }

  vlans = {
    external = {
      tag        = 100
      interfaces = [{ name = "1.1", tagged = true }]
    }
    internal = {
      tag        = 200
      mtu        = 9000
      interfaces = [{ name = "1.2", tagged = true }]
    }
    ha = {
      tag        = 300
      interfaces = [{ name = "1.3", tagged = true }]
    }
  }

  self_ips = {
    external = {
      address       = "192.0.2.10/24"
      vlan_key      = "external"
      allow_service = ["none"]
    }
    internal = {
      address       = "198.51.100.10/24"
      vlan_key      = "internal"
      allow_service = ["tcp:443", "udp:53"]
    }
    ha = {
      address       = "203.0.113.10/24"
      vlan_key      = "ha"
      allow_service = ["default"]
    }
  }

  routes = {
    default = {
      gw = "192.0.2.1"
    }
    internal = {
      network = "10.20.0.0/16"
      gw      = "198.51.100.1"
      mtu     = 9000
    }
  }

  users = {
    cis = {
      password         = "placeholder-not-a-real-password"
      shell            = "none"
      partition_access = { "all-partitions" = "admin" }
    }
  }

  partitions = {
    kubernetes = {
      description = "CIS-managed partition"
    }
  }
}

##################################################
# Standalone appliance
##################################################

run "base_declaration_is_well_formed" {
  command = plan

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).class == "Device"
    error_message = "the declaration envelope must be a Device declaration"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).schemaVersion == "1.12.0"
    error_message = "schemaVersion must be pinned to 1.12.0"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.class == "Tenant"
    error_message = "Common must be a Tenant"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.hostname == "bigip-01.test.invalid"
    error_message = "hostname must be rendered at the tenant level"
  }
}

run "base_declaration_renders_every_mvp_class" {
  command = plan

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.myLicense.licenseType == "regKey"
    error_message = "License must be rendered as a regKey licence"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.myProvisioning.ltm == "nominal"
    error_message = "CIS requires ltm provisioned at nominal or better"
  }

  assert {
    condition     = tolist(jsondecode(nonsensitive(bigip_do.base.do_json)).Common.myDns.nameServers) == tolist(["192.0.2.53", "192.0.2.54"])
    error_message = "DNS nameServers must be rendered"
  }

  # NTP is not optional hygiene: device trust fails on clock skew.
  assert {
    condition     = tolist(jsondecode(nonsensitive(bigip_do.base.do_json)).Common.myNtp.servers) == tolist(["192.0.2.123"])
    error_message = "NTP servers must be rendered"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.myNtp.timezone == "UTC"
    error_message = "timezone belongs on the NTP class, per the DO schema"
  }
}

run "vlans_render_with_interfaces_and_tags" {
  command = plan

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.external.class == "VLAN"
    error_message = "the VLAN map key must become the DO VLAN name"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.external.tag == 100
    error_message = "VLAN tag must be rendered"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.external.interfaces[0].name == "1.1"
    error_message = "VLAN interfaces must be rendered as objects carrying a name"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.external.interfaces[0].tagged == true
    error_message = "an explicitly tagged interface must render tagged"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.internal.mtu == 9000
    error_message = "a non-default MTU must be rendered"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.ha.mtu == 1500
    error_message = "MTU must default to 1500"
  }
}

run "self_ips_render_both_allow_service_forms" {
  command = plan

  # Every class in a DO tenant shares one key namespace. This fixture uses the
  # same keys for VLANs and self IPs deliberately: unprefixed, merge() would
  # silently drop the VLAN.
  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.external.class == "VLAN"
    error_message = "a self IP sharing a VLAN's key must not overwrite the VLAN"
  }

  # A preset renders as a bare string; a service list renders as an array. They
  # are different JSON types out of one variable, which is why the renderer uses
  # two comprehensions rather than a ternary.
  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.selfip_external.allowService == "none"
    error_message = "a preset allow_service must render as a bare string"
  }

  assert {
    condition     = tolist(jsondecode(nonsensitive(bigip_do.base.do_json)).Common.selfip_internal.allowService) == tolist(["tcp:443", "udp:53"])
    error_message = "a service list allow_service must render as an array"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.selfip_internal.vlan == "internal"
    error_message = "vlan_key must resolve to the VLAN name"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.selfip_external.trafficGroup == "traffic-group-local-only"
    error_message = "traffic_group must default to traffic-group-local-only"
  }
}

run "routes_and_users_render" {
  command = plan

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.route_default.network == "default"
    error_message = "network must default to DO's 'default' spelling"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.route_internal.mtu == 9000
    error_message = "a route MTU must be rendered when set"
  }

  assert {
    condition     = !contains(keys(jsondecode(nonsensitive(bigip_do.base.do_json)).Common.route_default), "mtu")
    error_message = "an unset route MTU must be omitted, not rendered null"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.cis.userType == "regular"
    error_message = "users must render as regular users"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.cis.partitionAccess["all-partitions"].role == "admin"
    error_message = "partition_access must render as scope -> {role}"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.cis.forceInitialPasswordChange == false
    error_message = "service accounts must not carry DO's forced initial password change — it blocks the first REST login"
  }
}

##################################################
# The HA path is absent unless asked for
##################################################

run "standalone_creates_no_ha_declaration" {
  command = plan

  assert {
    condition     = length(bigip_do.ha) == 0
    error_message = "a standalone appliance must not create an HA declaration"
  }

  assert {
    condition     = length(terraform_data.peer_gate) == 0
    error_message = "a standalone appliance must not create a peer gate"
  }

  assert {
    condition     = !contains(keys(jsondecode(nonsensitive(bigip_do.base.do_json)).Common), "deviceTrust")
    error_message = "the base declaration must never carry DeviceTrust"
  }

  assert {
    condition     = !contains(keys(jsondecode(nonsensitive(bigip_do.base.do_json)).Common), "failoverGroup")
    error_message = "the base declaration must never carry a DeviceGroup"
  }

  assert {
    condition     = output.summary.ha_role == "standalone"
    error_message = "summary must report a standalone appliance"
  }
}

##################################################
# HA owner
##################################################

run "ha_owner_emits_trust_sync_and_device_group" {
  command = plan

  variables {
    ha = {
      role             = "owner"
      local_password   = "placeholder-not-a-real-password"
      peer_address     = "192.0.2.11"
      peer_password    = "placeholder-not-a-real-password"
      config_sync_ip   = "203.0.113.10"
      failover_address = "203.0.113.10"
      members          = ["bigip-01.test.invalid", "bigip-02.test.invalid"]
    }
  }

  assert {
    condition     = length(bigip_do.ha) == 1
    error_message = "an HA appliance must create the HA declaration"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.deviceTrust.remoteHost == "192.0.2.11"
    error_message = "DeviceTrust must point at the peer"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.deviceTrust.localUsername == "admin"
    error_message = "DeviceTrust localUsername must default to admin"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.configSync.configsyncIp == "203.0.113.10"
    error_message = "ConfigSync must use the declared config sync address"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.failoverGroup.class == "DeviceGroup"
    error_message = "the owner must emit the DeviceGroup"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.failoverGroup.owner == "bigip-01.test.invalid"
    error_message = "the device group owner must default to this appliance's hostname"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.failoverGroup.type == "sync-failover"
    error_message = "device group type must default to sync-failover"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.failoverUnicast.port == 1026
    error_message = "failover unicast port must default to 1026"
  }

  assert {
    condition     = output.declaration_summary.ha.role == "owner"
    error_message = "summary must report the HA role"
  }

  assert {
    condition     = contains(output.declaration_summary.classes, "DeviceGroup")
    error_message = "summary classes must include DeviceGroup for an owner"
  }
}

##################################################
# HA member
##################################################

run "ha_member_does_not_emit_device_group" {
  command = plan

  variables {
    ha = {
      role           = "member"
      local_password = "placeholder-not-a-real-password"
      peer_address   = "192.0.2.10"
      peer_password  = "placeholder-not-a-real-password"
      config_sync_ip = "203.0.113.10"
    }
  }

  assert {
    condition     = !contains(keys(jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common), "failoverGroup")
    error_message = "only the owner may emit the DeviceGroup — this is the asymmetry ADR 0003 makes explicit"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.ha[0].do_json)).Common.deviceTrust.class == "DeviceTrust"
    error_message = "a member still establishes trust"
  }

  assert {
    condition     = !contains(output.declaration_summary.classes, "DeviceGroup")
    error_message = "summary must not claim a DeviceGroup on a member"
  }
}

##################################################
# The summary is the review surface, so it must not leak
##################################################

run "summary_carries_shape_not_secrets" {
  command = plan

  assert {
    condition     = output.declaration_summary.license == "regKey"
    error_message = "summary must report that a licence is asserted"
  }

  assert {
    condition     = !strcontains(jsonencode(output.declaration_summary), "AAAAA-BBBBB-CCCCC-DDDDD-EEEEEEE")
    error_message = "the registration key must never reach an output"
  }

  assert {
    condition     = !strcontains(jsonencode(output.declaration_summary), "placeholder-not-a-real-password")
    error_message = "no password may ever reach an output"
  }

  assert {
    condition     = output.declaration_summary.users == tolist(["cis"])
    error_message = "summary carries the NAMES of credentials, not their values"
  }

  assert {
    condition     = output.declaration_summary.self_ips["internal"].address == "198.51.100.10/24"
    error_message = "summary must carry self IP addresses so a change is reviewable"
  }
}

##################################################
# Escape hatch
##################################################

run "overrides_add_a_class_and_are_reported" {
  command = plan

  variables {
    do_declaration_overrides = {
      Common = {
        mySnmp = {
          class    = "SnmpAgent"
          contact  = "ops@test.invalid"
          location = "lab"
        }
      }
    }
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.mySnmp.class == "SnmpAgent"
    error_message = "the hatch must be able to add a class the module does not render"
  }

  assert {
    condition     = jsondecode(nonsensitive(bigip_do.base.do_json)).Common.hostname == "bigip-01.test.invalid"
    error_message = "an override must not disturb the typed classes around it"
  }

  assert {
    condition     = output.declaration_summary.overridden_keys == tolist(["Common.mySnmp"])
    error_message = "anything set through the hatch must be visible in the summary — it is invisible to validation"
  }
}
