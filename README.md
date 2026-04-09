# AKS Troubleshooting Labs

Interactive hands-on labs that deploy a broken AKS environment for you to diagnose and fix.

## How it works

1. Run a lab script (Bash or PowerShell)
2. The script validates prerequisites (Azure CLI, login, kubectl)
3. An AKS cluster is created with a **specific problem injected**
4. You investigate and fix the issue using your own skills
5. Use the interactive menu to **validate**, request **hints**, or see the **solution**
6. After completion, choose whether to clean up cloud resources

## Prerequisites

| Tool | Required | Install |
|------|----------|---------|
| Azure CLI (`az`) | Yes | [Install](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| kubectl | Auto-installed | `az aks install-cli` |
| jq (Bash only) | Yes | [Install](https://jqlang.github.io/jq/download/) |
| Bash / WSL | For bash scripts | Windows: WSL or Git Bash |
| PowerShell 5.1+ | For PS scripts | Built into Windows |

**Azure login required before running any lab:**
```bash
az login
az account set --subscription "<your-subscription>"
```

## Available Labs

| # | Lab | Problem | Difficulty |
|---|-----|---------|------------|
| 01 | DNS Resolution Failure | NetworkPolicy blocks all egress including DNS | ★★☆ |
| 02 | Pod Stuck in Pending | nodeSelector references non-existent label | ★☆☆ |
| 03 | CrashLoopBackOff | Liveness probe on wrong port causes restart loop | ★★☆ |
| 04 | ImagePullBackOff | Non-existent container image tag | ★☆☆ |
| 05 | Network Policy Blocking | Ingress policy with wrong label selector | ★★★ |
| 06 | Node Taint Issue | Maintenance taints prevent scheduling | ★★☆ |
| 07 | NSG Blocking Traffic | Azure NSG deny rule blocks LoadBalancer port 80 | ★★★ |

## Running a Lab

### Bash (Linux / macOS / WSL)
```bash
cd LABs/bash
chmod +x lab-01-dns-resolution.sh
./lab-01-dns-resolution.sh
```

### PowerShell (Windows)
```powershell
cd LABs\powershell
.\Lab-01-DnsResolution.ps1
```

## Interactive Menu

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
| `AKS_LAB_NODE_COUNT` | `2` | Nodes per cluster |
| `AKS_LAB_VM_SIZE` | `Standard_DS2_v2` | Node VM size |

Example:
```bash
export AKS_LAB_REGION=eastus
./lab-01-dns-resolution.sh
```

## Logs

All sessions are logged to `LABs/logs/` with timestamps, user actions, and validation results.

## Cost Estimate

Each lab creates a 2-node `Standard_DS2_v2` cluster (~$0.19/hr). A typical 1-hour lab session costs approximately **$0.20 USD**. Always clean up after finishing.

## File Structure

```
LABs/
├── README.md
├── bash/
│   ├── lib/
│   │   └── common.sh          # Shared framework
│   ├── lab-01-dns-resolution.sh
│   ├── lab-02-pod-pending.sh
│   ├── lab-03-crashloop.sh
│   ├── lab-04-image-pull.sh
│   ├── lab-05-network-policy.sh
│   ├── lab-06-node-taint.sh
│   └── lab-07-nsg-blocking.sh
├── powershell/
│   ├── lib/
│   │   └── Common.ps1         # Shared framework
│   ├── Lab-01-DnsResolution.ps1
│   ├── Lab-02-PodPending.ps1
│   ├── Lab-03-CrashLoop.ps1
│   ├── Lab-04-ImagePull.ps1
│   ├── Lab-05-NetworkPolicy.ps1
│   ├── Lab-06-NodeTaint.ps1
│   └── Lab-07-NsgBlocking.ps1
└── logs/
```

## Adding New Labs

1. Copy any existing lab script as a template
2. Define four functions: `deploy`, `validate`, `hint`, `solution`
3. Call `run_lab` (bash) or `Start-Lab` (PowerShell) at the bottom
4. The framework handles pre-checks, menu, logging, and cleanup
