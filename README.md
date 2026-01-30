# AWS Network Firewall - Single Zone Architecture

This Terraform project deploys a single Availability Zone AWS VPC architecture with integrated Network Firewall to inspect and control traffic between a customer subnet and the internet.

## Architecture Overview

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                    VPC: 10.0.0.0/16                     │
                              │                                                         │
    ┌───────────────┐         │  ┌─────────────────────────────────────────────────┐   │
    │   Internet    │         │  │           Firewall Subnet (10.0.4.0/28)         │   │
    │    Gateway    │◄────────┼──│                                                  │   │
    │  (igw-xxxx)   │         │  │    ┌─────────────────────────────────┐          │   │
    └───────┬───────┘         │  │    │   Network Firewall Endpoint     │          │   │
            │                 │  │    │        (vpce-xxxx)              │          │   │
            │                 │  │    └─────────────────────────────────┘          │   │
            │                 │  └─────────────────────────────────────────────────┘   │
            │                 │                          │                              │
            │                 │                          ▼                              │
            │                 │  ┌─────────────────────────────────────────────────┐   │
            │                 │  │           NAT Subnet (10.0.2.0/24)              │   │
            │                 │  │                                                  │   │
            │                 │  │    ┌─────────────────────────────────┐          │   │
            │                 │  │    │       NAT Gateway               │          │   │
            │                 │  │    │      (nat-xxxx)                 │          │   │
            │                 │  │    └─────────────────────────────────┘          │   │
            │                 │  └─────────────────────────────────────────────────┘   │
            │                 │                          │                              │
            │                 │                          ▼                              │
            │                 │  ┌─────────────────────────────────────────────────┐   │
            │                 │  │         Customer Subnet (10.0.3.0/24)           │   │
            │                 │  │                                                  │   │
            │                 │  │    ┌─────────────────────────────────┐          │   │
            │                 │  │    │        EC2 Instance             │          │   │
            │                 │  │    │   (Test Web Server)             │          │   │
            │                 │  │    └─────────────────────────────────┘          │   │
            │                 │  └─────────────────────────────────────────────────┘   │
            │                 │                                                         │
            │                 └─────────────────────────────────────────────────────────┘
            │                                       Availability Zone 1
            └───────────────────────────────────────────────────────────────────────────
```

## Traffic Flow

### Outbound Traffic (Customer → Internet)
1. EC2 instance in customer subnet initiates connection
2. Traffic routed to NAT Gateway (via customer subnet route table)
3. NAT Gateway forwards to Network Firewall endpoint (via NAT subnet route table)
4. Network Firewall inspects traffic against policies
5. If allowed, traffic forwarded to Internet Gateway
6. Internet Gateway routes to internet

### Inbound Traffic (Internet → Customer)
1. Return traffic arrives at Internet Gateway
2. IGW route table directs traffic for NAT subnet through firewall endpoint
3. Network Firewall inspects inbound traffic
4. Traffic forwarded to NAT Gateway
5. NAT Gateway performs reverse NAT
6. Traffic reaches destination EC2 instance

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- SSH key pair in the target AWS region (optional, for SSH access)

## Quick Start

1. **Clone/navigate to the project directory**:
   ```bash
   cd /path/to/tf-vpc-ingress-nfw
   ```

2. **Review and customize variables**:
   ```bash
   # Edit terraform.tfvars with your values
   vim terraform.tfvars
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Review the plan**:
   ```bash
   terraform plan
   ```

5. **Apply the configuration**:
   ```bash
   terraform apply
   ```

6. **View outputs**:
   ```bash
   terraform output
   ```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Name of the project | `network-firewall` |
| `environment` | Environment name (dev, staging, prod) | `dev` |
| `aws_region` | AWS region | `us-east-1` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `firewall_subnet_cidr` | Firewall subnet CIDR | `10.0.4.0/28` |
| `nat_subnet_cidr` | NAT gateway subnet CIDR | `10.0.2.0/24` |
| `customer_subnet_cidr` | Customer subnet CIDR | `10.0.3.0/24` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `key_name` | SSH key pair name | `""` |
| `enable_deletion_protection` | Enable firewall deletion protection | `false` |

## Route Tables

### IGW Route Table
| Destination | Target |
|-------------|--------|
| 10.0.2.0/24 | Firewall Endpoint |
| 10.0.3.0/24 | Firewall Endpoint |

### Firewall Subnet Route Table
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | Internet Gateway |

### NAT Subnet Route Table
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | Firewall Endpoint |

### Customer Subnet Route Table
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | NAT Gateway |

## Testing

### Accessing the Test Instance

Since the instance is in a private subnet, you have two options:

1. **AWS Systems Manager Session Manager** (recommended):
   ```bash
   aws ssm start-session --target <instance-id>
   ```

2. **SSH via Bastion** (if configured):
   ```bash
   ssh -i your-key.pem ec2-user@<private-ip>
   ```

### Outbound Connectivity Test

Once connected to the instance:
```bash
# Run the built-in test script
sudo /home/ec2-user/test-outbound.sh

# Or test manually
curl -I https://www.amazon.com
ping -c 4 8.8.8.8
nslookup google.com
```

### Verify Traffic Through Firewall

1. Check CloudWatch Logs for firewall flow logs
2. Monitor firewall metrics in CloudWatch
3. View VPC Flow Logs for traffic patterns

## Firewall Policy

The deployed firewall policy includes:

**Allowed Traffic (PASS)**:
- HTTPS outbound (port 443)
- HTTP outbound (port 80)
- DNS queries (port 53 UDP/TCP)
- ICMP (ping)

**Blocked Traffic (DROP)**:
- All other traffic

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Note**: If deletion protection is enabled, you must first disable it or set `enable_deletion_protection = false` before destroying.

## Cost Considerations

- **Network Firewall**: Hourly charges + data processing
- **NAT Gateway**: Hourly charges + data processing
- **EC2 Instance**: Hourly/On-demand charges
- **Elastic IP**: Free while attached to running NAT Gateway
- **CloudWatch Logs**: Storage and ingestion costs

## Security Considerations

1. **Private Subnet**: Customer instances have no direct internet access
2. **NAT Gateway**: Provides outbound-only internet access
3. **Network Firewall**: Inspects all traffic entering/leaving the VPC
4. **Security Groups**: Restrict inbound/outbound at instance level
5. **IMDSv2**: Enforced on EC2 instances for metadata security
6. **Encrypted EBS**: Root volumes are encrypted by default

## Architecture Limitations

- **Single AZ**: Not highly available - consider multi-AZ for production
- **No Inbound Web Access**: Customer subnet is private - requires ALB or similar for public web traffic
- **Firewall Capacity**: Rule group capacity limits apply

## Files

```
.
├── main.tf           # Main infrastructure resources
├── variables.tf      # Variable definitions
├── terraform.tfvars  # Variable values
├── locals.tf         # Local values and tags
├── data.tf           # Data sources
├── outputs.tf        # Output values
├── user-data.sh      # EC2 user data script
└── README.md         # This file
```

## Author

Generated by Antigravity AI

## License

MIT License
