# AWS Network Firewall - Single Zone Architecture (Public Subnet)

This Terraform project deploys a single Availability Zone AWS VPC architecture with integrated Network Firewall to inspect and control traffic between a public-facing customer subnet and the internet.

## Architecture Overview

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                    VPC: 10.0.0.0/16                     │
                              │                                                         │
    ┌───────────────┐         │  ┌─────────────────────────────────────────────────┐   │
    │   Internet    │         │  │           Firewall Subnet (10.0.4.0/28)         │   │
    │    Gateway    │◄────────┼──│                                                  │   │
    │  (igw-xxxx)   │         │  │    ┌─────────────────────────────────────────┐  │   │
    └───────┬───────┘         │  │    │   Network Firewall Endpoint (vpce-xxxx) │  │   │
            │                 │  │    └─────────────────────────────────────────┘  │   │
            │                 │  └─────────────────────────────────────────────────┘   │
            │                 │                          │                              │
            │                 │                          ▼                              │
            │                 │  ┌─────────────────────────────────────────────────┐   │
            │                 │  │         Customer Subnet (10.0.2.0/24)           │   │
            │                 │  │                  (Public Subnet)                 │   │
            │                 │  │    ┌─────────────────────────────────────────┐  │   │
            │                 │  │    │        EC2 Web Server (Elastic IP)      │  │   │
            │                 │  │    └─────────────────────────────────────────┘  │   │
            │                 │  └─────────────────────────────────────────────────┘   │
            │                 │                                                         │
            │                 └─────────────────────────────────────────────────────────┘
            │                                       Availability Zone 1
            └───────────────────────────────────────────────────────────────────────────
```

## Traffic Flow

### Outbound Traffic (EC2 → Internet)
1. EC2 instance initiates connection to internet
2. Traffic matches 0.0.0.0/0 in customer route table → Firewall Endpoint
3. Network Firewall inspects traffic against policies
4. If allowed, traffic forwarded to IGW (via firewall route table)
5. IGW routes to internet

### Inbound Traffic (Internet → EC2)
1. Traffic arrives at IGW destined for EC2's Elastic IP
2. IGW route table directs 10.0.2.0/24 traffic → Firewall Endpoint
3. Network Firewall inspects inbound traffic
4. If allowed, traffic forwarded to EC2 instance

## Route Tables

| Route Table | Destination | Target |
|-------------|-------------|--------|
| **IGW RT** | 10.0.2.0/24 | Firewall Endpoint |
| **Firewall RT** | 10.0.0.0/16 | local |
| **Firewall RT** | 0.0.0.0/0 | IGW |
| **Customer RT** | 10.0.0.0/16 | local |
| **Customer RT** | 0.0.0.0/0 | Firewall Endpoint |

## Quick Start

```bash
# Initialize
terraform init

# Review changes
terraform plan

# Deploy
terraform apply

# Get web server URL
terraform output web_url

# SSH to instance
eval $(terraform output -raw ssh_command)
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Project name | `network-firewall` |
| `environment` | Environment (dev/staging/prod) | `dev` |
| `aws_region` | AWS region | `us-east-1` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `firewall_subnet_cidr` | Firewall subnet CIDR | `10.0.4.0/28` |
| `customer_subnet_cidr` | Customer subnet CIDR | `10.0.2.0/24` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `key_name` | SSH key pair name | `""` |

## Firewall Policy

**Allowed Traffic (PASS)**:
- HTTPS (443), HTTP (80), SSH (22)
- DNS (53 UDP/TCP)
- ICMP (ping)

**Blocked Traffic (DROP)**:
- All other traffic

## Testing

After deployment:
```bash
# Access web server from internet
curl http://$(terraform output -raw ec2_public_ip)

# SSH to instance and test outbound
ssh -i your-key.pem ec2-user@$(terraform output -raw ec2_public_ip)
curl -I https://www.amazon.com
```

## Files

```
.
├── provider.tf       # Terraform & AWS provider config
├── main.tf           # Infrastructure resources
├── variables.tf      # Variable definitions
├── terraform.tfvars  # Variable values
├── locals.tf         # Computed values and tags
├── data.tf           # Data sources
├── outputs.tf        # Output values
├── user-data.sh      # EC2 user data script
└── README.md         # This file
```

## Cleanup

```bash
terraform destroy
```

## License

MIT License
