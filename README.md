# ci-cd-pipeline-k8s-eks-Jenkins-terraform

# 🚀 CI/CD Pipeline — Jenkins + Terraform + AWS EKS

A production-style, fully automated DevOps pipeline that provisions AWS infrastructure with Terraform and deploys a containerised Python app to Kubernetes on EKS via Jenkins.

---

## 📌 Stack

| Layer | Tool |
|---|---|
| Infrastructure as Code | Terraform |
| CI/CD | Jenkins |
| Containerisation | Docker |
| Container Registry | Amazon ECR |
| Orchestration | Kubernetes on AWS EKS |
| Monitoring | Prometheus + Grafana |
| Auto Scaling | Horizontal Pod Autoscaler (HPA) |

---

## 🏗️ Architecture

```
Developer Push
      ↓
GitHub Repository
      ↓
Jenkins Pipeline
      ├── Terraform Init / Plan / Apply
      │       └── VPC + Subnets + NAT Gateway
      │       └── EKS Cluster + Node Group
      │       └── Amazon ECR Repository
      │       └── IAM Roles
      ↓
Docker Build
      ↓
Amazon ECR (tagged with BUILD_NUMBER)
      ↓
AWS EKS Cluster
      ├── k8s-deployment.yaml
      ├── hpa.yaml
      ├── prometheus-deployment.yaml
      └── grafana-deployment.yaml
      ↓
Prometheus + Grafana Monitoring
      ↓
HPA Auto Scaling
```

---

## 📂 Repository Structure

```
.
├── app/
│   └── app.py                      # Python Flask application
├── terraform/
│   ├── main.tf                     # Provider config, backend
│   ├── variables.tf                # Input variables
│   ├── outputs.tf                  # Cluster endpoint, ECR URL
│   ├── vpc.tf                      # VPC, subnets, NAT gateway
│   ├── eks.tf                      # EKS cluster + node group
│   ├── ecr.tf                      # ECR repository + lifecycle
│   └── iam.tf                      # IAM roles
├── Dockerfile
├── Jenkinsfile
├── k8s-deployment.yaml
├── hpa.yaml
├── ingress.yaml
├── prometheus-deployment.yaml
├── grafana-deployment.yaml
├── requirements.txt
└── README.md
```

---

## ✅ Prerequisites

Install the following on your local machine and inside the Jenkins container:

| Tool | Purpose | Install |
|---|---|---|
| AWS CLI | AWS authentication | [docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Terraform >= 1.7 | Infrastructure provisioning | [developer.hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| kubectl | Kubernetes CLI | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Docker Desktop | Container runtime | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Jenkins | CI/CD server | Running via Docker (see Phase 1) |

---

## 🔐 Phase 1 — AWS & Local Setup

### Configure AWS CLI

```bash
aws configure
# AWS Access Key ID:     <your-key>
# AWS Secret Access Key: <your-secret>
# Default region:        us-east-1
# Default output format: json
```

Verify:

```bash
aws sts get-caller-identity
```

### Start Jenkins via Docker

```bash
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts
```

Access Jenkins at `http://localhost:8080`. Retrieve the initial admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## 🔧 Phase 2 — Jenkins Configuration

### Install Plugins

Go to **Manage Jenkins → Plugins → Available** and install:

- Docker Pipeline
- Kubernetes CLI
- Pipeline
- Credentials Binding
- AWS Credentials
- Terraform
- Blue Ocean *(optional)*

Restart Jenkins after installation.

### Add AWS Credentials

Go to **Manage Jenkins → Credentials → System → Global Credentials → Add Credentials**:

| Field | Value |
|---|---|
| Kind | AWS Credentials |
| ID | `eks-aws-creds` |
| Description | AWS credentials for EKS CI/CD |
| Access Key ID | Your AWS key |
| Secret Access Key | Your AWS secret |

### Install Tools Inside Jenkins Container

```bash
docker exec -it jenkins bash

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/
kubectl version --client

# Install AWS CLI
apt update && apt install -y curl unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && ./aws/install
aws --version

# Install Terraform
apt install -y wget
wget https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
unzip terraform_1.7.5_linux_amd64.zip && mv terraform /usr/local/bin/
terraform version
```

---

## 🏗️ Phase 3 — Terraform Files

### `terraform/variables.tf`

```hcl
variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "devops-cluster"
}

variable "ecr_repo_name" {
  default = "devops-app"
}

variable "node_instance_type" {
  default = "t3.small"
}

variable "desired_nodes" {
  default = 2
}
```

### `terraform/main.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Recommended for teams: remote state in S3
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "eks/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-lock"
  # }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}
```

### `terraform/vpc.tf`

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
```

### `terraform/eks.tf`

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    devops_nodes = {
      min_size       = 1
      max_size       = 5
      desired_size   = var.desired_nodes
      instance_types = [var.node_instance_type]

      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  # Prevent accidental cluster deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Environment = "dev"
    Project     = "devops-pipeline"
  }
}
```

### `terraform/ecr.tf`

```hcl
resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
```

### `terraform/outputs.tf`

```hcl
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}
```

---

## ⚡ Phase 4 — Handling Existing Infrastructure

Terraform is **idempotent** — running `terraform apply` repeatedly is safe. It only changes what has drifted from your configuration. The pipeline handles all three scenarios automatically:

### Scenario A: Infrastructure does not exist yet

`terraform apply` creates everything from scratch. EKS cluster creation takes ~15 minutes on first run.

### Scenario B: Infrastructure already exists (created by Terraform)

`terraform plan` compares your `.tf` files against the Terraform state file. If nothing has changed, it outputs:

```
No changes. Your infrastructure matches the configuration.
```

The Apply stage completes in seconds with no side effects.

### Scenario C: Infrastructure exists but was created manually (eksctl / console)

Terraform is unaware of resources it did not create. Use `terraform import` to adopt them:

```bash
cd terraform/
terraform import module.eks.aws_eks_cluster.this devops-cluster
terraform import aws_ecr_repository.app devops-app
```

After importing, run `terraform plan` to detect any config drift between your `.tf` files and the real infrastructure, then apply to reconcile.

### Scenario D: Someone manually changed a resource (drift)

`terraform plan` detects the change and shows a diff. For example, if a node group was manually scaled from 2 to 4, Terraform will flag it and offer to revert to the value in your `.tf` file.

### Scenario E: A previous apply failed partway through

Terraform's state file tracks what was already created. Re-running `terraform apply` resumes from the failure point — already-created resources are not recreated.

> **Note:** The `prevent_destroy = true` lifecycle rule on the EKS cluster in `eks.tf` acts as a safety net — `terraform destroy` will error out on the cluster itself, preventing accidental teardown.

---

## ▶️ Phase 5 — First-Time Infrastructure Provisioning

```bash
cd terraform/

# Download providers and modules
terraform init

# Preview everything that will be created
terraform plan -out=tfplan

# Apply (first run ~15 min, subsequent runs are near-instant if no changes)
terraform apply tfplan

# Configure kubectl to connect to the new cluster
$(terraform output -raw configure_kubectl)

# Verify nodes are ready
kubectl get nodes
```

---

## 🔌 Phase 6 — Jenkinsfile

Replace the `Jenkinsfile` in the root of your repo with this version:

```groovy
pipeline {

    agent any

    environment {
        AWS_REGION   = "us-east-1"
        CLUSTER_NAME = "devops-cluster"
        ECR_REPO     = sh(returnStdout: true, script: '''
            cd terraform && terraform output -raw ecr_repository_url
        ''').trim()
        IMAGE_TAG    = "${env.BUILD_NUMBER}"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git'
            }
        }

        stage('Terraform Init & Validate') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        sh 'terraform init -input=false'
                        sh 'terraform fmt -check'
                        sh 'terraform validate'
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        // Safe to run on every build — no-op if infra already matches
                        sh 'terraform plan -input=false -out=tfplan'
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    dir('terraform') {
                        // Idempotent: skips if infra already exists and matches
                        sh 'terraform apply -input=false tfplan'
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t devops-app:${IMAGE_TAG} ."
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} \
                          | docker login --username AWS --password-stdin ${ECR_REPO}

                        docker tag devops-app:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
                        docker tag devops-app:${IMAGE_TAG} ${ECR_REPO}:latest

                        docker push ${ECR_REPO}:${IMAGE_TAG}
                        docker push ${ECR_REPO}:latest
                    """
                }
            }
        }

        stage('Configure EKS Access') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'eks-aws-creds'
                ]]) {
                    sh "aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}"
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh """
                    sed -i 's|:latest|:${IMAGE_TAG}|g' k8s-deployment.yaml

                    kubectl apply -f k8s-deployment.yaml
                    kubectl apply -f hpa.yaml
                    kubectl apply -f prometheus-deployment.yaml
                    kubectl apply -f grafana-deployment.yaml

                    kubectl rollout status deployment/devops-app --timeout=120s
                """
            }
        }

        stage('Install Metrics Server') {
            steps {
                sh """
                    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    kubectl get pods
                    kubectl get svc
                    kubectl get hpa
                """
            }
        }
    }

    post {
        success {
            echo "✅ Deployment successful! Build #${env.BUILD_NUMBER}"
        }
        failure {
            echo "❌ Deployment failed at stage: ${env.STAGE_NAME}"
        }
        always {
            sh "docker rmi devops-app:${IMAGE_TAG} || true"
        }
    }
}
```

---

## 🔗 Phase 7 — Create Jenkins Pipeline Job

1. Go to **Jenkins Dashboard → New Item**
2. Choose **Pipeline**, give it a name, click OK
3. Under **Pipeline**, select **Pipeline script from SCM**
4. Set SCM to **Git**
5. Enter your repository URL
6. Set branch to `main`
7. Set Script Path to `Jenkinsfile`
8. Save and click **Build Now**

The pipeline executes all stages in order:

```
Checkout → Terraform Init/Validate → Terraform Plan → Terraform Apply
  → Docker Build → ECR Push → Configure EKS → Deploy to EKS
  → Metrics Server → Verify
```

---

## 📊 Phase 8 — Monitoring Setup

### Access Prometheus

```bash
kubectl get svc prometheus-service
# Copy the EXTERNAL-IP and open in browser on port 9090
```

### Access Grafana

```bash
kubectl get svc grafana-service
# Copy the EXTERNAL-IP and open in browser on port 3000
```

Default Grafana credentials: `admin` / `admin`

Add Prometheus as a data source:

```
URL: http://prometheus-service:9090
```

---

## 📈 Phase 9 — Test Auto Scaling

Install the Metrics Server if not already done:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes
kubectl top pods
```

Generate load to trigger HPA:

```bash
kubectl run -i --tty load-generator --image=busybox -- sh
# Inside the container:
while true; do wget -q -O- http://devops-service; done
```

Watch scaling in action:

```bash
kubectl get hpa -w
kubectl get pods -w
```

---

## 🔄 Rollback

Because images are tagged with `BUILD_NUMBER` (not `latest`), you can roll back instantly:

```bash
# Roll back to the previous deployment
kubectl rollout undo deployment/devops-app

# Roll back to a specific build number
kubectl set image deployment/devops-app devops-app=<ECR_URL>/devops-app:42
```

---

## 💰 Cleanup

```bash
# Remove Kubernetes resources first
kubectl delete -f k8s-deployment.yaml
kubectl delete -f prometheus-deployment.yaml
kubectl delete -f grafana-deployment.yaml
kubectl delete -f hpa.yaml

# Remove prevent_destroy from eks.tf, then destroy all infrastructure
cd terraform/
terraform destroy -auto-approve

# Resources deleted:
# ✓ EKS cluster + node group
# ✓ VPC + subnets + NAT gateway
# ✓ Amazon ECR repository + images
# ✓ IAM roles and policies
```

> **Before running destroy:** comment out or remove the `prevent_destroy = true` block in `terraform/eks.tf`, otherwise Terraform will error on the cluster deletion.

---

## 📋 Terraform vs Manual — Comparison

| | Manual (eksctl) | This Repo (Terraform) |
|---|---|---|
| Infrastructure definition | CLI commands | Declarative `.tf` files in Git |
| State tracking | None | Full state file |
| Idempotency | No | Yes — safe to re-run |
| Drift detection | No | `terraform plan` shows drift |
| Partial failure recovery | Manual | Automatic resume |
| Existing infra import | Not applicable | `terraform import` |
| Accidental deletion guard | None | `prevent_destroy = true` |
| Cleanup | Manual per-resource | `terraform destroy` |
| Team collaboration | Hard | S3 remote state + DynamoDB lock |

---

## 🔮 Future Improvements

- [ ] Helm Charts for Prometheus & Grafana
- [ ] ArgoCD for GitOps-style deployments
- [ ] SonarQube code quality gate in pipeline
- [ ] Trivy container image security scanning
- [ ] Slack notifications on pipeline success/failure
- [ ] Blue-Green deployment strategy
- [ ] S3 + DynamoDB remote Terraform state for team use

---

## 🛠️ Troubleshooting

**kubectl can't connect to cluster**
```bash
aws eks update-kubeconfig --region us-east-1 --name devops-cluster
```

**Terraform plan shows unexpected changes**
```bash
# Review the diff carefully before applying
terraform plan -detailed-exitcode
```

**ECR push denied**
```bash
# Re-authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

**HPA shows `<unknown>` for CPU**
```bash
# Metrics server is likely not running
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## 🎯 Skills Demonstrated

`Jenkins` `Terraform` `Docker` `Kubernetes` `AWS EKS` `Amazon ECR` `CI/CD Pipelines` `Prometheus` `Grafana` `HPA` `Infrastructure as Code` `Cloud-Native Deployment` `DevOps Automation`
