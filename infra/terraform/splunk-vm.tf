// Ubuntu 22.04 LTS VM for Splunk Enterprise Free.
// Splunk itself is installed manually via infra/scripts/install-splunk.sh
// (CLAUDE.md line 265 + docs/specs/infra-v1.md FR-22).

// ---- SSH keypair ----
// Generated fresh on first apply. Private key is written to disk at
// infra/private_key/splunk.pem (0600) and is recoverable from state via
// `terraform output -raw splunk_ssh_private_key`.

resource "tls_private_key" "splunk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "splunk_private_key" {
  content         = tls_private_key.splunk.private_key_pem
  filename        = "${path.module}/../private_key/splunk.pem"
  file_permission = "0600"
}

// ---- Public IP ----

resource "azurerm_public_ip" "splunk" {
  name                = "${var.splunk_vm_name}-pip"
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

// ---- NSG ----
// Three rules:
//   22/tcp   — operator IP only (auto-detected via ipify.org)
//   8000/tcp — operator IP only (Splunk Web UI)
//   8088/tcp — AKS node subnet only (HEC, reached from Fluent Bit pods)
// No rule allows 0.0.0.0/0 on any management port.

resource "azurerm_network_security_group" "splunk" {
  name                = "${var.splunk_vm_name}-nsg"
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  tags                = local.common_tags

  security_rule {
    name                       = "allow-ssh-operator"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.operator_ip_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-splunk-web-operator"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000"
    source_address_prefix      = local.operator_ip_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-hec-aks-subnet"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8088"
    source_address_prefix      = var.aks_subnet_cidr
    destination_address_prefix = "*"
  }
}

// Attach NSG to the Splunk subnet so the rules apply to all NICs in it.
resource "azurerm_subnet_network_security_group_association" "splunk" {
  subnet_id                 = azurerm_subnet.splunk.id
  network_security_group_id = azurerm_network_security_group.splunk.id
}

// ---- NIC ----

resource "azurerm_network_interface" "splunk" {
  name                = "${var.splunk_vm_name}-nic"
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.splunk.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.splunk.id
  }
}

// ---- Data disk for Splunk indexes ----

resource "azurerm_managed_disk" "splunk_data" {
  name                 = "${var.splunk_vm_name}-data"
  location             = azurerm_resource_group.money_honey.location
  resource_group_name  = azurerm_resource_group.money_honey.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.splunk_disk_gb
  tags                 = local.common_tags
}

// ---- Linux VM (Ubuntu 22.04 LTS) ----

resource "azurerm_linux_virtual_machine" "splunk" {
  name                = var.splunk_vm_name
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  size                = var.splunk_vm_sku
  admin_username      = var.splunk_admin_username
  tags                = local.common_tags

  // Key-only auth. No password auth anywhere.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.splunk_admin_username
    public_key = tls_private_key.splunk.public_key_openssh
  }

  network_interface_ids = [
    azurerm_network_interface.splunk.id,
  ]

  // Pinned Ubuntu 22.04 LTS gen2 image. Never use "latest".
  source_image_reference {
    publisher = var.splunk_image_publisher
    offer     = var.splunk_image_offer
    sku       = var.splunk_image_sku
    version   = var.splunk_image_version
  }

  os_disk {
    name                 = "${var.splunk_vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 30
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "splunk_data" {
  managed_disk_id    = azurerm_managed_disk.splunk_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.splunk.id
  lun                = 0
  caching            = "ReadWrite"
}
