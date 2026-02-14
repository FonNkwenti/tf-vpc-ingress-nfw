# variables.tf
# Variable definitions for VPC Ingress Routing with Network Firewall Demo

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "vpc-ingress-nfw"

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

variable "webserver_subnet_cidr" {
  description = "CIDR block for webserver subnet (public)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for web server (ARM-based recommended for cost savings)"
  type        = string
  default     = "t4g.micro"
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
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_monitoring_dashboard" {
  description = "Enable CloudWatch monitoring dashboard for Network Firewall"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS Topic ARN for CloudWatch alarms (optional)"
  type        = string
  default     = ""
}
