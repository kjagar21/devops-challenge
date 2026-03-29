variable "resource_group_name" {
  default = "devops-challenge-rg"
}

variable "location" {
  default = "Sweden Central"
}

variable "cluster_name" {
  default = "devops-aks"
}

variable "node_count" {
  default = 1
}

variable "node_size" {
  default = "Standard_D2s_v3"
}