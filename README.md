# AKS Troubleshooting Course for Support Engineers

A structured 10-lesson course with interactive hands-on labs. Each lesson teaches key Kubernetes and AKS concepts, then the corresponding lab deploys a broken environment for you to diagnose and fix.

## Course Overview

| # | Lesson | Lab | Difficulty |
|---|--------|-----|------------|
| 01 | kubectl Fundamentals & AKS Architecture | Scavenger Hunt: find cluster info using kubectl | ★☆☆ |
| 02 | Pods and Containers | Fix a pod with an incorrect image | ★☆☆ |
| 03 | Deployments and ReplicaSets | Fix a failed rollout | ★★☆ |
| 04 | Services and Networking | Service not connecting to pods | ★★☆ |
| 05 | ConfigMaps and Secrets | App fails due to missing configuration | ★★☆ |
| 06 | Storage and Volumes | PVC stuck in Pending | ★★☆ |
| 07 | Network Policies | Traffic blocked between pods | ★★★ |
| 08 | Node Management: Taints & Scheduling | Taints prevent pod scheduling | ★★★ |
| 09 | Azure Integration (NSG / Load Balancer) | NSG blocks external traffic | ★★★ |
| 10 | Advanced Troubleshooting | Multi-problem scenario | ★★★ |

## Recommended Pace

| Week | Lessons | Focus |
|------|---------|-------|
| 1 | 01–03 | Fundamentals: kubectl, Pods, Deployments |
| 2 | 04–06 | Networking, Configuration, Storage |
| 3 | 07–08 | Network Policies, Node Scheduling |
| 4 | 09–10 | Azure Integration, Advanced Troubleshooting |

## Prerequisites

| Tool | Required | Install |
|------|----------|---------|
| Azure CLI (`az`) | Yes | [Install](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| kubectl | Auto-installed | `az aks install-cli` |
| jq | Yes | [Install](https://jqlang.github.io/jq/download/) |

**Azure login required before running any lab:**
```bash
az login
az account set --subscription "<your-subscription>"
```

## How to Use the Course

### 1. Read the Lesson

Each lesson is a Markdown file with theory, diagrams, and key commands:

```
curso/lecciones/01-fundamentos-kubectl/leccion.md
curso/lecciones/02-pods-y-contenedores/leccion.md
...
```

### 2. Run the Corresponding Lab

**Azure Cloud Shell (recommended):**
```bash
chmod +x cloudshell/aks-labs.sh
./cloudshell/aks-labs.sh          # Interactive menu
./cloudshell/aks-labs.sh 1        # Run a specific lab by number
```

**Bash (Linux / macOS / WSL):**
```bash
cd bash
chmod +x lab-01-dns-resolution.sh
./lab-01-dns-resolution.sh
```

**PowerShell (Windows):**
```powershell
cd powershell
.\Lab-01-DnsResolution.ps1
```

## How Labs Work

1. The script validates prerequisites (Azure CLI, login, kubectl, required resource providers)
2. An AKS cluster is created with Azure CNI networking and a **specific problem injected**
3. You investigate and fix the issue using your own skills
4. Use the interactive menu to **validate**, request **hints**, or see the **solution**
5. After completion, choose whether to clean up cloud resources

### Interactive Menu

Once the broken environment is deployed, you see:

```
  ───────────────────────────────────────────────────────
  Lab Menu
  ───────────────────────────────────────────────────────
    [V]  Validate my fix
    [H]  Request a hint
    [S]  Show solution
    [Q]  Quit & Cleanup
```

- **V** – Runs automated validation to check if you fixed the problem
- **H** – Progressive hints (more detail after more attempts)
- **S** – Full solution with explanation (asks for confirmation)
- **Q** – Deletes all Azure resources and exits

## Configuration

Override defaults via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AKS_LAB_REGION` | `canadacentral` | Azure region |
| `AKS_LAB_NODE_COUNT` | `1` | Nodes per cluster |
| `AKS_LAB_VM_SIZE` | `Standard_D8ds_v5` | Node VM size |

Example:
```bash
export AKS_LAB_REGION=eastus
./cloudshell/aks-labs.sh 1
```

## Logs

All sessions are logged to `logs/` with timestamps, user actions, and validation results.

## Cost Estimate

Each lab creates a 1-node `Standard_D8ds_v5` cluster (~$0.40/hr). Labs typically take 30–60 minutes. **Always clean up after finishing.**

## File Structure

```
├── README.md
├── cloudshell/
│   └── aks-labs.sh                # Cloud Shell launcher (recommended)
├── curso/
│   └── lecciones/
│       ├── 01-fundamentos-kubectl/
│       │   ├── leccion.md         # Lesson content
│       │   └── lab-01.sh          # Lab script
│       ├── 02-pods-y-contenedores/
│       │   ├── leccion.md
│       │   └── lab-02.sh
│       └── ...                    # Lessons 03–10
├── bash/                          # Standalone Bash labs
│   ├── lib/common.sh
│   └── lab-*.sh
├── powershell/                    # Standalone PowerShell labs
│   ├── lib/Common.ps1
│   └── Lab-*.ps1
└── logs/
```

## Adding New Labs

1. Copy any existing lab script as a template
2. Define four functions: `deploy`, `validate`, `hint`, `solution`
3. Call `run_lab` (bash) or `Start-Lab` (PowerShell) at the bottom
4. The framework handles pre-checks, menu, logging, and cleanup
