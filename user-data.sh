#!/bin/bash
# User data script for Network Firewall test instance
# Sets up Apache web server and network testing utilities
# Includes retry logic to wait for network connectivity

set -e

# Function to wait for network connectivity
wait_for_network() {
    echo "Waiting for network connectivity..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --connect-timeout 5 https://aws.amazon.com > /dev/null 2>&1; then
            echo "Network connectivity established after $attempt attempts"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: No network connectivity, waiting 10 seconds..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: Network connectivity not available after $max_attempts attempts"
    return 1
}

# Wait for network before proceeding
wait_for_network

# Update system packages
yum update -y

# Install Apache web server
yum install -y httpd

# Install network utilities for testing
yum install -y telnet nc traceroute tcpdump bind-utils curl wget

# Create a simple test web page with instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null)

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>AWS Network Firewall Test Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f0f0; }
        .container { background-color: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); max-width: 800px; margin: 0 auto; }
        .success { color: #28a745; font-weight: bold; }
        .info { color: #007bff; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        td, th { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #007bff; color: white; }
        .traffic-path { background-color: #e9ecef; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .traffic-path h4 { margin-top: 0; color: #495057; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✓ Connection Successful!</h1>
        <h2>AWS Network Firewall - Traffic Test Page</h2>
        <p class="info">If you can see this page, traffic is flowing correctly through the Network Firewall.</p>
        
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Instance ID</td><td>$INSTANCE_ID</td></tr>
            <tr><td>Private IP</td><td>$PRIVATE_IP</td></tr>
            <tr><td>Public IP (EIP)</td><td>$PUBLIC_IP</td></tr>
            <tr><td>Availability Zone</td><td>$AZ</td></tr>
            <tr><td>Subnet</td><td>Customer Subnet (10.0.2.0/24)</td></tr>
        </table>

        <div class="traffic-path">
            <h4>📥 Inbound Traffic Path:</h4>
            <p>Internet → IGW → <strong>Network Firewall</strong> → Customer Subnet → EC2</p>
        </div>

        <div class="traffic-path">
            <h4>📤 Outbound Traffic Path:</h4>
            <p>EC2 → Customer Subnet → <strong>Network Firewall</strong> → IGW → Internet</p>
        </div>
        
        <h3>Test Timestamp</h3>
        <p id="timestamp"></p>
        
        <script>
            document.getElementById('timestamp').innerHTML = new Date().toLocaleString();
        </script>
    </div>
</body>
</html>
EOF

# Create status endpoint
cat > /var/www/html/status.json <<EOF
{
  "status": "healthy",
  "instance_id": "$INSTANCE_ID",
  "private_ip": "$PRIVATE_IP",
  "public_ip": "$PUBLIC_IP",
  "availability_zone": "$AZ",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create outbound connectivity test script
cat > /home/ec2-user/test-outbound.sh <<'SCRIPT'
#!/bin/bash
echo "=========================================="
echo "Outbound Connectivity Tests"
echo "=========================================="
echo ""
echo "1. Testing HTTPS (port 443)..."
curl -s -o /dev/null -w "Status: %{http_code}\n" https://www.amazon.com --max-time 10
echo ""
echo "2. Testing HTTP (port 80)..."
curl -s -o /dev/null -w "Status: %{http_code}\n" http://www.example.com --max-time 10
echo ""
echo "3. Testing DNS..."
nslookup google.com
echo ""
echo "4. Testing ICMP (ping)..."
ping -c 4 8.8.8.8
echo ""
echo "5. Public IP:"
curl -s ifconfig.me --max-time 10
echo ""
echo ""
echo "Tests completed at: $(date)"
SCRIPT

chmod +x /home/ec2-user/test-outbound.sh
chown ec2-user:ec2-user /home/ec2-user/test-outbound.sh

echo "Setup completed successfully at $(date)" > /var/log/userdata.log
