# terraform.tfvars
# Environment-specific variable values

# Project identification
project_name = "nfw-single-zone"
environment  = "dev"
owner        = "cloud-team@example.com"
cost_center  = "IT-Security"

# Network configuration
aws_region           = "us-east-1"
vpc_cidr             = "10.0.0.0/16"
firewall_subnet_cidr = "10.0.4.0/28"
nat_subnet_cidr      = "10.0.2.0/24"
customer_subnet_cidr = "10.0.3.0/24"

# EC2 configuration
instance_type = "t3.micro"
key_name      = "default-use1" # Replace with your key name

# Firewall configuration
enable_deletion_protection = false
firewall_policy_name       = "nfw-policy"

# Logging configuration
enable_firewall_logs = true
enable_alert_logs    = true
log_retention_days   = 30

# Allowed IP for SSH (your IP address)
ssh_allowed_cidr = ["0.0.0.0/0"] # Replace with your IP: ["1.2.3.4/32"]

# Tags
tags = {
  Department  = "Security"
  Compliance  = "Required"
  Backup      = "Daily"
  Application = "NetworkFirewall"
}
