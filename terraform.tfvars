# terraform.tfvars
# Environment-specific variable values for VPC Ingress Routing with Network Firewall Demo

# Project identification
project_name = "vpc-ingress-nfw"
environment  = "dev"
owner        = "cloud-infra@example.com"
cost_center  = "security"

# Network configuration
aws_region            = "us-east-1"
vpc_cidr              = "10.0.0.0/16"
firewall_subnet_cidr  = "10.0.4.0/28"
webserver_subnet_cidr = "10.0.2.0/24"

# EC2 configuration - using ARM-based instance for cost savings
instance_type = "t4g.micro"

# Firewall configuration
enable_deletion_protection = false
firewall_policy_name       = "nfw-policy"

# Logging configuration
enable_firewall_logs = true
enable_alert_logs    = true
log_retention_days   = 30

# Monitoring dashboard
enable_monitoring_dashboard = true
# alarm_sns_topic_arn         = "arn:aws:sns:us-east-1:123456789012:alerts" # Optional: SNS topic for alerts

# Tags
tags = {
  Department  = "Security"
  Application = "webserver"
}
