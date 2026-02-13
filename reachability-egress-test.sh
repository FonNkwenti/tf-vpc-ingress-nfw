#!/bin/bash
# reachability-egress-test.sh
#
# Tests egress path from the EC2 webserver to an external IP (8.8.8.8)
# using AWS Reachability Analyzer. Simulates outbound HTTPS traffic (port 443).
#
# The analyzer traces through the VPC route tables and models the full path:
#   EC2 ENI → NFW endpoint → Firewall subnet → IGW → 8.8.8.8
#
# Usage:
#   ./reachability-egress-test.sh [--region us-east-1] [--output-file results.json]
#
# Options:
#   --region       AWS region (default: us-east-1)
#   --output-file  JSON file to write the analysis result (default: nia-egress-result.json)
#   --port         Destination port to test (default: 443)
#   --dest-ip      Destination IP to test reachability to (default: 8.8.8.8)
#
# Requirements:
#   - AWS CLI v2 configured with sufficient IAM permissions
#   - Terraform state must exist (terraform output used to resolve resource IDs)
#   - jq installed

set -euo pipefail

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------
REGION="us-east-1"
OUTPUT_FILE="nia-egress-result.json"
PROTOCOL="tcp"
PORT="443"
DEST_IP="8.8.8.8"
ANALYSIS_TIMEOUT=120  # seconds to wait for analysis completion
POLL_INTERVAL=5       # seconds between status polls

#------------------------------------------------------------------------------
# Parse arguments
#------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)      REGION="$2";      shift 2 ;;
    --output-file) OUTPUT_FILE="$2"; shift 2 ;;
    --port)        PORT="$2";        shift 2 ;;
    --dest-ip)     DEST_IP="$2";     shift 2 ;;
    --help)
      grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }

check_deps() {
  for cmd in aws jq terraform; do
    command -v "$cmd" &>/dev/null || fail "'$cmd' is required but not found in PATH"
  done
}

#------------------------------------------------------------------------------
# Resolve resource IDs from Terraform outputs
#------------------------------------------------------------------------------
resolve_resources() {
  log "Resolving resource IDs from Terraform state..."

  TF_OUTPUT=$(terraform output -json 2>/dev/null) \
    || fail "Could not read Terraform outputs. Ensure 'terraform apply' has been run."

  INSTANCE_ID=$(echo "$TF_OUTPUT" | jq -r '.webserver_instance_id.value // empty')

  [[ -n "$INSTANCE_ID" ]] || fail "Could not resolve webserver_instance_id from Terraform output"

  log "  Instance ID : $INSTANCE_ID"
}

#------------------------------------------------------------------------------
# Resolve the primary ENI and VPC ID from the EC2 instance
#------------------------------------------------------------------------------
resolve_eni() {
  log "Resolving primary network interface (ENI) for $INSTANCE_ID..."

  INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].{ENI:NetworkInterfaces[0].NetworkInterfaceId,VPC:VpcId}" \
    --output json) || fail "Could not describe instance $INSTANCE_ID"

  ENI_ID=$(echo "$INSTANCE_INFO" | jq -r '.ENI // empty')
  VPC_ID=$(echo "$INSTANCE_INFO" | jq -r '.VPC // empty')

  [[ -n "$ENI_ID" && "$ENI_ID" != "null" ]] || fail "No ENI found for instance $INSTANCE_ID"
  [[ -n "$VPC_ID" && "$VPC_ID" != "null" ]] || fail "No VPC ID found for instance $INSTANCE_ID"

  log "  ENI ID      : $ENI_ID"
  log "  VPC ID      : $VPC_ID"
}

#------------------------------------------------------------------------------
# Resolve the Internet Gateway for the VPC
#------------------------------------------------------------------------------
resolve_igw() {
  log "Resolving Internet Gateway for VPC $VPC_ID..."

  IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --region "$REGION" \
    --query "InternetGateways[0].InternetGatewayId" \
    --output text) || fail "Could not describe internet gateways"

  [[ -n "$IGW_ID" && "$IGW_ID" != "None" ]] || fail "No IGW found for VPC $VPC_ID"

  log "  IGW ID      : $IGW_ID"
}

#------------------------------------------------------------------------------
# Create a Network Insights Path
# Source      : EC2 ENI
# Destination : IGW (last AWS resource in the egress path)
# Dest IP     : external IP (8.8.8.8 or user-supplied)
#------------------------------------------------------------------------------
create_path() {
  log "Creating Network Insights Path..."
  log "  Source         : ENI $ENI_ID (webserver)"
  log "  Destination    : IGW $IGW_ID"
  log "  Destination IP : $DEST_IP"
  log "  Protocol/Port  : $PROTOCOL/$PORT"

  NIP_ID=$(aws ec2 create-network-insights-path \
    --source "$ENI_ID" \
    --destination "$IGW_ID" \
    --destination-ip "$DEST_IP" \
    --protocol "$PROTOCOL" \
    --destination-port "$PORT" \
    --region "$REGION" \
    --tag-specifications \
      "ResourceType=network-insights-path,Tags=[{Key=Name,Value=egress-test-ec2-to-${DEST_IP//\./-}},{Key=ManagedBy,Value=reachability-egress-test.sh}]" \
    --query "NetworkInsightsPath.NetworkInsightsPathId" \
    --output text) || fail "Failed to create Network Insights Path"

  log "  NIP ID      : $NIP_ID"
}

#------------------------------------------------------------------------------
# Start a Network Insights Analysis
#------------------------------------------------------------------------------
start_analysis() {
  log "Starting Network Insights Analysis..."

  NIA_ID=$(aws ec2 start-network-insights-analysis \
    --network-insights-path-id "$NIP_ID" \
    --region "$REGION" \
    --tag-specifications \
      "ResourceType=network-insights-analysis,Tags=[{Key=Name,Value=egress-test-analysis},{Key=ManagedBy,Value=reachability-egress-test.sh}]" \
    --query "NetworkInsightsAnalysis.NetworkInsightsAnalysisId" \
    --output text) || fail "Failed to start Network Insights Analysis"

  echo ""
  echo "================================================"
  echo "  NIA_ID=${NIA_ID}"
  echo "================================================"
  echo ""
  log "  NIA ID      : $NIA_ID"
}

#------------------------------------------------------------------------------
# Poll until analysis completes
#------------------------------------------------------------------------------
wait_for_analysis() {
  log "Waiting for analysis to complete (timeout: ${ANALYSIS_TIMEOUT}s)..."

  local elapsed=0
  while [[ $elapsed -lt $ANALYSIS_TIMEOUT ]]; do
    STATUS=$(aws ec2 describe-network-insights-analyses \
      --network-insights-analysis-ids "$NIA_ID" \
      --region "$REGION" \
      --query "NetworkInsightsAnalyses[0].Status" \
      --output text)

    log "  Status: $STATUS (${elapsed}s elapsed)"

    if [[ "$STATUS" == "succeeded" ]]; then
      return 0
    elif [[ "$STATUS" == "failed" ]]; then
      fail "Analysis $NIA_ID failed. Run: aws ec2 describe-network-insights-analyses --network-insights-analysis-ids $NIA_ID --region $REGION"
    fi

    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done

  fail "Analysis did not complete within ${ANALYSIS_TIMEOUT}s. NIA_ID: $NIA_ID"
}

#------------------------------------------------------------------------------
# Download full analysis result to JSON
#------------------------------------------------------------------------------
download_result() {
  log "Downloading analysis result to $OUTPUT_FILE..."

  aws ec2 describe-network-insights-analyses \
    --network-insights-analysis-ids "$NIA_ID" \
    --region "$REGION" \
    --output json > "$OUTPUT_FILE" \
    || fail "Failed to download analysis result"

  log "  Saved to: $OUTPUT_FILE"
}

#------------------------------------------------------------------------------
# Print summary
#------------------------------------------------------------------------------
print_summary() {
  local network_path_found
  network_path_found=$(jq -r '.NetworkInsightsAnalyses[0].NetworkPathFound' "$OUTPUT_FILE")

  echo ""
  echo "============================================================"
  echo "  EGRESS REACHABILITY TEST SUMMARY"
  echo "============================================================"
  echo "  NIA_ID            : $NIA_ID"
  echo "  NIP_ID            : $NIP_ID"
  echo "  Source            : $ENI_ID (webserver EC2 ENI)"
  echo "  Destination IP    : $DEST_IP"
  echo "  Protocol/Port     : $PROTOCOL/$PORT"
  echo "  Network Path Found: $network_path_found"
  echo "  Result file       : $OUTPUT_FILE"
  echo "============================================================"
  echo ""

  if [[ "$network_path_found" == "true" ]]; then
    echo "  RESULT: REACHABLE"
    echo "  EC2 → NFW endpoint → IGW → $DEST_IP:$PORT is valid."
  else
    echo "  RESULT: NOT REACHABLE"
    echo "  Explanations:"
    jq -r '.NetworkInsightsAnalyses[0].Explanations[]? |
      "  - [\(.ExplanationCode)] \(.Component.ResourceType // "") \(.Component.Id // "") \(.Direction // "")"' \
      "$OUTPUT_FILE" 2>/dev/null || echo "  (no explanation details found)"
  fi

  echo ""
  echo "  To re-download the result at any time:"
  echo "    aws ec2 describe-network-insights-analyses \\"
  echo "      --network-insights-analysis-ids $NIA_ID \\"
  echo "      --region $REGION --output json > $OUTPUT_FILE"
  echo ""
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
  check_deps
  resolve_resources
  resolve_eni
  resolve_igw
  create_path
  start_analysis
  wait_for_analysis
  download_result
  print_summary
}

main "$@"
