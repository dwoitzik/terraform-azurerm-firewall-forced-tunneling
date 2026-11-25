# ==========================================
# The Loop Breaker: Forced Tunneling Routing
# ==========================================

resource "azurerm_route_table" "spoke_udr" {
  name                          = "rt-forced-tunneling-${var.environment}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  # 1. Forced Tunneling: all internet-bound traffic through the firewall.
  route {
    name                   = "to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.fw.ip_configuration[0].private_ip_address
  }

  # 2. Azure Platform Bypass: the WireServer/host endpoint every Windows VM
  #    talks to for extensions, the Guest Agent, DHCP lease renewal, and
  #    activation checks. This is the one Microsoft's own forced-tunneling
  #    docs call out explicitly. Without it, VM extensions and Windows
  #    Activation break the moment traffic is forced through the firewall.
  route {
    name           = "bypass-azure-wireserver"
    address_prefix = "168.63.129.16/32"
    next_hop_type  = "Internet"
  }

  # 3. KMS Bypass: Windows activation (TCP 1688) must reach Azure KMS from an
  #    Azure public IP. azkms.core.windows.net moved to 20.118.99.224 and
  #    40.83.235.53 on 2022-10-03, and kms.core.windows.net has resolved to
  #    20.118.99.224 since 2023-03-01. Microsoft says 23.102.135.246 is no
  #    longer used and its route can be removed; it stays here only so that
  #    upgrading the module does not change existing route tables, and will be
  #    dropped in the next major version. Source:
  #    https://learn.microsoft.com/troubleshoot/azure/virtual-machines/windows/custom-routes-enable-kms-activation
  route {
    name           = "bypass-azure-kms-1"
    address_prefix = "20.118.99.224/32"
    next_hop_type  = "Internet"
  }

  route {
    name           = "bypass-azure-kms-2"
    address_prefix = "40.83.235.53/32"
    next_hop_type  = "Internet"
  }

  route {
    name           = "bypass-azure-kms-legacy"
    address_prefix = "23.102.135.246/32"
    next_hop_type  = "Internet"
  }

  # 4. Azure AD Bypass: prevent auth lockouts on the forced-tunneled spoke.
  route {
    name           = "bypass-azure-ad"
    address_prefix = "AzureActiveDirectory"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_subnet_route_table_association" "spoke_binding" {
  for_each       = azurerm_subnet.spoke_workload
  subnet_id      = each.value.id
  route_table_id = azurerm_route_table.spoke_udr.id
}
