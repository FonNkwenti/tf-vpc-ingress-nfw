# Project identification
project_name = "vpc-ingress-nfw"
environment  = "dev"
owner        = "cloud-infra@example.com"
cost_center  = "security"

aws_region            = "us-east-1"
vpc_cidr              = "10.0.0.0/16"
firewall_subnet_cidr  = "10.0.4.0/28"
webserver_subnet_cidr = "10.0.2.0/24"
instance_type = "t4g.micro"
enable_deletion_protection = false
firewall_policy_name       = "nfw-policy"
enable_firewall_logs = true
enable_alert_logs    = true
log_retention_days   = 30
enable_monitoring_dashboard = true

tags = {
  Department  = "Security"
  Application = "webserver"
}
