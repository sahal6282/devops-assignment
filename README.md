# 🚀 Deployment Guide

A step-by-step guide for provisioning and testing cloud infrastructure using Terraform and AWS.

---

## 📋 Prerequisites

Ensure the following tools are installed on your local machine before proceeding:

- [Terraform](https://developer.hashicorp.com/terraform/install) v1.5.0 or newer
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [Git](https://git-scm.com/)

---

## 🌍 Infrastructure Region & AMI Compatibility

This project is configured by default to deploy to **`ap-south-1` (Mumbai)**.

Because AWS Machine Images (AMIs) are regional, the infrastructure expects an Ubuntu image specific to the chosen region. If you wish to change the deployment region, you must update two components to maintain compatibility:

1. **Region Setting:** Update the `region` variable in `infra/variables.tf` to your desired AWS region (e.g., `us-east-1`).

2. **AMI Compatibility:** This repository uses a static AMI mapped to the Mumbai region. You must provide a valid Ubuntu 24.04 AMI ID for your chosen region.

   You can find the correct AMI ID using the AWS CLI:

   ```bash
   aws ec2 describe-images \
     --owners 099720109477 \
     --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*" \
     --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
     --output text
   ```

   Or browse manually via the [AWS EC2 Console](https://console.aws.amazon.com/ec2/) under **AMIs → Public Images**.

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

Terraform uses a `terraform.tfvars` file to supply secret values that shouldn't be hardcoded in your infrastructure files. **This file is listed in `.gitignore` and must never be committed to version control.**

### What it is

The repository includes a `variables.tf` that declares all the inputs Terraform needs but leaves them empty. You fill in the actual values by creating a `terraform.tfvars` file inside the `infra/` directory.

### Create the file

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # if an example file exists
# — or create it from scratch:
touch terraform.tfvars
```

### Fill in your values

Open `terraform.tfvars` and add your EC2 key pair name:

```hcl
# terraform.tfvars  ← DO NOT commit this file

key_name = "my-ec2-keypair"   # Name of your EC2 Key Pair in AWS (for SSH access)
```

> **Where does `key_name` come from?**
> Go to **AWS Console → EC2 → Key Pairs → Create key pair**. Give it a name (e.g. `my-ec2-keypair`), download the `.pem` file, and store it safely. Enter that same name as the `key_name` value above.

### Keep it secret

Confirm `terraform.tfvars` is in your `.gitignore` before pushing:

```bash
grep "tfvars" .gitignore
# Expected output: *.tfvars
```

If it's missing, add it:

```bash
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

3. *(Optional)* **Review the deployment plan** to see what resources will be created:

```bash
terraform plan
```

4. **Apply the configuration** to provision the cloud environment:

```bash
terraform apply
```

Type `yes` when prompted to confirm.

5. **Wait for bootstrapping:** Once Terraform completes, it will output the `api_public_ip`. Allow **3–5 minutes** for the EC2 user-data scripts to finish installing Node.js, Python, and downloading the AI models in the background.

---

## Step 3: Test the API

Once the infrastructure is up and the instances are fully bootstrapped, test the end-to-end microservices pipeline.

Run the following `curl` command from your local terminal, replacing `<YOUR_API_PUBLIC_IP>` with the IP address from the previous step:

```bash
curl -X POST http://<YOUR_API_PUBLIC_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Write a short, two-line poem about cloud computing."
      }
    ]
  }'
```

### Expected Response

```json
{
  "message": "Caller → Inference pipeline working",
  "response": "Write a short, two-line poem about cloud computing.\nproceeding\n...",
  "success": true
}
```

---

## Step 4: Teardown & Cleanup

To avoid unnecessary AWS charges from the running NAT Gateway and EC2 instances, destroy the infrastructure when you are done testing:

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

## ⚠️ Notes

- The API is exposed on port `3111`. Ensure this port is accessible in your security group rules.
- **Never commit `terraform.tfvars`** — it contains secrets. Add `*.tfvars` to `.gitignore`.
- Keep your `.pem` key file safe; losing it means you can no longer SSH into your EC2 instances.
