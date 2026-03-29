output "public_ip_address" {
  value       = azurerm_public_ip.main.ip_address
  description = "Public IP address of the VM"
}

output "ssh_command" {
  value       = "ssh -i ~/.ssh/devops-vm-key.pem devops@${azurerm_public_ip.main.ip_address}"
  description = "SSH command to connect to the VM"
}