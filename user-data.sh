#!/bin/bash
# User data script for VPC Ingress Routing Demo - Web Server
# Apache setup works WITHOUT internet (local repo)
# Network-dependent tasks run after connectivity is available

exec > >(tee /var/log/user-data.log) 2>&1
set -x

echo "=== Starting user-data script at $(date) ==="
echo "Note: Internet access will not be available until firewall is ready"
echo "Purpose: Demonstrate VPC Ingress Routing with inline traffic inspection"

# Get instance metadata (this works without internet - local link)
echo "=== Getting instance metadata ==="
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "unknown")
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")

echo "Instance metadata: ID=$INSTANCE_ID, PrivateIP=$PRIVATE_IP, PublicIP=$PUBLIC_IP, AZ=$AZ"

# Install Apache from local repo (doesn't require internet)
echo "=== Installing Apache web server (from local repo) ==="
if yum install -y httpd; then
    echo "SUCCESS: Apache installed"
else
    echo "ERROR: Failed to install httpd from local repo"
    exit 1
fi

# Create the custom web page immediately
echo "=== Creating web content ==="
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>VPC Ingress Routing Demo - Web Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f0f0; }
        .container { background-color: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); max-width: 800px; margin: 0 auto; }
        .success { color: #28a745; font-weight: bold; }
        .info { color: #007bff; }
        .highlight { background-color: #fff3cd; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #ffc107; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        td, th { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #007bff; color: white; }
        .traffic-path { background-color: #e9ecef; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .traffic-path h4 { margin-top: 0; color: #495057; }
        code { background-color: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✓ VPC Ingress Routing Demo</h1>
        <h2>Web Server with Inline Traffic Inspection</h2>
        <p class="info">If you can see this page, traffic is flowing through the Network Firewall!</p>

        <div class="highlight">
            <strong>Demo Purpose:</strong> This architecture demonstrates <strong>VPC Ingress Routing</strong>, 
            where all traffic (inbound and outbound) is routed through an inline inspection point 
            (Network Firewall) instead of going directly to/from the destination.
        </div>
        
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Instance ID</td><td>$INSTANCE_ID</td></tr>
            <tr><td>Private IP</td><td>$PRIVATE_IP</td></tr>
            <tr><td>Public IP (EIP)</td><td>$PUBLIC_IP</td></tr>
            <tr><td>Availability Zone</td><td>$AZ</td></tr>
            <tr><td>Subnet</td><td>WebServer Subnet</td></tr>
        </table>

        <div class="traffic-path">
            <h4>📥 Inbound Traffic Path (VPC Ingress Routing):</h4>
            <p>Internet → IGW → <strong>Network Firewall (INSPECTION)</strong> → WebServer Subnet → EC2</p>
            <p><em>Note: Traffic does NOT go directly from IGW to the web server!</em></p>
        </div>

        <div class="traffic-path">
            <h4>📤 Outbound Traffic Path (Egress Inspection):</h4>
            <p>EC2 → WebServer Subnet → <strong>Network Firewall (INSPECTION)</strong> → IGW → Internet</p>
        </div>

        <div class="highlight">
            <h4>🔍 How to Verify the Demo:</h4>
            <ol>
                <li>Access this page via the public IP - it works because the firewall allows HTTP traffic</li>
                <li>Check CloudWatch Logs to see traffic flowing through the firewall</li>
                <li>The Network Firewall is not the highlight - it's merely demonstrating VPC Ingress Routing!</li>
            </ol>
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
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "demo": "VPC Ingress Routing with Network Firewall"
}
EOF

# Set permissions
chmod 644 /var/www/html/index.html /var/www/html/status.json
chown apache:apache /var/www/html/index.html /var/www/html/status.json 2>/dev/null || chown www-data:www-data /var/www/html/index.html /var/www/html/status.json 2>/dev/null || true

echo "Created web content files"

# Start Apache immediately (this is the critical part!)
echo "=== Starting Apache web server ==="
systemctl start httpd || service httpd start
if systemctl is-active httpd > /dev/null 2>&1 || service httpd status > /dev/null 2>&1; then
    echo "SUCCESS: Apache is running"
else
    echo "ERROR: Apache failed to start"
    exit 1
fi

# Enable Apache to start on boot
systemctl enable httpd 2>/dev/null || chkconfig httpd on 2>/dev/null || true

# Verify Apache is serving content
echo "=== Verifying Apache is serving content ==="
sleep 1
if curl -s http://localhost | grep -q "VPC Ingress Routing"; then
    echo "SUCCESS: Custom web page is being served"
else
    echo "WARNING: Custom web page not detected, checking default page..."
    curl -s http://localhost | head -5
fi

# Background process: Wait for internet, then install extra packages and update
echo "=== Starting background process for network-dependent tasks ==="
(
    echo "[Background] Waiting for internet connectivity..."
    for i in {1..60}; do
        if curl -s --connect-timeout 5 https://aws.amazon.com > /dev/null 2>&1; then
            echo "[Background] Internet connectivity established after $i attempts"
            
            echo "[Background] Updating system packages..."
            yum update -y 2>/dev/null || echo "[Background] yum update failed"
            
            echo "[Background] Installing network utilities..."
            yum install -y telnet nc traceroute tcpdump bind-utils wget 2>/dev/null || echo "[Background] Some utilities failed to install"
            
            echo "[Background] Network setup complete at $(date)"
            break
        fi
        sleep 10
    done
    echo "[Background] Process ended at $(date)"
) &

echo "=== Main setup completed successfully at $(date) ==="
echo "Apache web server is running and serving content"
echo "Background process continuing to wait for internet..."
echo ""
echo "To connect to this instance, use EC2 Instance Connect:"
echo "  aws ec2-instance-connect ssh --instance-id $INSTANCE_ID --region $AZ"
echo ""
echo "Check /var/log/user-data.log for full details"
