# main.tf
# AWS Network Firewall - Single Zone Architecture (Public Subnet)
# Main infrastructure resources

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.vpc_tags
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = local.igw_tags
}

#------------------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------------------

# Firewall Subnet - hosts the Network Firewall endpoint
resource "aws_subnet" "firewall" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.firewall_subnet_cidr
  availability_zone = local.availability_zone

  tags = local.firewall_subnet_tags
}

# Customer Subnet - hosts customer workloads (public subnet)
resource "aws_subnet" "customer" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.customer_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true # Public subnet for public-facing instances

  tags = local.customer_subnet_tags
}

#------------------------------------------------------------------------------
# Elastic IP for EC2 Instance
#------------------------------------------------------------------------------
resource "aws_eip" "ec2" {
  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-ec2-eip"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip_association" "ec2" {
  instance_id   = aws_instance.test.id
  allocation_id = aws_eip.ec2.id
}

#------------------------------------------------------------------------------
# Network Firewall Policy - Stateful Rule Groups
#------------------------------------------------------------------------------

# Stateful rule group for allowing standard traffic
resource "aws_networkfirewall_rule_group" "allow_traffic" {
  capacity = 100
  name     = "${local.project_name}-allow-traffic"
  type     = "STATEFUL"

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
    rules_source {
      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "443"
          direction        = "ANY"
          protocol         = "TCP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["1"]
        }
      }

      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "80"
          direction        = "ANY"
          protocol         = "TCP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["2"]
        }
      }

      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "53"
          direction        = "ANY"
          protocol         = "UDP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["3"]
        }
      }

      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "53"
          direction        = "ANY"
          protocol         = "TCP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["4"]
        }
      }

      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "ICMP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["5"]
        }
      }

      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "22"
          direction        = "ANY"
          protocol         = "TCP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["6"]
        }
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-allow-traffic-rules"
    }
  )
}

# Drop all other traffic (default deny)
resource "aws_networkfirewall_rule_group" "drop_all" {
  capacity = 10
  name     = "${local.project_name}-drop-all"
  type     = "STATEFUL"

  rule_group {
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
    rules_source {
      stateful_rule {
        action = "DROP"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "IP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword  = "sid"
          settings = ["100"]
        }
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-drop-all-rules"
    }
  )
}

#------------------------------------------------------------------------------
# Network Firewall Policy
#------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall_policy" "main" {
  name = var.firewall_policy_name

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.allow_traffic.arn
    }

    stateful_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.drop_all.arn
    }

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-firewall-policy"
    }
  )
}

#------------------------------------------------------------------------------
# Network Firewall
#------------------------------------------------------------------------------
resource "aws_networkfirewall_firewall" "main" {
  name                = "${local.project_name}-nfw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.main.id

  delete_protection                 = var.enable_deletion_protection
  subnet_change_protection          = false
  firewall_policy_change_protection = false

  subnet_mapping {
    subnet_id = aws_subnet.firewall.id
  }

  tags = local.firewall_tags
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups for Network Firewall
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "firewall_flow_logs" {
  count = var.enable_firewall_logs ? 1 : 0

  name              = "/aws/networkfirewall/${local.project_name}/flow"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_name}-firewall-flow-logs"
      LogType = "Flow"
    }
  )
}

resource "aws_cloudwatch_log_group" "firewall_alert_logs" {
  count = var.enable_alert_logs ? 1 : 0

  name              = "/aws/networkfirewall/${local.project_name}/alert"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.project_name}-firewall-alert-logs"
      LogType = "Alert"
    }
  )
}

#------------------------------------------------------------------------------
# Network Firewall Logging Configuration
#------------------------------------------------------------------------------
resource "aws_networkfirewall_logging_configuration" "main" {
  count = var.enable_firewall_logs || var.enable_alert_logs ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    dynamic "log_destination_config" {
      for_each = var.enable_firewall_logs ? [1] : []
      content {
        log_destination = {
          logGroup = aws_cloudwatch_log_group.firewall_flow_logs[0].name
        }
        log_destination_type = "CloudWatchLogs"
        log_type             = "FLOW"
      }
    }

    dynamic "log_destination_config" {
      for_each = var.enable_alert_logs ? [1] : []
      content {
        log_destination = {
          logGroup = aws_cloudwatch_log_group.firewall_alert_logs[0].name
        }
        log_destination_type = "CloudWatchLogs"
        log_type             = "ALERT"
      }
    }
  }
}

#------------------------------------------------------------------------------
# Route Tables
#------------------------------------------------------------------------------

# Local for firewall endpoint ID
locals {
  firewall_endpoint_id = [for ep in aws_networkfirewall_firewall.main.firewall_status[0].sync_states : ep.attachment[0].endpoint_id][0]
}

# IGW Route Table - Routes inbound traffic to firewall
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id

  # Route for customer subnet traffic through firewall
  route {
    cidr_block      = local.customer_subnet_cidr
    vpc_endpoint_id = local.firewall_endpoint_id
  }

  tags = local.igw_route_table_tags
}

# Associate IGW route table with Internet Gateway (edge association)
resource "aws_route_table_association" "igw" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw.id
}

# Firewall Subnet Route Table
resource "aws_route_table" "firewall" {
  vpc_id = aws_vpc.main.id

  # Route to internet via IGW
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = local.firewall_route_table_tags
}

resource "aws_route_table_association" "firewall" {
  subnet_id      = aws_subnet.firewall.id
  route_table_id = aws_route_table.firewall.id
}

# Customer Subnet Route Table - routes through firewall
resource "aws_route_table" "customer" {
  vpc_id = aws_vpc.main.id

  # Route to internet through firewall endpoint
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = local.firewall_endpoint_id
  }

  tags = local.customer_route_table_tags
}

resource "aws_route_table_association" "customer" {
  subnet_id      = aws_subnet.customer.id
  route_table_id = aws_route_table.customer.id
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------

# Security Group for Customer Subnet instances
resource "aws_security_group" "customer" {
  name_prefix = "${local.project_name}-customer-sg-"
  description = "Security group for customer subnet resources"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from anywhere"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.security_group_tags

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# EC2 Test Instance (Public-facing Web Server)
#------------------------------------------------------------------------------
resource "aws_instance" "test" {
  ami                    = local.ec2_ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  subnet_id              = aws_subnet.customer.id
  vpc_security_group_ids = [aws_security_group.customer.id]

  user_data = file(local.user_data_file)

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = merge(
      local.common_tags,
      {
        Name = "${local.project_name}-root-volume"
      }
    )
  }

  tags = local.ec2_tags

  depends_on = [
    aws_internet_gateway.main,
    aws_networkfirewall_firewall.main,
    aws_route_table_association.customer
  ]
}
