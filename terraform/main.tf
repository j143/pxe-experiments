terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "pxe_lab" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "pxe-experiments"
    environment = "lab"
  }
}

# ── Networking ────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "pxe_lab" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.pxe_lab.location
  resource_group_name = azurerm_resource_group.pxe_lab.name
  address_space       = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "host" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.pxe_lab.name
  virtual_network_name = azurerm_virtual_network.pxe_lab.name
  address_prefixes     = ["10.0.0.0/28"]
}

resource "azurerm_network_security_group" "host" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.pxe_lab.location
  resource_group_name = azurerm_resource_group.pxe_lab.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ssh_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "host" {
  subnet_id                 = azurerm_subnet.host.id
  network_security_group_id = azurerm_network_security_group.host.id
}

resource "azurerm_public_ip" "host" {
  name                = "${var.prefix}-pip"
  location            = azurerm_resource_group.pxe_lab.location
  resource_group_name = azurerm_resource_group.pxe_lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "host" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.pxe_lab.location
  resource_group_name = azurerm_resource_group.pxe_lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.host.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.host.id
  }

  # Enable IP forwarding so the host can route between its internal bridges
  enable_ip_forwarding = true
}

# ── Storage (Premium SSD) ─────────────────────────────────────────────────────

resource "azurerm_managed_disk" "data" {
  name                 = "${var.prefix}-data-disk"
  location             = azurerm_resource_group.pxe_lab.location
  resource_group_name  = azurerm_resource_group.pxe_lab.name
  storage_account_type = "StandardSSD_LRS"
  # 128 GiB Standard SSD - suitable for Azure Student Subscriptions
  disk_size_gb         = 128
  create_option        = "Empty"
}

# ── Host VM ───────────────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "host" {
  name                  = "${var.prefix}-host"
  location              = azurerm_resource_group.pxe_lab.location
  resource_group_name   = azurerm_resource_group.pxe_lab.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.host.id]

  # Ubuntu Server 24.04 LTS (latest)
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "${var.prefix}-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  # cloud-init bootstraps the host: enables nested virt, installs KVM tools
  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))

  tags = {
    project     = "pxe-experiments"
    environment = "lab"
    role        = "nested-virt-host"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.host.id
  lun                = 0
  caching            = "None"
}
