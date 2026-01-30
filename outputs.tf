# outputs.tf
# Output values for easy access to created resources

#------------------------------------------------------------------------------
# VPC Outputs
#------------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

#------------------------------------------------------------------------------
# Subnet Outputs
#------------------------------------------------------------------------------
output "firewall_subnet_id" {
  description = "ID of the firewall subnet"
  value       = aws_subnet.firewall.id
}

output "nat_subnet_id" {
  description = "ID of the NAT gateway subnet"
  value       = aws_subnet.nat.id
}

output "customer_subnet_id" {
  description = "ID of the customer subnet"
  value       = aws_subnet.customer.id
}

#------------------------------------------------------------------------------
# Gateway Outputs
#------------------------------------------------------------------------------
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

#------------------------------------------------------------------------------
# Network Firewall Outputs
#------------------------------------------------------------------------------
output "network_firewall_id" {
  description = "ID of the Network Firewall"
  value       = aws_networkfirewall_firewall.main.id
}

output "network_firewall_arn" {
  description = "ARN of the Network Firewall"
  value       = aws_networkfirewall_firewall.main.arn
}

output "firewall_endpoint_id" {
  description = "ID of the firewall endpoint (VPC endpoint)"
  value       = local.firewall_endpoint_id
}

output "firewall_policy_arn" {
  description = "ARN of the Network Firewall policy"
  value       = aws_networkfirewall_firewall_policy.main.arn
}

#------------------------------------------------------------------------------
# Route Table Outputs
#------------------------------------------------------------------------------
output "igw_route_table_id" {
  description = "ID of the IGW route table"
  value       = aws_route_table.igw.id
}

output "firewall_route_table_id" {
  description = "ID of the firewall subnet route table"
  value       = aws_route_table.firewall.id
}

output "nat_route_table_id" {
  description = "ID of the NAT subnet route table"
  value       = aws_route_table.nat.id
}

output "customer_route_table_id" {
  description = "ID of the customer subnet route table"
  value       = aws_route_table.customer.id
}

#------------------------------------------------------------------------------
# EC2 Instance Outputs
#------------------------------------------------------------------------------
output "ec2_instance_id" {
  description = "ID of the test EC2 instance"
  value       = aws_instance.test.id
}

output "ec2_private_ip" {
  description = "Private IP address of the test EC2 instance"
  value       = aws_instance.test.private_ip
}

output "ec2_ami_id" {
  description = "AMI ID used for the EC2 instance"
  value       = local.ec2_ami_id
}

output "ec2_ami_name" {
  description = "Name of the AMI used for the EC2 instance"
  value       = data.aws_ami.amazon_linux_2023.name
}

#------------------------------------------------------------------------------
# Security Group Outputs
#------------------------------------------------------------------------------
output "security_group_id" {
  description = "ID of the customer security group"
  value       = aws_security_group.customer.id
}

#------------------------------------------------------------------------------
# Logging Outputs
#------------------------------------------------------------------------------
output "cloudwatch_flow_log_group" {
  description = "CloudWatch Log Group for firewall flow logs"
  value       = var.enable_firewall_logs ? aws_cloudwatch_log_group.firewall_flow_logs[0].name : "N/A"
}

output "cloudwatch_alert_log_group" {
  description = "CloudWatch Log Group for firewall alert logs"
  value       = var.enable_alert_logs ? aws_cloudwatch_log_group.firewall_alert_logs[0].name : "N/A"
}

#------------------------------------------------------------------------------
# Connectivity Outputs
#------------------------------------------------------------------------------
output "ssh_command" {
  description = "SSH command to connect to the instance via NAT (requires bastion or SSM)"
  value       = var.key_name != "" ? "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.test.private_ip}" : "No SSH key configured - use SSM Session Manager"
}

output "availability_zone" {
  description = "Availability Zone used for deployment"
  value       = local.availability_zone
}

#------------------------------------------------------------------------------
# Deployment Information
#------------------------------------------------------------------------------
output "deployment_info" {
  description = "Deployment information"
  value = {
    project_name    = local.project_name
    environment     = var.environment
    region          = data.aws_region.current.name
    account_id      = data.aws_caller_identity.current.account_id
    deployment_date = formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())
  }
}

#------------------------------------------------------------------------------
# Architecture Summary
#------------------------------------------------------------------------------
output "architecture_summary" {
  description = "Summary of the deployed architecture"
  value = {
    vpc_cidr             = local.vpc_cidr
    firewall_subnet_cidr = local.firewall_subnet_cidr
    nat_subnet_cidr      = local.nat_subnet_cidr
    customer_subnet_cidr = local.customer_subnet_cidr
    availability_zone    = local.availability_zone
    firewall_endpoint    = local.firewall_endpoint_id
    nat_gateway_ip       = aws_eip.nat.public_ip
  }
}

#------------------------------------------------------------------------------
# Traffic Flow Documentation
#------------------------------------------------------------------------------
output "traffic_flow_outbound" {
  description = "Outbound traffic flow path"
  value       = "Customer Subnet (${local.customer_subnet_cidr}) → NAT Gateway (${aws_eip.nat.public_ip}) → Firewall Endpoint (${local.firewall_endpoint_id}) → IGW → Internet"
}

output "traffic_flow_inbound" {
  description = "Inbound traffic flow path (return traffic)"
  value       = "Internet → IGW → Firewall Endpoint (${local.firewall_endpoint_id}) → NAT Subnet → Customer Subnet (${local.customer_subnet_cidr})"
}
