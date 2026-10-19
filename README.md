# Azure Kubernetes Service (AKS) Platform with Terraform

## Project Overview

This project demonstrates the design, provisioning, deployment, and validation of a containerized application on **Azure Kubernetes Service (AKS)** using Infrastructure as Code (IaC).

The platform uses modular Terraform configurations to provision Azure networking, an AKS cluster, Azure Container Registry (ACR), and role-based access control (RBAC). A Python Flask API is containerized with Docker and deployed to Kubernetes using Kustomize.

The project also includes a GitHub Actions CI workflow for validating Terraform configurations, Kubernetes manifests, Python code, and Docker builds.

**Key technologies:** Microsoft Azure, Terraform, AKS, Kubernetes, Docker, ACR, Azure RBAC, Kustomize, GitHub Actions, Python, Flask.

## Architecture

```text
                  Developer / GitHub
                         |
              Terraform Infrastructure
                         |
                Azure Resource Group
                         |
          +--------------+--------------+
          |                             |
     Azure Networking             Azure Container
       VNet/Subnet                 Registry (ACR)
          |                             |
          |                        Docker Image
          |                             |
          +---------- AKS --------------+
                         |
                 Managed Identity
                 + AcrPull RBAC
                         |
                 Kubernetes Cluster
                         |
                 Kustomize Dev Overlay
                         |
                  Flask Deployment
                         |
                  Kubernetes Service
                     ClusterIP
                         |
                  Flask API (8001)
                         |
                  / and /health
```

The AKS worker node runs inside the provisioned Azure subnet. Its kubelet identity receives the `AcrPull` role on ACR, allowing Kubernetes to retrieve the application image without embedding registry credentials in deployment manifests.

## Infrastructure as Code

Terraform is organized into reusable modules to separate infrastructure responsibilities.

```text
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── versions.tf
└── modules/
    ├── networking/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── aks/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── acr/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### Networking Module

Provisions an Azure Virtual Network and dedicated subnet for AKS.

- Virtual network: `vnet-aks-platform-dev`
- Address space: `10.20.0.0/16`
- AKS subnet: `snet-aks-dev`
- Subnet address range: `10.20.1.0/24`

The subnet ID is passed to the AKS module, enabling the cluster's worker nodes to use the configured network.

### AKS Module

Provisions an Azure Kubernetes Service cluster with:

- AKS Free management tier
- One system node
- `Standard_D2s_v4` virtual machine size
- 30 GB managed OS disk
- System-assigned managed identity
- Azure-integrated Kubernetes infrastructure

The AKS worker node successfully reached the `Ready` state during deployment.

### Azure Container Registry Module

Provisions a private Azure Container Registry using the Basic SKU.

- Registry: `acraksplatformdev12345`
- Administrative user disabled
- Container image: `flask-aks-api:v2`

An Azure RBAC role assignment grants the AKS kubelet identity `AcrPull` access to the registry.

This avoids hardcoding registry passwords in Kubernetes manifests.

## Containerized Flask Application

The application is a lightweight Python Flask API packaged into a Docker image.

It exposes two endpoints:

| Endpoint | Purpose |
|---|---|
| `/` | Returns application information and version |
| `/health` | Returns application health status |

The container listens on port `8001`.

### Docker Image Build

The image was built for the `linux/amd64` architecture to match the Azure AKS worker node.

```bash
docker buildx build \
  --platform linux/amd64 \
  -t acraksplatformdev12345.azurecr.io/flask-aks-api:v2 \
  -f app/Dockerfile \
  --push \
  ./app
```

The image was successfully pushed to ACR and verified using Azure CLI.

## Kubernetes Deployment and Kustomize

The project uses Kubernetes manifests and Kustomize to separate reusable application configuration from environment-specific customization.

```text
kubernetes/
├── base/
└── overlays/
    └── dev/
```

The base configuration defines the application's Kubernetes resources, including the Deployment and ClusterIP Service.

The development overlay customizes the deployment, including the container image reference and desired replica count.

### ACR Image Override

```yaml
images:
  - name: flask-aks-api
    newName: acraksplatformdev12345.azurecr.io/flask-aks-api
    newTag: v2
```

This allows the same base manifests to be reused while changing image sources for different deployment environments.

### Deployment

```bash
kubectl apply -k kubernetes/overlays/dev
```

The deployed application reached the following state:

```text
NAME                READY   UP-TO-DATE   AVAILABLE
dev-flask-aks-api   1/1     1            1
```

The application pod reached `Running` with zero restarts.

### Kubernetes Service

A ClusterIP Service exposes the application internally on port `80`, forwarding traffic to container port `8001`.

The application was tested using local port forwarding without exposing it through a public Azure Load Balancer.

```bash
kubectl port-forward service/dev-flask-aks-service 8080:80
```

## Application Validation

### Application Endpoint

```bash
curl http://localhost:8080/
```

Successful response:

```json
{
  "message": "Hello from Azure Kubernetes Service v2!",
  "status": "running",
  "version": "2.0"
}
```

### Health Endpoint

```bash
curl http://localhost:8080/health
```

Successful response:

```json
{
  "status": "healthy"
}
```

Both endpoints were successfully tested against the application running in Azure Kubernetes Service.

## Kubernetes Self-Healing Validation

To verify Kubernetes' ability to maintain the desired application state, the running pod was manually deleted.

```bash
kubectl delete pod -l app=flask-aks-api
```

The Kubernetes Deployment controller automatically created a replacement pod.

**Original pod:**

```text
dev-flask-aks-api-cdc964875-nhpj2
```

**Replacement pod:**

```text
dev-flask-aks-api-cdc964875-8mt6k
```

The replacement reached `1/1 Running` with zero restarts.

This demonstrated Kubernetes' declarative reconciliation and pod self-healing behavior.

## Continuous Integration with GitHub Actions

A GitHub Actions CI workflow validates the application and infrastructure code.

The workflow includes:

- Python source compilation checks
- Docker image build validation
- Kubernetes manifest rendering with Kustomize
- Terraform formatting checks
- Terraform initialization and configuration validation

The CI workflow completed successfully.

**Deployment scope:** GitHub Actions performs validation and build checks. Azure infrastructure provisioning, image publishing, and AKS deployment were executed manually during this project.

## Troubleshooting and Engineering Challenges

### 1. Azure VM SKU Restrictions

The original AKS configuration specified `Standard_B2s`.

Azure rejected the VM size because it was not permitted for the subscription in East US.

**Investigation:**

```bash
az vm list-skus --location eastus \
  --resource-type virtualMachines \
  --size Standard_D2s_v4 \
  --all
```

**Resolution:** Selected `Standard_D2s_v4` after checking regional SKU restrictions and available vCPU quota.

### 2. Azure Regional vCPU Quota

Although `Standard_B2s_v2` appeared in Azure's permitted SKU list, the subscription had zero quota for its VM family.

**Investigation:**

```bash
az vm list-usage --location eastus -o table
```

**Lesson learned:** VM SKU availability and subscription quota are separate deployment constraints. Both must be validated.

### 3. Docker Build Context

The initial Docker build failed because `requirements.txt` and `app.py` were outside the specified build context.

**Resolution:** Updated the Docker build command to use `./app` as the build context.

### 4. Container Architecture Compatibility

The development machine uses Apple Silicon, while the AKS worker node runs Linux on AMD64.

**Resolution:** Used Docker Buildx with `--platform linux/amd64` to produce a compatible container image.

### 5. ACR Authentication and Authorization

Azure CLI authentication was used to push the Docker image to ACR.

The AKS kubelet identity was separately authorized to pull images using the Azure `AcrPull` role.

**Lesson learned:** Developer authentication and workload identity permissions serve different purposes.

## Deployment Workflow

The project can be reproduced using the following general workflow.

### 1. Initialize Terraform

```bash
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

An authenticated Azure CLI session and appropriate Azure subscription permissions are required. The Terraform `subscription_id` variable must also be provided.

### 2. Provision Infrastructure

```bash
terraform apply
```

### 3. Connect to AKS

```bash
az aks get-credentials \
  --resource-group rg-aks-platform-dev \
  --name aks-aks-platform-dev \
  --overwrite-existing
```

### 4. Build and Push Application Image

From the project root:

```bash
az acr login --name acraksplatformdev12345

docker buildx build \
  --platform linux/amd64 \
  -t acraksplatformdev12345.azurecr.io/flask-aks-api:v2 \
  -f app/Dockerfile \
  --push \
  ./app
```

### 5. Deploy to Kubernetes

```bash
kubectl apply -k kubernetes/overlays/dev
kubectl get nodes
kubectl get pods
kubectl get deployments
kubectl get services
```

### 6. Validate Application

```bash
kubectl port-forward service/dev-flask-aks-service 8080:80
```

In a second terminal:

```bash
curl http://localhost:8080/
curl http://localhost:8080/health
```

## Cost Management and Infrastructure Cleanup

The project was deployed as a temporary learning environment rather than a continuously running production workload.

To avoid unnecessary Azure charges, the infrastructure was destroyed after successful validation.

```bash
cd terraform
terraform destroy
```

Terraform reported six resources destroyed.

The AKS-managed resource group was also checked after deletion, with no matching group returned.

The project source code remains available in GitHub, allowing the infrastructure to be recreated when needed.

Azure usage charges incurred before deletion may still appear later due to billing delays.

## Project Outcomes

This project demonstrated hands-on experience with:

- Designing and provisioning modular Azure infrastructure using Terraform
- Configuring AKS networking and worker nodes
- Implementing Azure managed identity and RBAC integration
- Building and publishing Docker images to ACR
- Deploying containerized workloads with Kubernetes and Kustomize
- Configuring internal Kubernetes networking
- Validating application health and service connectivity
- Testing Kubernetes self-healing
- Implementing CI checks with GitHub Actions
- Troubleshooting Azure subscription restrictions and container build issues
- Managing cloud infrastructure lifecycle and costs

## Future Improvements

Potential next iterations include implementing automated Azure deployments through GitHub Actions, integrating workload identity for application-level Azure access, adding ingress and TLS, introducing centralized observability, and expanding Kubernetes environments.

---

**Project status:** Successfully deployed, validated, and cleaned up after testing.