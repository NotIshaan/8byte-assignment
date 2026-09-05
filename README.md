# 8Byte DevOps Assignment

## Overview

This repo contains the infrastructure and deployment setup for a simple Node.js todo API backed by PostgreSQL, running on AWS. The goal was to demonstrate end-to-end ownership of infrastructure provisioning, deployment automation, and monitoring.

The application itself is intentionally minimal — a small Express app with a `/health` endpoint, a `/ready` endpoint that checks DB connectivity, and basic todo CRUD routes. App logic is not the point here, the infrastructure is.

## Architecture

```
Internet → ALB → EC2 (Auto Scaling Group) → RDS PostgreSQL
                      ↑
                   ECR (Docker images)
                      ↑
              GitHub Actions (CI/CD)
```

- **VPC** — one VPC with 2 public subnets and 2 private subnets across 2 availability zones. Public subnets hold the ALB, private subnets hold EC2 and RDS.
- **EC2** — runs inside an Auto Scaling Group with a minimum of 1 instance. On boot, pulls the latest Docker image from ECR via a userdata shell script and runs it as a container.
- **RDS** — PostgreSQL in private subnets, not publicly accessible. Credentials stored in AWS Secrets Manager, fetched at runtime by EC2.
- **ALB** — sits in public subnets, forwards traffic to EC2 on port 3000, health checks against `/health` every 30 seconds.
- **NAT Gateway** *(happy path)* — allows EC2 instances in private subnets to reach ECR, CloudWatch and Secrets Manager without being exposed to the internet. VPC Endpoints per service would be cheaper but adds more resources to manage — documented under Cost Optimization.

## Project Structure

```
8byte-assignment/
  app/
    server.js          # Express app
    server.test.js     # Tests
    package.json
    Dockerfile
  terraform/
    vpc.tf
    sg.tf
    alb.tf
    rds.tf
    ec2.tf
    monitoring.tf
    outputs.tf
    variables.tf
    providers.tf
    userdata.sh
    environments/
      staging.tfvars
      production.tfvars
  .github/
    workflows/
      cicd.yml
  README.md
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with valid credentials
- Docker
- Node.js 20+

## Setup

### 1. Clone the repo

```bash
git clone <repo-url>
cd 8byte-assignment
```

### 2. Install app dependencies

```bash
cd app
npm install
cd ..
```

### 3. Apply infrastructure

```bash
cd terraform
terraform init
terraform apply -var-file=environments/staging.tfvars
```

After apply, Terraform prints the ALB DNS name and ECR repository URL as outputs. Copy the ECR URL — you need it for the next step.

### 4. Push Docker image manually (first time only)

```bash
aws ecr get-login-password --region ap-south-1 | docker login --username AWS \
  --password-stdin <ecr-url>
docker build -t <ecr-url>:latest ./app
docker push <ecr-url>:latest
```

After this, all subsequent image builds and pushes are handled by GitHub Actions.

### 5. Verify

```bash
curl http://<alb-dns-name>/health
# should return {"status":"ok"}
```

### 6. Teardown

```bash
cd terraform
terraform destroy -var-file=environments/staging.tfvars
```

## CI/CD

GitHub Actions workflow at `.github/workflows/cicd.yml` does the following:

- **On every PR** — runs unit and integration tests against a real Postgres service container, scans dependencies with `npm audit`
- **On merge to main** — builds Docker image, scans with Trivy for vulnerabilities, pushes to ECR, triggers an ASG instance refresh on staging which rolls out the new image
- **Production deploy** — same as staging but requires manual approval via GitHub Environments before it runs

### GitHub secrets required

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### GitHub environments required

Create two environments in repo Settings → Environments:
- `staging` — no restrictions
- `production` — add yourself as a required reviewer for the manual approval gate

## Monitoring

All monitoring is defined in `terraform/monitoring.tf` using CloudWatch:

**Alarms** (all notify via SNS email):
- EC2 CPU above 80% for 2 consecutive periods
- RDS CPU above 80%
- RDS free storage below 2GB
- ALB 5xx errors above 10 per minute

**Dashboards:**
- `octabyte-infrastructure` — EC2 CPU, ALB request count, ALB 5xx errors
- `octabyte-database` — RDS CPU, RDS connections, RDS free storage

**Centralized logging:**
- `/octabyte/app` — application logs
- `/octabyte/system` — system logs
- `/octabyte/access` — access logs

CloudWatch agent is installed and configured via `userdata.sh` on each EC2 instance and ships logs from the instance to these log groups automatically.

## Security

- RDS is in private subnets, never publicly accessible
- DB credentials are stored in Secrets Manager and fetched at runtime — never hardcoded in the image or environment files
- Security groups are chained: internet → ALB only, ALB → EC2 only, EC2 → RDS only. Nothing can reach RDS directly from outside.
- EC2 uses an IAM role for ECR, CloudWatch and Secrets Manager access — no hardcoded AWS credentials on the instance

## Cost Optimization

- **NAT Gateway** *(happy path)* — one shared NAT Gateway instead of one per AZ saves ~$32/month per additional AZ. Better approach: VPC Endpoints for ECR, CloudWatch and Secrets Manager which removes the NAT Gateway cost entirely at the expense of more resources to manage.
- **t3.micro everywhere** — cheapest instance type for both EC2 and RDS
- **Single EC2 instance** *(happy path)* — ASG desired capacity is 1. Proper HA would run 2 instances across both AZs.
- **No Multi-AZ RDS** *(happy path)* — single AZ database to save cost. Production would use `multi_az = true`.
- **30 day log retention** — prevents unbounded CloudWatch storage costs

## Backup Strategy

RDS automated backups are enabled with a 7 day retention period. AWS takes a daily snapshot automatically and keeps the last 7 days, giving point-in-time recovery within that window.

`skip_final_snapshot = true` is set *(happy path)* — meaning no final snapshot is taken on `terraform destroy`. In production this would be `false`.

Better approach would also include manual snapshots before major changes and cross-region replication for disaster recovery.

## Secret Management

DB credentials are generated at tfvars level and stored in AWS Secrets Manager via Terraform. EC2 instances fetch the secret at boot time using their IAM role — the password never appears in the Docker image, environment variables baked into the container, or anywhere in the codebase.

## Architecture Decisions

**Flat .tf files over Terraform modules** *(happy path)* — kept all Terraform in flat `.tf` files (vpc.tf, ec2.tf etc) rather than separate module folders. Modules would give better separation of concerns and reusability but add significant boilerplate for an assignment. In production each concern would be its own module with its own variables and outputs.

**Local Terraform state** *(happy path)* — state is stored locally instead of remotely in S3 with DynamoDB locking. Remote state prevents concurrent applies corrupting the state file and protects against losing it if your laptop dies. For production this would be the first thing to set up before anything else.

**ASG over bare EC2** — even at 1 instance, the Auto Scaling Group gives self-healing. If the instance dies it gets replaced automatically without manual intervention.

**EC2 over ECS/EKS** — straightforward for this scale and easier to reason about end to end. ECS would be the natural next step for proper container orchestration without managing the underlying instances.

**No HTTPS on ALB** *(happy path)* — proper setup requires a domain name and ACM certificate. Running on HTTP only for this assignment. Would never do this in production.

**Trivy exit code 0** *(happy path)* — image is scanned for vulnerabilities but the build does not fail on findings. In production you would fail the build on CRITICAL severity findings.
