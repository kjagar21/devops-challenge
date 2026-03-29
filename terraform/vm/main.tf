terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "devops-vm-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "devops-vm-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "devops-vm-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "devops-vm-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# NSG Association
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Data Disk
resource "azurerm_managed_disk" "docker" {
  name                 = "docker-data"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDExxnIERfkE6Z+ZQszoL/Ae3wwFAWnm7n68F7U1FW2J2aomctor3tVn0xFRAHkyim8qBoUk8S1Khj1E00zWlMV9GVEChJ0z/YBCoRrdLqIkngP5YIEsspxnHz8IZUnlc+1gtmvtkVEYcTAFR08KyBDqCCAr1OMPqZyncm+km+nj8WHY1euMD4JeInPm8LAA4gqcIkm2OxZ3BFCffTpNUzoNG6GUogJxnKctxcuAA9A6xrFt/cyfrfkE5Y2B0KxEPv4TvdG5/SSFeW4taDk7dqA3HXO+x3ihBuTQO8yci1CsZ5EsNVcX296UA2DozKfX/QLn/bIFf5DmJvB3v+5/PfUcCAN9RPtMkPt84sgHWsbt0aeRPDzZVopta5/FtA0jRPs8XwNe2d1e8a+wOG6hJNovI0D0MWfui09z8yvXOEHEy670EBOh2JiIjFBZZyw3+Lb91egTvXIvlzzT3lQGW2guH7fk5AnTu3+pzcIZTeHWE7m0fWNAhqdZjkWUCAc5Gk="
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# Attach Docker Disk to VM
resource "azurerm_virtual_machine_data_disk_attachment" "docker" {
  managed_disk_id    = azurerm_managed_disk.docker.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = 0
  caching            = "ReadWrite"
}