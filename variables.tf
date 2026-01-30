# variables.tf
# Variable definitions with descriptions and validation

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "network-firewall"

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "owner" {
  description = "Email address of the project owner"
  type        = string
  default     = "cloud-team@example.com"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "IT-Security"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "firewall_subnet_cidr" {
  description = "CIDR block for firewall subnet"
  type        = string
  default     = "10.0.4.0/28"
}

variable "customer_subnet_cidr" {
  description = "CIDR block for customer subnet (public)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for test instance"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH key pair name for EC2 instance"
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Network Firewall"
  type        = bool
  default     = false
}

variable "firewall_policy_name" {
  description = "Name for the Network Firewall policy"
  type        = string
  default     = "network-firewall-policy"
}

variable "enable_firewall_logs" {
  description = "Enable Network Firewall flow logs"
  type        = bool
  default     = true
}

variable "enable_alert_logs" {
  description = "Enable Network Firewall alert logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "ssh_allowed_cidr" {
  description = "CIDR blocks allowed to SSH to EC2 instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
