---
name: analyze-reachability
description: Run AWS VPC Reachability Analyzer tests against Terraform infrastructure, download the Network Insights report, and produce a hop-by-hop traffic flow analysis document. Use when the user wants to test connectivity, validate network paths, analyze traffic flows through Transit Gateway hubs, or generate a traffic flow analysis for a centralized egress (or similar multi-VPC) architecture. Also use when the user asks to "create analysis of internet egress" -- in that case first create scripts/analyze-internet-egress.sh (see Phase 0) then run the full analysis workflow using that script.
disable-model-invocation: true
---

# VPC Reachability Analysis Workflow

Analyze network connectivity in a multi-VPC Terraform architecture using AWS VPC Reachability Analyzer, then interpret the results into a detailed traffic flow analysis document.

## Prerequisites

Before running this skill, verify:

1. **Terraform has been applied** -- infrastructure must exist in AWS
2. **AWS CLI is configured** with credentials that have `ec2:CreateNetworkInsightsPath`, `ec2:StartNetworkInsightsAnalysis`, `ec2:DescribeNetworkInsightsAnalyses`, and `ec2:DeleteNetworkInsightsPath` permissions
3. **Terraform outputs exist** for instance IDs and gateway IDs used by the analysis script
4. An `analyze-reachability.sh` script (or equivalent) exists under `scripts/`

> **Cost note:** AWS charges approximately $0.10 per Reachability Analyzer analysis run.

## Workflow

### Phase 0: Create the Internet Egress Script (trigger: "create analysis of internet egress")

> **Only run this phase** when the user's prompt is about creating an internet egress analysis (e.g., "create analysis of internet egress"). Skip to Phase 1 for all other invocations.

If `scripts/analyze-internet-egress.sh` does not already exist, create it now. The script must:

1. Read `vpc_a_instance_id` and `internet_gateway_id` from `terraform output`
2. Define an `analyze_egress <protocol> <port> <label>` function that:
   - Creates a Network Insights Path: source = instance, destination = IGW, destination-ip = `${EGRESS_DEST_IP:-8.8.8.8}`, using `--tag-specifications` to name each path
   - Starts a Network Insights Analysis on that path
   - Waits for the analysis to complete (`aws ec2 wait network-insights-analysis-complete`)
   - Prints `PASS` or `FAIL` based on `NetworkPathFound`; on failure prints each `ExplanationCode`
   - Appends the path ID to `/tmp/egress_paths_$$` and the analysis ID to `/tmp/egress_analyses_$$`
3. Register a `trap cleanup EXIT` that deletes all created paths and removes the temp files
4. Run three tests, all expected to PASS:
   - TCP:53  (DNS over TCP)  →  `$DEST_IP`
   - TCP:80  (HTTP)          →  `$DEST_IP`
   - TCP:443 (HTTPS)         →  `$DEST_IP`
5. Print the last analysis ID and the `aws ec2 describe-network-insights-analyses` command to inspect it

Write the script to `scripts/analyze-internet-egress.sh` and make it executable (`chmod +x`).

After creating the script, continue with Phase 1 using `scripts/analyze-internet-egress.sh` as the script under test.

---

### Phase 1: Verify Infrastructure and Script

1. Confirm Terraform state is up to date:
   ```bash
   terraform output
   ```
2. Determine which script to use:
   - Internet egress analysis (came from Phase 0): use `scripts/analyze-internet-egress.sh`
   - General reachability analysis: use `scripts/analyze-reachability.sh`
   Read the chosen script to understand which paths it tests.
3. Identify the test cases and their expected outcomes (PASS/FAIL).

### Phase 2: Run the Reachability Analysis

Execute the appropriate script and capture all output:

```bash
# Internet egress analysis:
bash scripts/analyze-internet-egress.sh

# General reachability analysis:
bash scripts/analyze-reachability.sh
```

Record:
- Each test name, source, destination, protocol, and port
- The Network Insights Path IDs and Analysis IDs created
- The result for each test: REACHABLE or NOT REACHABLE
- Any `ExplanationCode` values for failed paths

After the script completes, note the exported `NIA_ID` (last analysis ID).

### Phase 3: Download the Full Report

Download the detailed Network Insights report for every analysis that was run. If the script stored analysis IDs in a temp file, retrieve them. Otherwise, use the IDs captured from script output.

For each analysis ID:

```bash
aws ec2 describe-network-insights-analyses \
    --network-insights-analysis-ids <ANALYSIS_ID> \
    --region <REGION> \
    --output json
```

Combine all analysis results into a single `network-insights-report.json` file at the project root.

### Phase 4: Interpret the Report and Write the Traffic Flow Analysis

Read `network-insights-report.json` and the Terraform source files (`main.tf`, `locals.tf`, `variables.tf`, `outputs.tf`) to produce a `traffic-flow-analysis.md` document with the following structure:

#### 4.1 -- Report Summary Table

List every analysis performed:

| Analysis ID | Path | Protocol | Result | Purpose |
|---|---|---|---|---|
| `nia-...` | Source &rarr; Destination | TCP:port | Reachable / Not Reachable | What this test validates |

Include a note about any known Reachability Analyzer limitations encountered (e.g., Regional NAT Gateway modeling, `AlternatePathHints`).

#### 4.2 -- Architecture Diagram

Create an ASCII diagram showing:
- All VPCs with their CIDR ranges and resource IDs
- Subnet layout (public, private, TGW attachment) with route table associations
- Transit Gateway with its route tables, routes, and blackhole entries
- Internet Gateway and NAT Gateway placement
- Test instance locations and IPs

#### 4.3 -- Hop-by-Hop Path Analysis

For each analyzed path, walk through every hop in the `ForwardPathComponents` and `ReturnPathComponents` arrays from the report. For each hop, document:

**Hop N -- Component Name (Sequence N)**

- **Component:** Resource name and ID
- **Location:** Subnet, VPC, and AZ where applicable
- **What happens:** Plain-language explanation of what occurs at this hop (routing decision, NAT translation, security evaluation, etc.)
- **Packet state:** Show source and destination IP:port at this point in the path
- **Intention:** Explain the architectural design reason this component exists and what it enforces (isolation, egress control, defense-in-depth, etc.)
- **Terraform:** Include the relevant Terraform resource block from the project source

The hop types to cover include:
- **Instance / ENI** -- source or destination endpoint
- **Security Group** -- egress or ingress rule evaluation, show the matched rule
- **Network ACL** -- stateless rule evaluation, show the matched rule number
- **Route Table** -- which route matched (longest-prefix), what the next hop is
- **Transit Gateway** -- ingress/egress, which TGW route table was consulted, blackhole enforcement
- **NAT Gateway** -- source NAT translation, connection tracking
- **Internet Gateway** -- final hop to public internet

#### 4.4 -- VPC Isolation Analysis

For paths that are NOT reachable (e.g., VPC-to-VPC), explain:
- Exactly which component blocked the traffic (typically a TGW blackhole route)
- The CIDR match that triggered the block
- Why this isolation is intentional in the architecture

#### 4.5 -- Return Path

For reachable paths, document the return path hops showing:
- How the response enters via IGW
- NAT Gateway reverse translation using connection tracking
- TGW routing back to the correct spoke VPC
- Stateful security group allowing the return traffic

### Phase 5: Review and Validate

After generating the document:
1. Cross-check every resource ID in the analysis against `terraform output` and `main.tf`
2. Verify route table lookups match the actual routes defined in Terraform
3. Confirm that "expected FAIL" tests actually failed and "expected PASS" tests actually passed
4. Flag any discrepancies between the Reachability Analyzer results and actual connectivity (test with `curl` or `ping` from the instance if needed)

## Output

The workflow produces three artifacts:
1. **Console output** from the reachability script (test results summary)
2. **`network-insights-report.json`** -- raw AWS API response at the project root
3. **`traffic-flow-analysis.md`** -- the interpreted, hop-by-hop analysis document at the project root

## Adapting to Other Projects

When using this workflow in a new project:

1. **Prompt "create analysis of internet egress"** to have the skill auto-generate `scripts/analyze-internet-egress.sh` and run the full internet egress analysis workflow. The script tests TCP:53, TCP:80, and TCP:443 from the spoke instance to `8.8.8.8` (configurable via `EGRESS_DEST_IP`). This is the recommended starting point for any centralized egress architecture.

2. **Or create `scripts/analyze-reachability.sh`** manually for general multi-path tests:
   - Update the Terraform output names for instance IDs and gateway IDs
   - Define test cases appropriate to the topology (e.g., spoke-to-spoke, spoke-to-shared-services, spoke-to-internet)
   - Set expected outcomes per test (which should pass, which should fail)

3. **Adjust the Terraform outputs** to expose the resource IDs the scripts need (`instance_id`, `internet_gateway_id`, etc.)

4. **Run this skill** -- the analysis and interpretation phases remain the same regardless of the specific hub-and-spoke topology
