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
# CloudWatch Dashboard for Network Firewall Monitoring
#------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "nfw_monitoring" {
  count = var.enable_monitoring_dashboard ? 1 : 0

  dashboard_name = "${local.project_name}-nfw-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Packets Processed (Stateless)"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "PacketsProcessed", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Sum" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Packets Dropped (Stateless)"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "PacketsDropped", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Sum" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Stateful Packets Processed"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "StatefulPacketsProcessed", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Sum" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Stateful Packets Dropped"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "StatefulPacketsDropped", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Sum" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Connections Per Second"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "ConnectionCount", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Active Connections"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "ActiveConnections", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Dropped Connections"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/NetworkFirewall", "DroppedConnections", "FirewallName", aws_networkfirewall_firewall.main.name, { stat = "Sum" }]
          ]
          period = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 18
        width  = 24
        height = 2
        properties = {
          markdown = "## Network Firewall: ${aws_networkfirewall_firewall.main.name} | VPC: ${aws_vpc.main.id} | Region: ${data.aws_region.current.name}"
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CloudWatch Alarms for Network Firewall
#------------------------------------------------------------------------------

# Alarm for high packet drops (stateless)
resource "aws_cloudwatch_metric_alarm" "stateless_packets_dropped" {
  count = var.enable_monitoring_dashboard ? 1 : 0

  alarm_name          = "${local.project_name}-stateless-packets-dropped"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PacketsDropped"
  namespace           = "AWS/NetworkFirewall"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Alarm when stateless packet drops exceed 100 packets in 5 minutes"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    FirewallName = aws_networkfirewall_firewall.main.name
  }

  tags = local.common_tags
}


resource "aws_cloudwatch_metric_alarm" "stateful_packets_dropped" {
  count = var.enable_monitoring_dashboard ? 1 : 0

  alarm_name          = "${local.project_name}-stateful-packets-dropped"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatefulPacketsDropped"
  namespace           = "AWS/NetworkFirewall"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "Alarm when stateful packet drops exceed 50 packets in 5 minutes"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    FirewallName = aws_networkfirewall_firewall.main.name
  }

  tags = local.common_tags
}
