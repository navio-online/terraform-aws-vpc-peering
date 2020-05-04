variable "requester_name" {
  description = "Readable alias for requester account name"
  type = string
  default = "requester"
}

variable "accepter_name" {
  description = "Readable alias for accepter account name"
  type = string
  default = "requester"
}

variable "requester_subnet_range" {
  description = "requester VPC subnet range in CIDR format"
  type        = list(string)
}

variable "requester_main_route_table_id" {
  description = "requester main route table ID used to update access to accepter network"
  type        = string
  default     = ""
}

variable "accepter_subnet_range" {
  description = "accepter VPC subnet range in CIDR format"
  type        = list(string)
}

variable "accepter_main_route_table_id" {
  description = "accepter main route table ID used to update access to requester network"
  type        = string
  default     = ""
}

variable "accepter_vpc_id" {
  description = "accepter VPC ID"
  type        = string
}

variable "requester_vpc_id" {
  description = "requester VPC ID"
  type        = string
}

variable "tags" {
  description = "Add custom tags to all resources"
  type        = map
  default     = {}
}
