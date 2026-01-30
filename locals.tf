# locals.tf
# Local values and computed data

locals {
  # Project metadata
  project_name = "${var.project_name}-${var.environment}"

  # Network configuration
  vpc_cidr             = var.vpc_cidr
  firewall_subnet_cidr = var.firewall_subnet_cidr
  customer_subnet_cidr = var.customer_subnet_cidr

  # Select first available AZ for single-zone deployment
  availability_zone = data.aws_availability_zones.available.names[0]

  # AMI ID from data source
  ec2_ami_id = data.aws_ami.amazon_linux_2023.id

  # Compute user data file path
  user_data_file = "${path.module}/user-data.sh"

  # Common tags applied to all resources
  common_tags = merge(
    var.tags,
    {
      Project        = var.project_name
      Environment    = var.environment
      ManagedBy      = "Terraform"
      DeploymentDate = formatdate("YYYY-MM-DD", timestamp())
      Owner          = var.owner
      CostCenter     = var.cost_center
      Architecture   = "single-zone-network-firewall"
    }
  )

  # Resource-specific tags
  vpc_tags = merge(
    local.common_tags,
    {
      Name         = "${local.project_name}-vpc"
      ResourceType = "VPC"
    }
  )

  firewall_subnet_tags = merge(
    local.common_tags,
    {
      Name       = "${local.project_name}-firewall-subnet"
      SubnetType = "Firewall"
      CIDR       = local.firewall_subnet_cidr
    }
  )

  customer_subnet_tags = merge(
    local.common_tags,
    {
      Name       = "${local.project_name}-customer-subnet"
      SubnetType = "Customer"
      CIDR       = local.customer_subnet_cidr
      PublicIP   = "Enabled"
    }
  )

  igw_tags = merge(
    local.common_tags,
    {
      Name         = "${local.project_name}-igw"
      ResourceType = "InternetGateway"
    }
  )

  firewall_tags = merge(
    local.common_tags,
    {
      Name               = "${local.project_name}-network-firewall"
      ResourceType       = "NetworkFirewall"
      DeletionProtection = var.enable_deletion_protection
    }
  )

  ec2_tags = merge(
    local.common_tags,
    {
      Name         = "${local.project_name}-webserver"
      ResourceType = "EC2Instance"
      Role         = "WebServer"
      AMI          = local.ec2_ami_id
    }
  )

  # Route table tags
  igw_route_table_tags = merge(
    local.common_tags,
    {
      Name           = "${local.project_name}-igw-rt"
      RouteTableType = "InternetGateway"
      AssociatedWith = "IGW"
    }
  )

  firewall_route_table_tags = merge(
    local.common_tags,
    {
      Name           = "${local.project_name}-firewall-rt"
      RouteTableType = "FirewallSubnet"
      AssociatedWith = "FirewallSubnet"
    }
  )

  customer_route_table_tags = merge(
    local.common_tags,
    {
      Name           = "${local.project_name}-customer-rt"
      RouteTableType = "CustomerSubnet"
      AssociatedWith = "CustomerSubnet"
    }
  )

  # Security group tags
  security_group_tags = merge(
    local.common_tags,
    {
      Name         = "${local.project_name}-customer-sg"
      ResourceType = "SecurityGroup"
    }
  )
}
