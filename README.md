# 🚀 DevOps Internship Assignment — Deployment Guide

A complete guide to deploying a multi-VM private-subnet microservices stack on AWS using Terraform, exposing an SLM inference pipeline through a JSON HTTP API.

---

## 📋 Prerequisites

Ensure the following tools are installed on your local machine before proceeding:

- [Terraform](https://developer.hashicorp.com/terraform/install) v1.5.0 or newer
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [Git](https://git-scm.com/)

---

## 🏗️ Architecture Diagram

The diagram below illustrates the VPC structure, the separation of public and private subnets, and the RPC communication flow between the API Gateway and the worker nodes.

```
 🌎 Public Internet
        │
        ▼
 ┌─────────────────────────────────────────────────────────┐
 │  AWS VPC (10.0.0.0/16)                                  │
 │                                                         │
 │  [ 🌐 Public Subnet: 10.0.1.0/24 ]                      │
 │    ├─ 🖥️  API Gateway VM (Public IP)                    │
 │    └─ 🚪 NAT Gateway (Outbound for workers)             │
 │          │                                              │
 │          │ (WebSocket RPC on Port 49134)                │
 │          ▼                                              │
 │  [ 🔒 Private Subnet: 10.0.2.0/24 ]                     │
 │    ├─ ⚙️  Caller Worker VM (Node.js)                    │
 │    │     │ (Internal RPC)                               │
 │    │     ▼                                              │
 │    └─ 🧠 Inference Worker VM (Python SLM)               │
 └─────────────────────────────────────────────────────────┘
```

**How to read this flow:**

- **Ingress:** External traffic hits the API Gateway VM on port `3111` via its public IP.
- **Dispatch:** The API Gateway forwards the request over the internal VPC network to the Caller Worker on port `49134` via WebSocket RPC.
- **Inference:** The Caller Worker communicates with the Inference Worker to execute the SLM model logic and returns the result back up the chain.
- **Network Security:** Worker VMs have no public IP addresses and are isolated in a private subnet. They reach the internet for updates only through the NAT Gateway.

---

## 🌍 Infrastructure Region & AMI Compatibility

This project is configured by default to deploy to **`ap-south-1` (Mumbai)**.

Because AWS Machine Images (AMIs) are regional, the infrastructure expects an Ubuntu image specific to the chosen region. If you wish to change the deployment region, you must update two components:

1. **Region Setting:** Update the `region` variable in `infra/variables.tf` to your desired AWS region (e.g., `us-east-1`).

2. **AMI Compatibility:** This repository uses a static AMI mapped to the Mumbai region. You must supply a valid Ubuntu 24.04 AMI ID for your chosen region:

   ```bash
   aws ec2 describe-images \
     --owners 099720109477 \
     --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" \
     --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
     --output text
   ```

> **Note on Reproducibility:** The configuration is pinned to `ap-south-1` to ensure immediate, out-of-the-box success on a clean AWS account. It is structured to allow easy porting to other regions by updating `variables.tf` and supplying the appropriate AMI ID as described above.

---

## Step 1: Configure AWS Credentials

Authenticate your local machine with your AWS account so Terraform has permission to provision infrastructure.

1. Generate an **Access Key ID** and **Secret Access Key** from your [AWS IAM Console](https://console.aws.amazon.com/iam/).

2. Run the AWS configuration wizard:

```bash
aws configure
```

3. Enter your credentials when prompted:

```
AWS Access Key ID [None]: <YOUR_ACCESS_KEY>
AWS Secret Access Key [None]: <YOUR_SECRET_KEY>
Default region name [None]: ap-south-1
Default output format [None]: json
```

---

## Step 1.5: Configure Your `terraform.tfvars` File

Terraform uses a `terraform.tfvars` file to supply secret values that shouldn't be hardcoded in your infrastructure files. **This file must never be committed to version control.**

### Create the file

```bash
cd infra
touch terraform.tfvars
```

### Fill in your values

```hcl
# terraform.tfvars  ← DO NOT commit this file

key_name = "my-ec2-keypair"   # Name of your EC2 Key Pair in AWS (for SSH access)
```

> **Where does `key_name` come from?**
> Go to **AWS Console → EC2 → Key Pairs → Create key pair**. Give it a name, download the `.pem` file, and store it safely. Use that same name as the `key_name` value above.

### Keep it secret

```bash
grep "tfvars" .gitignore   # confirm *.tfvars is present
# if missing:
echo "*.tfvars" >> .gitignore
```

---

## Step 2: Initialize and Deploy Infrastructure

Terraform will provision the VPC, subnets, NAT Gateway, security groups, and EC2 instances.

1. **Clone this repository** and navigate to the infrastructure directory:

```bash
git clone <YOUR_REPO_URL>
cd infra
```

2. **Initialize Terraform** to download the required AWS providers:

```bash
terraform init
```

3. *(Optional)* **Review the deployment plan:**

```bash
terraform plan
```

4. **Apply the configuration:**

```bash
terraform apply
```

Type `yes` when prompted to confirm.

5. **Wait for bootstrapping:** Once Terraform completes, it will output the `api_public_ip`. Allow **3–5 minutes** for the EC2 user-data scripts to finish installing Node.js, Python, and downloading the AI models in the background.

---

## Step 3: Test the API

### Request

```bash
curl -X POST http://<YOUR_API_PUBLIC_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello"}]}'
```

### Schema

| Field | Type | Description |
|---|---|---|
| `messages` | array | Conversation turns to send to the model |
| `messages[].role` | string | Either `"user"` or `"assistant"` |
| `messages[].content` | string | The message text |

### Expected Response

```json
{
  "message": "Caller → Inference pipeline working",
  "response": "Hello\nproceeding\n...",
  "success": true
}
```

---

## Step 4: Teardown & Cleanup

To avoid unnecessary AWS charges from the running NAT Gateway and EC2 instances:

```bash
terraform destroy
```

Type `yes` when prompted to confirm.

---

## 📁 Project Structure

```
.
└── infra/
    ├── main.tf                  # Core infrastructure resources
    ├── variables.tf             # Variable declarations (committed)
    ├── outputs.tf               # Output values (e.g. api_public_ip)
    ├── terraform.tfvars         # ⚠️  Your secret values — NOT committed
    └── terraform.tfvars.example # Safe template to share with the team
```

---

## 🛡️ Production Hardening Considerations

- **TLS & Authentication:** Terminate HTTPS at an ALB with an ACM certificate. Enforce API key or JWT validation at the gateway before any request reaches the worker mesh.
- **Secrets Management:** Move all secrets out of `terraform.tfvars` and into AWS Secrets Manager or SSM Parameter Store, injected at runtime.
- **IAM Least Privilege:** Assign each EC2 instance a dedicated IAM role scoped to only the permissions it requires.
- **mTLS on Internal RPC:** VPC isolation alone is not sufficient. Add mutual TLS between workers to prevent lateral movement if any instance is compromised.
- **Containerisation:** Package each worker as a Docker image to eliminate environment drift and ensure consistent behaviour across dev, staging, and production.
- **High Availability:** Replace single VMs with Auto Scaling Groups behind an internal ALB with health checks, so unhealthy instances are replaced automatically.
- **Observability:** Add CloudWatch Log Groups, structured JSON logging on all workers, and alerting on error rates and inference latency.

## 📈 Scaling to a 100x Larger Model

At 100x scale the shift is from managing servers to managing a platform:

- **GPU Compute:** Replace `t3` instances with `g4dn` or `p3` GPU instances. Use Spot instances for inference workloads to manage cost.
- **Inference Server:** Replace the custom Python worker with a dedicated inference server such as vLLM or NVIDIA Triton for batching, quantisation, and VRAM management.
- **Model Storage:** Weights too large to bake into an AMI would be stored in S3 and loaded at startup, or served from EFS shared across inference nodes.
- **Kubernetes Orchestration:** Migrate from raw EC2 to Amazon EKS. Kubernetes provides automated pod replication, self-healing, and GPU-aware resource scheduling — ensuring models have the VRAM they need without being killed by the OOM killer.
- **Async API:** Synchronous HTTP will time out under heavy inference load. Shift to an async pattern where the API returns a job ID immediately, with clients polling or receiving a webhook on completion.

---

## ⚠️ Notes

- The API is exposed on port `3111`. Ensure this port is open in your EC2 security group rules.
- **Never commit `terraform.tfvars`** — it contains secrets. Confirm `*.tfvars` is in `.gitignore`.
- Keep your `.pem` key file safe; losing it means you can no longer SSH into your EC2 instances.
