# VPC Ingress Routing with AWS Network Firewall

Single Availability Zone architecture demonstrating VPC Ingress Routing with inline traffic inspection via AWS Network Firewall. All traffic between the internet and the web server passes through the firewall endpoint in both directions.

## Architecture

```
                          ┌──────────────────────────────────────────────────┐
                          │                  VPC: 10.0.0.0/16                │
                          │                                                  │
  ┌──────────────┐        │  ┌────────────────────────────────────────────┐  │
  │   Internet   │        │  │         Firewall Subnet (10.0.4.0/28)      │  │
  │   Gateway    │◄───────┼──│   Network Firewall Endpoint (vpce-xxxx)    │  │
  └──────┬───────┘        │  └────────────────────────────────────────────┘  │
         │                │                        │                         │
         │ IGW RT:         │                        ▼                         │
         │ 10.0.2.0/24    │  ┌────────────────────────────────────────────┐  │
         │ → NFW endpoint  │  │        WebServer Subnet (10.0.2.0/24)      │  │
         │                │  │   EC2 Web Server (Graviton, Elastic IP)    │  │
         └────────────────┼──│   WebServer RT: 0.0.0.0/0 → NFW endpoint  │  │
                          │  └────────────────────────────────────────────┘  │
                          └──────────────────────────────────────────────────┘
```

## Traffic Flow

**Inbound**: Internet → IGW → (IGW RT intercepts webserver CIDR) → NFW endpoint → EC2

**Outbound**: EC2 → (WebServer RT) → NFW endpoint → (Firewall RT) → IGW → Internet

## Route Tables

| Route Table | Destination | Target |
|---|---|---|
| IGW RT | 10.0.2.0/24 | NFW endpoint |
| Firewall RT | 0.0.0.0/0 | IGW |
| WebServer RT | 0.0.0.0/0 | NFW endpoint |

## Firewall Policy (STRICT_ORDER)

| Priority | Action | Protocol | Port |
|---|---|---|---|
| 1 | PASS | TCP | 443 |
| 1 | PASS | TCP | 80 |
| 1 | PASS | UDP | 53 |
| 1 | PASS | TCP | 53 |
| 1 | PASS | ICMP | ANY |
| 100 | DROP | IP | ANY |

## Quick Start

```bash
terraform init
terraform plan
terraform apply
```

After deploy:

```bash
# Access the web server
curl http://$(terraform output -raw webserver_public_ip)

# Connect via EC2 Instance Connect (no SSH key required)
$(terraform output -raw ec2_instance_connect_command)
```

## Variables

| Variable | Description | Default |
|---|---|---|
| `project_name` | Project name | `vpc-ingress-nfw` |
| `environment` | Environment (dev/staging/prod) | `dev` |
| `aws_region` | AWS region | `us-east-1` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `firewall_subnet_cidr` | Firewall subnet CIDR | `10.0.4.0/28` |
| `webserver_subnet_cidr` | WebServer subnet CIDR | `10.0.2.0/24` |
| `instance_type` | EC2 instance type (ARM/Graviton) | `t4g.micro` |
| `enable_deletion_protection` | NFW deletion protection | `false` |
| `firewall_policy_name` | Network Firewall policy name | `network-firewall-policy` |
| `enable_firewall_logs` | Enable NFW flow logs to CloudWatch | `true` |
| `enable_alert_logs` | Enable NFW alert logs to CloudWatch | `true` |
| `log_retention_days` | CloudWatch log retention (days) | `30` |
| `enable_monitoring_dashboard` | Enable CloudWatch dashboard and alarms | `true` |
| `alarm_sns_topic_arn` | SNS topic ARN for CloudWatch alarms | `""` |

## Outputs

| Output | Description |
|---|---|
| `webserver_instance_id` | EC2 instance ID |
| `webserver_public_ip` | Elastic IP address |
| `webserver_private_ip` | Private IP address |
| `web_url` | HTTP URL to access the web server |
| `ec2_instance_connect_command` | AWS CLI command to connect via EC2 Instance Connect |

## Monitoring

When `enable_monitoring_dashboard = true`, the following are deployed:

- **CloudWatch Dashboard** — packets processed/dropped (stateless + stateful), connections
- **Alarm**: stateless packets dropped > 100 in 5 min
- **Alarm**: stateful packets dropped > 50 in 5 min

Firewall logs ship to CloudWatch Log Groups:
- `/aws/networkfirewall/<project>/flow`
- `/aws/networkfirewall/<project>/alert`

## Reachability Testing

Two scripts use AWS Network Insights to verify both egress and ingress paths:

### Egress Test
`reachability-egress-test.sh` verifies: **EC2 ENI → NFW endpoint → IGW → 8.8.8.8:443**

```bash
./reachability-egress-test.sh

# Options
./reachability-egress-test.sh --region eu-west-1 --dest-ip 1.1.1.1 --port 443 --output-file result.json
```

Output: `nia-egress-result.json`

### Ingress Test
`reachability-ingress-test.sh` verifies: **IGW → NFW endpoint → EC2 ENI (port 80)**

```bash
./reachability-ingress-test.sh

# Options
./reachability-ingress-test.sh --region eu-west-1 --port 443 --output-file result.json
```

Output: `nia-ingress-result.json`

Both scripts auto-resolve the EC2 ENI and IGW from the instance ID, start a Network Insights Analysis, poll for completion, and save the full result to JSON for review.

> **Note**: Reachability Analyzer validates routing and security group rules only. NFW stateful rule evaluation requires live traffic testing via `curl` and CloudWatch NFW logs.

## Files

```
.
├── main.tf                         # VPC, subnets, IGW, EIP, route tables, security group, EC2
├── network_firewall.tf             # NFW policy, rules, firewall, logging, dashboard, alarms
├── variables.tf                    # Variable definitions
├── locals.tf                       # Computed locals and resource tags
├── data.tf                         # AMI and availability zone data sources
├── outputs.tf                      # Terraform outputs
├── provider.tf                     # Terraform and AWS provider config
├── terraform.tfvars                # Variable values
├── user-data.sh                    # EC2 bootstrap: Apache web server setup
├── reachability-egress-test.sh     # Network Insights egress path test (EC2 → IGW)
├── reachability-ingress-test.sh    # Network Insights ingress path test (IGW → EC2)
└── README.md                       # This file
```

## Cleanup

```bash
terraform destroy
```
