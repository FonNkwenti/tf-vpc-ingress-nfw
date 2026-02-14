# VPC Ingress Routing Demo with Network Firewall

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

# WebServer Subnet - hosts the web server (public subnet)
resource "aws_subnet" "webserver" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.webserver_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true # Public subnet for public-facing instances

  tags = local.webserver_subnet_tags
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
  instance_id   = aws_instance.webserver.id
  allocation_id = aws_eip.ec2.id
}

#------------------------------------------------------------------------------
# Route Tables
#------------------------------------------------------------------------------

# Local for firewall endpoint ID (defined after firewall is created)
locals {
  firewall_endpoint_id = [for ep in aws_networkfirewall_firewall.main.firewall_status[0].sync_states : ep.attachment[0].endpoint_id][0]
}

# IGW Route Table - Routes inbound traffic to firewall
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id

  # Route for webserver subnet traffic through firewall (VPC Ingress Routing)
  route {
    cidr_block      = local.webserver_subnet_cidr
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


resource "aws_route_table" "webserver" {
  vpc_id = aws_vpc.main.id

  # Route to internet through firewall endpoint
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = local.firewall_endpoint_id
  }

  tags = local.webserver_route_table_tags
}

resource "aws_route_table_association" "webserver" {
  subnet_id      = aws_subnet.webserver.id
  route_table_id = aws_route_table.webserver.id
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------

# Security Group for WebServer Subnet instances
resource "aws_security_group" "webserver" {
  name_prefix = "${local.project_name}-webserver-sg-"
  description = "Security group for webserver subnet resources"
  vpc_id      = aws_vpc.main.id

  # For EC2Instance Connect on port 22 but from AWS service IPs
  ingress {
    description = "EC2 Instance Connect (SSH) from AWS IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.206.107.24/29"] # EC2 Instance Connect IP range for us-east-1
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
# IAM Role for EC2 Instance Connect
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_instance_connect" {
  name               = "${local.project_name}-ec2-instance-connect-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_instance_connect" {
  role       = aws_iam_role.ec2_instance_connect.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_connect" {
  name = "${local.project_name}-ec2-instance-connect-profile"
  role = aws_iam_role.ec2_instance_connect.name

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# EC2 Web Server Instance
#------------------------------------------------------------------------------
resource "aws_instance" "webserver" {
  ami                    = local.ec2_ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.webserver.id
  vpc_security_group_ids = [aws_security_group.webserver.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_connect.name

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
    aws_route_table_association.webserver
  ]
}
