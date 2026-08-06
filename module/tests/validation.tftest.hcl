##################################################
# Validation coverage
#
# Every rule that can stop a plan gets a failing case here. Cross-variable rules
# land in local.validation_errors and are asserted through the output;
# single-variable rules raise from their validation {} block and are asserted
# with expect_failures.
#
# enforce_validation = false throughout the cross-variable runs: a failed
# precondition makes every output unreadable, so each rule has to be asserted
# with the gate open. `precondition_fires` below proves the real gate works.
##################################################

mock_provider "bigip" {}

variables {
  enforce_validation = false

  hostname = "bigip-01.test.invalid"

  vlans = {
    internal = {
      tag        = 200
      interfaces = [{ name = "1.2" }]
    }
  }

  self_ips = {
    internal = {
      address  = "198.51.100.10/24"
      vlan_key = "internal"
    }
  }
}

##################################################
# The gate itself
#
# Without this, every run above could be passing against a permanently disabled
# hard stop and look identical.
##################################################

run "precondition_fires_on_a_real_error" {
  command = plan

  variables {
    enforce_validation = true

    self_ips = {
      internal = {
        address  = "198.51.100.10/24"
        vlan_key = "does-not-exist"
      }
    }
  }

  expect_failures = [terraform_data.validation]
}

run "valid_configuration_has_no_errors" {
  command = plan

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "a valid configuration must produce no validation errors"
  }
}

##################################################
# Cross-variable rules
##################################################

run "self_ip_referencing_an_unknown_vlan_key" {
  command = plan

  variables {
    self_ips = {
      internal = {
        address  = "198.51.100.10/24"
        vlan_key = "external"
      }
    }
  }

  assert {
    condition     = length(output.validation_errors) == 1
    error_message = "an unresolved vlan_key must produce exactly one error"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "vlan_key 'external'")
    error_message = "the error must name the unresolved key"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "internal")
    error_message = "the error must name both ends — the self IP and the missing VLAN"
  }
}

run "config_sync_ip_not_matching_a_self_ip" {
  command = plan

  variables {
    ha = {
      role           = "owner"
      local_password = "placeholder-not-a-real-password"
      peer_address   = "192.0.2.11"
      peer_password  = "placeholder-not-a-real-password"
      config_sync_ip = "203.0.113.99"
    }
  }

  assert {
    condition     = length(output.validation_errors) == 1
    error_message = "a config sync address that is not a self IP must be an error"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "203.0.113.99")
    error_message = "the error must name the offending address"
  }
}

run "failover_address_not_matching_a_self_ip" {
  command = plan

  variables {
    ha = {
      role             = "owner"
      local_password   = "placeholder-not-a-real-password"
      peer_address     = "192.0.2.11"
      peer_password    = "placeholder-not-a-real-password"
      config_sync_ip   = "198.51.100.10"
      failover_address = "203.0.113.99"
    }
  }

  assert {
    condition     = length(output.validation_errors) == 1
    error_message = "a failover address that is not a self IP must be an error"
  }
}

run "overrides_may_not_contradict_a_module_owned_class" {
  command = plan

  variables {
    do_declaration_overrides = {
      Common = {
        sneaky = {
          class       = "License"
          licenseType = "regKey"
          regKey      = "ZZZZZ-YYYYY-XXXXX-WWWWW-VVVVVVV"
        }
      }
    }
  }

  assert {
    condition     = length(output.validation_errors) == 1
    error_message = "the hatch must refuse a module-owned class"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "module-owned")
    error_message = "the error must say the class is module-owned"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "var.license")
    error_message = "the error must point at the typed variable that owns it"
  }
}

run "vlan_and_user_keys_may_not_collide" {
  command = plan

  variables {
    users = {
      internal = {
        password = "placeholder-not-a-real-password"
      }
    }
  }

  assert {
    condition     = length(output.validation_errors) == 1
    error_message = "a VLAN and a user sharing a key must be an error — one would silently overwrite the other"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "one key namespace")
    error_message = "the error must explain why the collision matters"
  }
}

run "reserved_tenant_keys_are_refused" {
  command = plan

  variables {
    vlans = {
      hostname = {
        tag        = 200
        interfaces = [{ name = "1.2" }]
      }
    }
    self_ips = {}
  }

  assert {
    condition     = length(output.validation_errors) == 1
    error_message = "a VLAN named after a tenant property must be an error"
  }

  assert {
    condition     = strcontains(output.validation_errors[0], "reserved")
    error_message = "the error must say the key is reserved"
  }
}

run "every_error_is_reported_at_once" {
  command = plan

  variables {
    self_ips = {
      a = {
        address  = "198.51.100.10/24"
        vlan_key = "nope-one"
      }
      b = {
        address  = "198.51.100.11/24"
        vlan_key = "nope-two"
      }
    }
    users = {
      internal = {
        password = "placeholder-not-a-real-password"
      }
    }
  }

  # One precondition reporting everything, rather than making the operator
  # re-plan once per typo.
  assert {
    condition     = length(output.validation_errors) == 3
    error_message = "all three errors must be reported together, not one at a time"
  }
}

##################################################
# Single-variable rules
##################################################

run "ha_role_must_be_owner_or_member" {
  command = plan

  variables {
    ha = {
      role           = "primary"
      local_password = "placeholder-not-a-real-password"
      peer_address   = "192.0.2.11"
      peer_password  = "placeholder-not-a-real-password"
      config_sync_ip = "198.51.100.10"
    }
  }

  expect_failures = [var.ha]
}

run "ha_role_is_required_when_ha_is_set" {
  command = plan

  variables {
    ha = {
      local_password = "placeholder-not-a-real-password"
      peer_address   = "192.0.2.11"
      peer_password  = "placeholder-not-a-real-password"
      config_sync_ip = "198.51.100.10"
    }
  }

  expect_failures = [var.ha]
}

run "config_sync_ip_must_not_carry_a_prefix_length" {
  command = plan

  variables {
    ha = {
      role           = "owner"
      local_password = "placeholder-not-a-real-password"
      peer_address   = "192.0.2.11"
      peer_password  = "placeholder-not-a-real-password"
      config_sync_ip = "198.51.100.10/24"
    }
  }

  expect_failures = [var.ha]
}

run "hostname_must_be_fully_qualified" {
  command = plan

  variables {
    hostname = "bigip-01"
  }

  expect_failures = [var.hostname]
}

run "provisioning_level_must_be_valid" {
  command = plan

  variables {
    provisioning = { ltm = "maximum" }
  }

  expect_failures = [var.provisioning]
}

run "provisioning_module_must_exist" {
  command = plan

  variables {
    provisioning = { kubernetes = "nominal" }
  }

  expect_failures = [var.provisioning]
}

run "self_ip_address_must_carry_a_prefix_length" {
  command = plan

  variables {
    self_ips = {
      internal = {
        address  = "198.51.100.10"
        vlan_key = "internal"
      }
    }
  }

  expect_failures = [var.self_ips]
}

run "allow_service_entries_must_be_protocol_port" {
  command = plan

  variables {
    self_ips = {
      internal = {
        address       = "198.51.100.10/24"
        vlan_key      = "internal"
        allow_service = ["https"]
      }
    }
  }

  expect_failures = [var.self_ips]
}

run "vlan_must_have_an_interface" {
  command = plan

  variables {
    vlans = {
      internal = {
        tag        = 200
        interfaces = []
      }
    }
    self_ips = {}
  }

  expect_failures = [var.vlans]
}

run "vlan_tag_must_be_in_range" {
  command = plan

  variables {
    vlans = {
      internal = {
        tag        = 5000
        interfaces = [{ name = "1.2" }]
      }
    }
    self_ips = {}
  }

  expect_failures = [var.vlans]
}

run "user_role_must_be_a_real_bigip_role" {
  command = plan

  variables {
    users = {
      cis = {
        password         = "placeholder-not-a-real-password"
        partition_access = { kubernetes = "superuser" }
      }
    }
  }

  expect_failures = [var.users]
}

run "route_gateway_must_be_an_address" {
  command = plan

  variables {
    routes = {
      default = {
        gw = "not-an-address"
      }
    }
  }

  expect_failures = [var.routes]
}
