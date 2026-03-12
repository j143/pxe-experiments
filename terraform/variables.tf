variable "prefix" {
  description = "Prefix added to all resource names."
  type        = string
  default     = "pxe-lab"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
  default     = "pxe-lab-rg"
}

variable "location" {
  description = "Azure region to deploy into."
  type        = string
  default     = "eastus2"
}

variable "vm_size" {
  description = <<-EOT
    Azure VM size for the host (nested-virtualization capable).
    Standard_D4s_v3  – 4 vCPU / 16 GiB RAM  (Azure Student Subscription default)
    Standard_D8s_v3  – 8 vCPU / 32 GiB RAM  (cost-effective alternative)
    Standard_E8s_v4  – 8 vCPU / 64 GiB RAM  (memory-optimised alternative)
  EOT
  type        = string
  default     = "Standard_D4s_v3"

  validation {
    condition = contains([
      "Standard_D4s_v3",
      "Standard_D8s_v3",
      "Standard_D16s_v3",
      "Standard_E8s_v4",
      "Standard_E16s_v4",
    ], var.vm_size)
    error_message = "vm_size must be a nested-virtualisation-capable Azure SKU."
  }
}

variable "admin_username" {
  description = "OS admin user created on the host VM."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Local path to the SSH public key (~/.ssh/id_rsa.pub by default)."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_ssh_source_cidr" {
  description = "CIDR block allowed to SSH into the host VM. Set this to your own IP or CIDR (e.g. '203.0.113.5/32'). Do NOT leave as '0.0.0.0/0' in production."
  type        = string

  validation {
    condition     = var.admin_ssh_source_cidr != "0.0.0.0/0" && var.admin_ssh_source_cidr != "*"
    error_message = "admin_ssh_source_cidr must be restricted to a specific IP or CIDR block, not '0.0.0.0/0' or '*'."
  }
}
