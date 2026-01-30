#!/bin/bash
# User data script for Network Firewall test instance
# Sets up Apache web server and network testing utilities

set -e

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
        .warning { color: #ffc107; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        td, th { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #007bff; color: white; }
        .traffic-path { background-color: #e9ecef; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .traffic-path h4 { margin-top: 0; color: #495057; }
        code { background-color: #f8f9fa; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✓ Connection Successful!</h1>
        <h2>AWS Network Firewall - Traffic Test Page</h2>
        <p class="info">If you can see this page, inbound traffic is flowing correctly through the Network Firewall.</p>
        
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Instance ID</td><td>$INSTANCE_ID</td></tr>
            <tr><td>Private IP</td><td>$PRIVATE_IP</td></tr>
            <tr><td>Public IP</td><td>$PUBLIC_IP</td></tr>
            <tr><td>Availability Zone</td><td>$AZ</td></tr>
            <tr><td>Subnet</td><td>Customer Subnet (10.0.3.0/24)</td></tr>
        </table>

        <div class="traffic-path">
            <h4>📥 Inbound Traffic Path:</h4>
            <p>Internet → IGW → <strong>Network Firewall</strong> → NAT Subnet → Customer Subnet</p>
        </div>

        <div class="traffic-path">
            <h4>📤 Outbound Traffic Path:</h4>
            <p>Customer Subnet → <strong>NAT Gateway</strong> → <strong>Network Firewall</strong> → IGW → Internet</p>
        </div>
        
        <h3>Test Timestamp</h3>
        <p id="timestamp"></p>
        
        <h3>Quick Links</h3>
        <ul>
            <li><a href="/status.json">Health Check Endpoint</a></li>
            <li><a href="/test-results.txt">Test Results Log</a></li>
            <li><a href="/outbound-test-results.txt">Outbound Test Results</a></li>
        </ul>
        
        <script>
            document.getElementById('timestamp').innerHTML = new Date().toLocaleString();
        </script>
    </div>
</body>
</html>
EOF

# Create test log file
cat > /var/www/html/test-results.txt <<EOF
Network Firewall Architecture Test Instance
============================================
Instance ID: $INSTANCE_ID
Private IP: $PRIVATE_IP
Public IP: $PUBLIC_IP
Availability Zone: $AZ
Deployment Time: $(date)

Architecture: Single-Zone Network Firewall with NAT Gateway
Subnet: Customer Subnet (10.0.3.0/24)

Test Commands:
--------------
# Test outbound HTTPS
curl -I https://www.amazon.com

# Test outbound HTTP  
curl -I http://www.example.com

# Test DNS resolution
nslookup google.com

# Trace route to internet
traceroute -m 10 8.8.8.8
EOF

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Configure firewall (if firewalld is running)
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
fi

# Create outbound connectivity test script
cat > /home/ec2-user/test-outbound.sh <<'SCRIPT'
#!/bin/bash
echo "=========================================="
echo "Outbound Connectivity Tests"
echo "=========================================="
echo ""

echo "1. Testing HTTPS connectivity..."
curl -s -o /dev/null -w "Status: %{http_code}\n" https://www.amazon.com --max-time 10
echo ""

echo "2. Testing HTTP connectivity..."
curl -s -o /dev/null -w "Status: %{http_code}\n" http://www.example.com --max-time 10
echo ""

echo "3. Testing DNS resolution..."
nslookup google.com
echo ""

echo "4. Testing ICMP (ping)..."
ping -c 4 8.8.8.8
echo ""

echo "5. Checking public IP (should show NAT gateway IP)..."
curl -s ifconfig.me --max-time 10
echo ""
echo ""

echo "6. Testing specific ports..."
nc -zv -w 5 www.google.com 443 2>&1 | grep -E "succeeded|open|Connected"
nc -zv -w 5 www.google.com 80 2>&1 | grep -E "succeeded|open|Connected"
echo ""

echo "Tests completed at: $(date)"
SCRIPT

chmod +x /home/ec2-user/test-outbound.sh
chown ec2-user:ec2-user /home/ec2-user/test-outbound.sh

# Run initial outbound test and save results (with timeout)
timeout 120 /home/ec2-user/test-outbound.sh > /var/www/html/outbound-test-results.txt 2>&1 || echo "Some tests timed out" >> /var/www/html/outbound-test-results.txt

# Create a status check endpoint
cat > /var/www/html/status.json <<EOF
{
  "status": "healthy",
  "instance_id": "$INSTANCE_ID",
  "private_ip": "$PRIVATE_IP",
  "public_ip": "$PUBLIC_IP",
  "availability_zone": "$AZ",
  "subnet": "customer-subnet",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Setup completed successfully at $(date)" > /var/log/userdata.log
