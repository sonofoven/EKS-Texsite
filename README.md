# TexSite: A GitOps-Managed Personal Website on EKS

TexSite is a small, end-to-end GitOps project that provisions an EKS cluster with Terraform, builds and publishes an NGINX-based website image to ECR based on an input LaTeX file, and continuously deploys it to Kubernetes using Flux.

The repo is intentionally minimal: one app (NGINX), one public ingress (AWS ALB), and a clean CI/CD path from Git → container image → automated manifest update → rollout.


## Features

- **Terraform-provisioned AWS foundation**: EKS cluster + ECR repo + IAM roles needed for controllers and automation.
- **Docker-based website delivery**: your site is packaged as a container image and pushed to **Amazon ECR**.
- **Flux GitOps**: Flux bootstraps from your GitHub repo and applies everything under `cluster/`.
- **Automated image updates**:
  - Flux **ImageRepository** scans ECR tags
  - **ImagePolicy** chooses the “latest” tag
  - **ImageUpdateAutomation** commits the new image tag back into this repo
  - Flux reconciles the commit and rolls out the new version automatically
- **Public ingress via AWS Load Balancer Controller** (ALB).
- **Support for horizontal auto-scaling** (EKS Auto Mode + HPA). your site automatically expands to adapt to increased load/traffic


## Project Structure (high level)
```
terraform/                # AWS provisioning (EKS, ECR, IAM)
nginx/                    # Docker context for the website image
scripts/
  bootstrap.sh            # One-command provisioning + Flux bootstrap
  destroyAll.sh           # One-command teardown
  resume2html.sh          # Example “source → site artifact” step (if used)
cluster/
  flux-system/            # Flux bootstrap/customization manifests
  infra/                  # Cluster add-ons (AWS Load Balancer Controller)
  apps/
    nginx/                # NGINX workload, Service, Ingress, autoscaling, image automation
```



## Prerequisites

Local tools:

- AWS CLI (authenticated to your account)
- Terraform
- Docker (with buildx)
- kubectl
- Flux CLI
- GitHub CLI (`gh`) authenticated to the repo you will bootstrap from

AWS-side expectations:

- You can create EKS/ECR/IAM resources
- Your cluster can reach AWS APIs (typical for EKS in private subnets via NAT, or public subnets)


## Bootstrap: First-Time Setup

From the project root, run:

```bash
cd scripts
./bootstrap.sh
```

This script performs the core flow:

- `terraform init && terraform apply`
- converts your source content found in `./latex/resume.tex` (`.tex` → HTML)
- logs into ECR and pushes an initial image tag
- configures `kubectl` for the new cluster
- runs `flux bootstrap github ... --path=cluster` so Flux reconciles the repo
- renders template-based manifests with your real cluster values (cluster name, region, VPC ID, IAM role ARNs)
- stores key values as **GitHub Actions variables** for CI/CD


## How deployments work (GitOps loop)

### 1) You push a change to Git
You update the website source LaTeX file and push it to the GitHub repository. It can be found here `./latex/resume.tex`.

### 2) CI builds and pushes a new image tag to ECR
A GitHub Actions workflow (in your repo) converts the LaTeX to html, builds the Docker image, and pushes it to the ECR repo.

This project’s bootstrap script also sets repo variables that a workflow can consume (e.g., ECR repo URL and region), so the workflow can stay generic and environment-aware.

### 3) Flux image automation updates manifests
Flux’s image automation resources watch ECR and update the image tag in the Kubernetes manifests, then commit the change back to `main`.

### 4) Flux reconciles the commit and rolls out
Once the repo is updated, Flux applies it automatically; Kubernetes rolls the Deployment.

## Public access (ALB Ingress)

TexSite uses **AWS Load Balancer Controller** to provision an internet-facing ALB.

After reconciliation:

```bash
kubectl -n default get ingress nginx-texsite
```

Look for the `ADDRESS` field (this is the ALB DNS name). That DNS name is your public entry point.

## Grafana + Prometheus monitoring

The service is monitored by Prometheus and visualized with Grafana. You can access Grafana with this command:

```bash
kubectl port-forward -n monitoring svc/monitoring-prometheus-grafana 3000:80
```

Once the port is being forwarded, access Grafana on a web browser via `127.0.0.1:3000`. Default username is `admin` and default password is `prom-operator`

To get your nginx site's information, you can either set up your own dashboard or import one and select Prometheus as your data source. I prefer this one:
```bash
https://grafana.com/grafana/dashboards/17452-nginx/
```

Now you can view connection and usage stats of your site as well as the whole cluster

## Operations: useful commands

### Flux health
```bash
flux get kustomizations -A
flux get helmreleases -A
```

### Image automation status
```bash
flux get images all -A
kubectl -n flux-system describe imagerepository nginx-texsite
kubectl -n flux-system describe imagepolicy nginx-texsite
kubectl -n flux-system describe imageupdateautomation nginx-texsite
```

## Teardown

To remove all provisioned resources:

```bash
cd scripts
./destroyAll.sh
```

## Notes on extending the project

- Add TLS + custom domain via ACM + Ingress annotations.
- Add a second environment (dev/prod) by splitting `cluster/` into overlays (kustomize) and bootstrapping separate clusters.
