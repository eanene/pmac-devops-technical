# EC2 Snapshot Cleanup — Infrastructure & Lambda

Automatically deletes EC2 snapshots older than one year using a scheduled Lambda function deployed inside a private VPC subnet, with all infrastructure defined in Terraform.

---

## Project Structure
```
├── env
│   ├── dev                                 # dev environment
│   │   ├── dev.conf                        # backend config
│   │   ├── dev.tf                          # parent module
│   │   └── output.tf
│   └── prod
├── modules
│   └── snapshot_cleanup                    # Reusable child module
│       ├── iam.tf                          # IAM role + EC2 snapshot policy
│       ├── lambda.tf                       # Lambda, EventBridge rule, CloudWatch alarm
│       ├── output.tf
│       ├── templates
│       │   ├── snapshot_cleanup.py.        # Lambda function source code
│       │   └── snapshot_cleanup.zip
│       ├── variable.tf
│       └── vpc.tf                          # VPC, private subnet, security group, VPC endpoints

```

---

## IaC Tool — Terraform

Terraform was chosen because:

- **State management** — remote state (S3 + DynamoDB) supports team workflows and drift detection.
- **Module reusability** — the same child module can be instantiated for dev / staging / prod by changing a few variables in a new root `.tf` file (e.g. `dev.tf` or `prod.tf`).
- **Rich AWS provider** — mature coverage of every AWS resource used here.
- **Plan preview** — `terraform plan` shows exact changes before any resource is touched.
- **Familiarity** — aligns with existing organisational IaC standards.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x |
| Python | >= 3.12 (local testing only) |

AWS credentials must be configured with sufficient permissions to create VPCs, IAM roles, Lambda functions, and EventBridge rules.

```bash
aws configure         
aws sts get-caller-identity   
```

---

## How to Deploy

### 1 — Initialise Terraform

```bash
cd Terraform/env/dev
terraform init -backend-config=dev.conf
```
### 2 — Review the plan

```bash
terraform plan
```
Terraform will package `lambda/snapshot_cleanup.py` into a zip and show every resource it intends to create.

### 3 — Apply

```bash
terraform apply
```

Type `yes` when prompted. All resources are created in **us-east-1**.

### 4 — Tear down

```bash
terraform destroy
```

---

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_vpc` | `/16` VPC with DNS enabled |
| `aws_subnet` | Private `/24` subnet in `us-east-1a` |
| `aws_route_table` | Private route table (no default route) |
| `aws_security_group` | Allows outbound HTTPS (443) for VPC endpoint traffic |
| `aws_vpc_endpoint` (EC2) | Interface endpoint — Lambda → EC2 API, no NAT needed |
| `aws_vpc_endpoint` (Logs) | Interface endpoint — Lambda → CloudWatch Logs |
| `aws_iam_role` | Lambda execution role |
| `aws_iam_policy` | Custom policy: `ec2:DescribeSnapshots`, `ec2:DeleteSnapshot` |
| `aws_iam_role_policy_attachment` | Attaches VPC execution + custom EC2 policies |
| `aws_lambda_function` | Python 3.12, 300 s timeout, deployed inside the VPC |
| `aws_cloudwatch_log_group` | `/aws/lambda/snapshot-cleanup-dev-…`, 30-day retention |
| `aws_cloudwatch_event_rule` | EventBridge cron: daily at 02:00 UTC |
| `aws_cloudwatch_event_target` | Connects the rule to the Lambda |
| `aws_lambda_permission` | Grants EventBridge permission to invoke the Lambda |
| `aws_cloudwatch_metric_alarm` | Fires when Lambda `Errors` >= 1 in a 24-hour window |

---

## Lambda Function Configuration

The Lambda is automatically configured by Terraform. The relevant settings are:

| Setting | Value |
|---------|-------|
| Runtime | `python3.12` |
| Handler | `snapshot_cleanup.lambda_handler` |
| Timeout | 300 seconds |
| Memory | 128 MB |
| VPC Subnet | Private subnet created above |
| Security Group | Lambda SG created above |
| Trigger | EventBridge rule (daily at 02:00 UTC) |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SNAPSHOT_RETENTION_DAYS` | `365` | Snapshots older than this are deleted |
| `AWS_REGION_NAME` | `us-east-1` | Region to query |
| `LOG_LEVEL` | `INFO` | Python logging level |


---

## VPC Design — Why No NAT Gateway?

The Lambda runs in a **fully private subnet with no NAT gateway** to minimise cost and attack surface. Instead, two **Interface VPC Endpoints** route traffic to AWS APIs over the AWS private network:

- `com.amazonaws.us-east-1.ec2` — for `DescribeSnapshots` / `DeleteSnapshot`
- `com.amazonaws.us-east-1.logs` — for CloudWatch Logs delivery

This means the Lambda has **no internet access whatsoever**, which is intentional for a cleanup function that only needs to talk to AWS APIs.

---

## Monitoring

### CloudWatch Logs

All Lambda output goes to:

```
/aws/lambda/snapshot-cleanup-dev-snapshot-cleanup
```

Useful log insight queries:

```sql
-- Summary of each run
fields @timestamp, @message
| filter @message like /Cleanup complete/
| sort @timestamp desc
| limit 20

-- All deleted snapshot IDs
fields @timestamp, @message
| filter @message like /Successfully deleted/
| sort @timestamp desc

-- All errors
fields @timestamp, @message
| filter @message like /error/ or @message like /Error/ or @message like /ERROR/
| sort @timestamp desc
```

### CloudWatch Metrics

Navigate to **CloudWatch > Lambda** and monitor:

| Metric | What to watch |
|--------|--------------|
| `Invocations` | Confirms the schedule is firing |
| `Errors` | Any non-zero value should be investigated |
| `Duration` | Spike may indicate a large snapshot backlog |
| `Throttles` | Should always be 0 for this workload |

### CloudWatch Alarm

A metric alarm (`snapshot-cleanup-dev-snapshot-cleanup-errors`) is pre-configured to trigger when `Errors >= 1` over a 24-hour period. This can also be configured to send email alerts via SNS topic
    
### Manual Invocation (testing)

Lambda can either be invoked via AWS console using the Testing Tab or via AWS CLI using the below command

```bash
aws lambda invoke \
  --function-name dev-snapshot-cleanup \
  --region us-east-1 \
  --log-type Tail \
  --payload '{}' \
  response.json \
  --query 'LogResult' \
  --output text | base64 --decode

cat response.json
```

## Assumptions

| Assumption | Detail |
|------------|--------|
| Region | `us-east-1` |
| Snapshot ownership | Only snapshots with `OwnerIds=["self"]` are evaluated |
| Deletion safety | Snapshots in use by an AMI are logged and skipped, not hard-failed |
| remote state | s3 is used for remote state and its configured in the dev.conf file |
| Single AZ | One private subnet in `us-east-1a`; extend `private_subnet_cidr` list for multi-AZ HA |
| No KMS | Encrypted snapshots are supported as long as the Lambda role has `kms:CreateGrant` on the relevant key |

---

## Extending to Other Environments

To add a staging or prod environment, create a new root file (e.g. `prod.tf`) with the same module call but different variable values:

```hcl
module "snapshot_cleanup_prod" {
  source              = "./modules/snapshot_cleanup"
  environment         = "prod"
  region              = "us-east-1"
  project_name        = "snapshot-cleanup"
  vpc_cidr            = "10.1.0.0/16"
  private_subnet_cidr = "10.1.1.0/24"
  availability_zone   = "us-east-1b"
  snapshot_retention_days = 365
  lambda_schedule     = "cron(0 2 * * ? *)"
  log_retention_days  = 90
}
```
