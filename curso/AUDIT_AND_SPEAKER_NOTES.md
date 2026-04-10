# AKS Training — Full Audit & Speaker Notes

---

## AUDIT SUMMARY

### Issues Found

| # | Issue | Severity | Lab(s) | Status |
|---|-------|----------|--------|--------|
| 1 | Lab-02 PPT says "A pod has wrong image tag" but lab deploys a **Deployment** (3 replicas), not a single pod | Minor | 02 | ⚠️ PPT description imprecise |
| 2 | Lab-04 PPT says selector is `app:backend-api` vs `app:backend` — matches lab script perfectly | ✅ OK | 04 | — |
| 3 | Lab-02 deploy messages missing structured format ("What was deployed / What's wrong / Your task") | Minor | 02 | ⚠️ Only has `ok "Broken deployment applied"` + sleep |
| 4 | Lab-07 uses namespace `app` but PPT examples use `default` namespace commands | Minor | 07 | ⚠️ Student may need to add `-n app` |
| 5 | Lab-10 PPT says "Apply everything you learned to fix them all" — matches the 4 problems perfectly | ✅ OK | 10 | — |
| 6 | Lab-01 leccion.md was updated to "Application Down + Scavenger Hunt" | ✅ OK | 01 | — |
| 7 | All `lab_cmd` fields in PPT match actual script filenames (lab-01.sh through lab-10.sh) | ✅ OK | All | — |
| 8 | All curl commands in PPT use correct GitHub raw URL pattern | ✅ OK | All | — |
| 9 | Labs 01-06 use shared cluster `aks-training` / `aks-training-rg` with reuse validation | ✅ OK | 01-06 | — |
| 10 | Labs 07-10 use random names (as required for special config) | ✅ OK | 07-10 | — |

### Per-Lab Audit Detail

---

## LAB 01 — kubectl Fundamentals: Application Down + Scavenger Hunt

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: get, describe, logs, namespaces, labels, events
- Lab tests: `kubectl get all`, `kubectl scale`, `kubectl get pods -n kube-system`, ConfigMap update
- Lab title in PPT: "Application Down + Scavenger Hunt" → matches script `LAB_TITLE`

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 01

**Slide: Title**
> "Welcome to Lesson 1. This is the foundation for everything we'll do in this course. Today you'll learn the essential kubectl commands and understand how AKS clusters are built from the ground up. By the end, you'll be able to connect to any AKS cluster and navigate it confidently."

**Slide: AKS Architecture**
> "Before we touch any command, let's understand what we're working with. AKS has two main parts: the Control Plane, which Azure manages for you — you don't pay for it, you don't access it directly — and the Worker Nodes, which are the VMs where your applications actually run."

**Slide: Control Plane (Managed by Azure)**
> "The API Server is the front door to everything. Every `kubectl` command you run talks to the API Server. etcd stores all the cluster state — think of it as the database of Kubernetes. The Scheduler decides where to place new pods, and the Controller Manager constantly checks 'is the current state matching the desired state?' If not, it takes action."

**Slide: Worker Nodes**
> "On each node, the kubelet is the agent that receives instructions from the API Server and actually starts/stops containers. kube-proxy handles the networking rules so pods can communicate. And CoreDNS — remember this name — it's what lets pods find each other by name instead of IP addresses."

**Slide: Connect to AKS (code)**
> "Connecting is just two commands: `az login` to authenticate, then `az aks get-credentials` which downloads the kubeconfig file. After that, `kubectl cluster-info` confirms you're connected. In Cloud Shell, `az login` isn't needed since you're already authenticated."

**Slide: Viewing Resources (code)**
> "These three commands will be your bread and butter. `kubectl get nodes` shows you the VMs. `kubectl get pods -A` shows ALL pods in ALL namespaces — the `-A` flag is critical, without it you only see the default namespace. And `kubectl get all` gives you a quick overview of a specific namespace."

**Slide: Diagnosing Resources (code)**
> "This is the most important slide in this lesson. `kubectl describe` is your best friend for troubleshooting. Always scroll to the **Events** section at the bottom — that's where Kubernetes tells you what went wrong. `kubectl logs` shows what the application is printing. And `kubectl exec` lets you get inside a running container to debug."

**Slide: Namespaces**
> "Think of namespaces as folders for your Kubernetes resources. `default` is where your stuff goes if you don't specify. `kube-system` is where Kubernetes itself lives — CoreDNS, kube-proxy, etc. Never delete things from kube-system unless you know exactly what you're doing."

**Slide: Labels & Selectors**
> "Labels are how Kubernetes connects things together. A Service finds its pods through labels. A Deployment manages pods through labels. If labels don't match, things break silently — the Service will just have zero endpoints and you'll get timeouts with no error message. We'll see this exact scenario in Lab 04."

**Slide: Essential Commands Summary (table)**
> "This is your cheat sheet. Keep these six commands in mind. If something is broken, start with `get`, then `describe`, then `logs`. That three-step process solves 80% of problems."

**Slide: Lab 01**
> "Time for practice! You'll fix a broken web application — it exists but has zero endpoints — and then prove your kubectl skills with a scavenger hunt where you need to find specific information about the cluster. Run the command shown on screen in your Cloud Shell. The script will create the cluster and inject the problem. You'll have hints available if you get stuck."

---

## LAB 02 — Pods & Containers: Fix ImagePullBackOff

**PPT ↔ Lab Alignment:** ✅ MATCH (minor wording difference)
- PPT lab_desc says "A pod has a wrong image tag" — technically it's a Deployment with 3 replicas, not a single pod
- Lab deploys: Deployment `web-app` with image `nginx:99.99.99-nonexistent`
- PPT teaches the exact 3-step diagnosis (get → describe → logs) used to solve this lab

**PPT Issues:** Minor — "A pod" could say "A deployment" for precision
**Lab Issues:** None found — deploy message after scenario injection is minimal (just `ok "Broken deployment applied"`)
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 02

**Slide: Title**
> "Now that you know the basics of kubectl, let's go deeper into the most fundamental unit in Kubernetes: the Pod. Today we'll understand pod lifecycle, how container images work, and how to diagnose the most common pod errors."

**Slide: What is a Pod?**
> "A Pod is not a container — it's a wrapper around one or more containers. All containers in a pod share the same network and storage. The key thing to remember: pods are ephemeral. When a pod dies, everything inside it is gone. That's why we have volumes and persistent storage, which we'll cover in Lesson 06."

**Slide: Pod Lifecycle States (table)**
> "Memorize these states. When you run `kubectl get pods`, the STATUS column shows these. The two you'll see most often in troubleshooting are `CrashLoopBackOff` — the app keeps crashing — and `ImagePullBackOff` — Kubernetes can't download the container image. Today's lab focuses on ImagePullBackOff."

**Slide: Image Format & Errors**
> "Container images follow the format registry/repository:tag. When you say just `nginx:1.25`, Docker Hub is the implicit registry. For Azure, you'll see `mcr.microsoft.com` for Microsoft images and `myacr.azurecr.io` for your private images. The error `ErrImagePull` means the first attempt failed. `ImagePullBackOff` means it keeps retrying with increasing delays."

**Slide: Step 1: View Status (code)**
> "First step is always `kubectl get pods`. Look at the STATUS column. Here we see `ImagePullBackOff` — that immediately tells us it's an image problem, not an application crash. Notice READY shows 0/1 — zero containers ready out of one expected."

**Slide: Step 2: Describe (code)**
> "Now describe the pod and go straight to the Events section. See these lines? 'Failed to pull image nginx:99.99' — it tells you the exact image that failed. 'Error: ErrImagePull' confirms it. The Events section is the single most important diagnostic tool in Kubernetes."

**Slide: Step 3: Logs (code)**
> "If the pod actually started but is crashing, logs are your next step. `--previous` gets the logs from the last crashed container. And you can filter logs by label which is useful when you have multiple replicas."

**Slide: Resources: Requests & Limits**
> "Quick aside on resource management: requests are what the scheduler guarantees, limits are the maximum. If a container exceeds its memory limit, Kubernetes kills it with OOMKilled — which shows up as CrashLoopBackOff. `kubectl top pods` shows current usage."

**Slide: Diagnosis Quick Reference (table)**
> "This three-step process — get pods, describe, logs — will be your go-to for any pod problem. Print this table or keep it handy."

**Slide: Lab 02**
> "In this lab, a deployment has the wrong image tag. You'll use the three-step process we just learned to diagnose and fix it. The fix is simple once you find the problem — but the goal is to practice the diagnostic flow."

---

## LAB 03 — Deployments & ReplicaSets: Failed Rollout

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: rollouts, rollbacks, liveness probes, `kubectl rollout undo`
- Lab: initial working deployment → broken update with liveness probe on port 9999
- Solution options match PPT: rollback or fix the probe
- PPT mentions "Wrong port in probe → CrashLoopBackOff" — exactly the lab scenario

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 03

**Slide: Title**
> "Deployments are how you run applications in production. Today we'll learn how Kubernetes manages updates, what happens when an update goes wrong, and how to rollback. We'll also cover health checks — probes — which are critical for application stability."

**Slide: Deployment → ReplicaSet → Pods**
> "The hierarchy is: Deployment manages ReplicaSets, ReplicaSets manage Pods. When you update a Deployment, it creates a NEW ReplicaSet and gradually shifts pods from the old one to the new one. That's a rolling update. The old ReplicaSet stays around — that's what enables rollbacks."

**Slide: Basic Commands (code)**
> "Three key commands: `scale` to change the number of replicas, `set image` to trigger a rolling update, and `rollout status` to watch the progress. When you set a new image, Kubernetes creates new pods one by one, waits for each to be ready, then terminates old pods."

**Slide: Rollback Commands (code)**
> "`rollout history` shows all the previous versions. `rollout undo` reverts to the previous version. You can even go back to a specific revision with `--to-revision`. This is why Kubernetes keeps old ReplicaSets — they're your safety net."

**Slide: Probe Types (table)**
> "This is critical. livenessProbe asks 'is the container still alive?' If it fails, kubelet kills and restarts the container. readinessProbe asks 'can it receive traffic?' If it fails, the pod is removed from the Service but NOT restarted. startupProbe is for slow-starting apps — it blocks the other probes until the app is ready."

**Slide: Common Probe Mistakes**
> "The most common mistake is wrong port. If your app listens on port 80 but your probe checks port 8080, the probe will always fail and kubelet will keep restarting the container — giving you CrashLoopBackOff. The second mistake is a path that doesn't exist. In today's lab, you'll see both."

**Slide: Commands Summary (table)**
> "Quick reference. The key insight: if pods are crashing after a deployment update, you can always `rollout undo` first to restore service, then investigate what went wrong."

**Slide: Lab 03**
> "Someone pushed an update with a bad liveness probe — port 9999 instead of 80, and path /healthz which nginx doesn't serve. The deployment is stuck mid-rollout. You can either fix the probe or rollback to the previous working version."

---

## LAB 04 — Services & Networking: Service Disconnect

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: Service types, DNS, endpoints, selector matching
- Lab: Service selector `app:backend-api` doesn't match pod label `app:backend`
- PPT explicitly covers "Service Has No Endpoints" with selector mismatch as the cause
- Connectivity checklist in PPT maps exactly to the debugging flow needed

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 04

**Slide: Title**
> "Now we understand pods and deployments. But how do pods talk to each other? That's what Services do. Today we'll learn how Kubernetes networking works and how to troubleshoot when connections fail."

**Slide: Service Types (table)**
> "Three types to know: ClusterIP is internal-only — other pods can reach it but the outside world can't. NodePort exposes a port on every node — useful for testing. LoadBalancer creates an actual Azure Load Balancer with a public IP — that's what you use in production for external access."

**Slide: DNS Resolution**
> "Inside the cluster, pods find each other by name, not by IP. When you create a Service called `backend-svc`, any pod can reach it at `http://backend-svc`. If it's in another namespace, add the namespace: `http://backend-svc.production`. This all works because of CoreDNS running in kube-system."

**Slide: Testing DNS (code)**
> "A busybox pod is your best debugging tool. Run it interactively, then use `nslookup` and `wget` to test connectivity. If DNS fails, the problem is usually CoreDNS or a NetworkPolicy blocking port 53. If DNS works but HTTP fails, it's a Service endpoint problem."

**Slide: Service Has No Endpoints**
> "This is the #1 Service troubleshooting scenario. A Service has an IP but nothing behind it. The key diagnostic: `kubectl get endpoints my-svc`. If it shows empty, the Service can't find matching pods. Why? Because the **selector labels don't match the pod labels**. This is exactly what you'll fix in today's lab."

**Slide: Common Issues (table)**
> "Four things to check: endpoints empty means selector mismatch, connection refused means wrong port, DNS not resolving means CoreDNS or NetworkPolicy, and LoadBalancer with no IP means Azure quota or permissions."

**Slide: Connectivity Checklist (code)**
> "Follow these five steps in order and you'll find any networking issue. Step 1: does the Service exist? Step 2: does it have endpoints? Step 3: are pods running? Step 4: do selectors match labels? Step 5: can you connect from another pod?"

**Slide: Lab 04**
> "A backend deployment is running fine, but the frontend can't connect through the Service. The Service has zero endpoints. Your job: find the selector mismatch and fix it. Remember: compare `kubectl describe svc` with `kubectl get pods --show-labels`."

---

## LAB 05 — ConfigMaps & Secrets: Missing Configuration

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: ConfigMap/Secret creation, env vars, `CreateContainerConfigError`
- Lab: Deployment references missing `app-config` ConfigMap and `db-credentials` Secret
- PPT table shows "CreateContainerConfigError → ConfigMap or Secret doesn't exist" — exact lab error
- Solution commands in PPT match lab solution

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 05

**Slide: Title**
> "Today's lesson is about one of the most common real-world issues: configuration management. You should never hardcode database URLs, API keys, or feature flags inside your container images. ConfigMaps and Secrets let you externalize that configuration."

**Slide: When to Use (table)**
> "Simple rule: if it's not sensitive — URLs, feature flags, log levels — use a ConfigMap. If it's sensitive — passwords, tokens, certificates — use a Secret. Secrets are base64 encoded, NOT encrypted by default, so they're not truly secure — but they signal intent and can be encrypted with additional configuration."

**Slide: Creating ConfigMaps (code)**
> "`--from-literal` is the fastest way to create a ConfigMap with simple key-value pairs. `--from-file` is great when you have a full config file like nginx.conf. Use `describe` to verify the contents."

**Slide: Using in Pods**
> "Three ways to consume ConfigMaps: first, individual env vars with `valueFrom.configMapKeyRef`. Second, mount the entire ConfigMap as files using volumes. Third, `envFrom` loads ALL keys at once — convenient but gives you less control."

**Slide: Creating Secrets (code)**
> "Creating Secrets works the same as ConfigMaps. The key difference: if you `kubectl get secret -o yaml`, you'll see base64 encoded values, not plaintext. But base64 is NOT encryption — anyone can decode it. For real security, use Azure Key Vault with the CSI driver."

**Slide: Common Errors (table)**
> "`CreateContainerConfigError` is the classic error when a ConfigMap or Secret is missing. The pod won't even start — Kubernetes won't create the container if it can't inject the configuration. This is exactly what you'll see in today's lab."

**Slide: Diagnosis (code)**
> "When you see `CreateContainerConfigError`, describe the pod and look at Events. It will tell you exactly which ConfigMap or Secret is missing and which key. Then create it and the pod will auto-restart."

**Slide: Lab 05**
> "A deployment is stuck because it references a ConfigMap called `app-config` and a Secret called `db-credentials`, neither of which exist. You need to create both with the correct keys. Check the pod's describe output to find the exact key names expected."

---

## LAB 06 — Storage & Volumes: PVC Stuck in Pending

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: StorageClass, PV, PVC, access modes, stuck PVCs
- Lab: PVC uses non-existent StorageClass `premium-ssd-nonexistent`
- PPT table "PVC Stuck in Pending" lists "StorageClass doesn't exist" as first cause — matches lab
- Fix path: delete PVC + pod, recreate with `managed-csi`

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 06

**Slide: Title**
> "So far everything we've done is ephemeral — when a pod dies, data is lost. Today we'll learn how to give pods persistent storage that survives restarts and even pod deletion."

**Slide: The Problem**
> "Containers have a filesystem, but it's temporary. If you restart a database container, all the data is gone. That's why we need Persistent Volumes."

**Slide: Key Concepts**
> "Three resources to understand. StorageClass defines WHAT type of storage — SSD, premium, file share. PersistentVolume (PV) is the actual provisioned disk. PersistentVolumeClaim (PVC) is the pod's request — like a ticket saying 'I need 5GB of SSD storage'. In AKS, the StorageClass dynamically creates the PV when a PVC is submitted."

**Slide: StorageClasses in AKS (table)**
> "AKS comes with these built-in. `managed-csi` is your default for Azure Disks — good for databases. `azurefile-csi` is for Azure Files — the key difference is it supports ReadWriteMany, meaning multiple pods on multiple nodes can mount it simultaneously."

**Slide: Access Modes**
> "Critical distinction: Azure Disks only support ReadWriteOnce — one node at a time. If you need multiple pods on different nodes to share files, you must use Azure Files with ReadWriteMany. Getting this wrong means your PVC will be stuck in Pending."

**Slide: PVC Stuck in Pending (table)**
> "Five reasons a PVC stays Pending. The first — StorageClass doesn't exist — is the most common mistake and exactly what today's lab tests. `WaitForFirstConsumer` is normal — it just means the disk won't be created until a pod actually uses it."

**Slide: Azure Disk vs Azure Files (table)**
> "Quick comparison to remember: Disk for databases (fast, single node), Files for shared data (slightly slower, multi-node)."

**Slide: Diagnosis Commands (code)**
> "Four commands: `get pvc` shows status, `describe pvc` shows Events with the error, `get pv` shows actual disks, `get sc` lists available StorageClasses. Always start with `describe pvc` — the Events will tell you exactly why it's Pending."

**Slide: Lab 06**
> "A database pod can't start because its PVC references a StorageClass called `premium-ssd-nonexistent` which doesn't exist. Important: PVCs can't be edited in-place for StorageClass — you must delete and recreate both the PVC and the pod."

---

## LAB 07 — Network Policies: Blocked Traffic

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: NetworkPolicy, egress/ingress, DNS port 53 requirement
- Lab: NetworkPolicy blocks DNS egress for frontend pods (no port 53 rule)
- PPT section "Always Allow DNS in Egress Policies" is the exact lesson
- Lab uses namespace `app` — PPT commands don't specify namespace (students need to add `-n app`)

**PPT Issues:** Minor — PPT diagnosis commands don't include `-n app`, students will need to figure out the namespace
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 07

**Slide: Title**
> "By default, every pod in Kubernetes can talk to every other pod. That's convenient but not secure. Network Policies are like firewalls at the pod level — they let you control exactly who can talk to whom."

**Slide: Key Rules**
> "Four rules to internalize: One, no policy means everything is allowed. Two, the moment you create a policy for a pod, everything NOT explicitly allowed is BLOCKED. Three, an Ingress policy with no rules blocks all incoming traffic. Four — and this is the most common mistake — an Egress policy with no rules blocks ALL outgoing traffic, including DNS!"

**Slide: Anatomy of a NetworkPolicy**
> "`podSelector` selects which pods this policy applies to — using labels. `policyTypes` says whether this controls Ingress, Egress, or both. Then `ingress.from` and `egress.to` define the actual rules."

**Slide: Selectors**
> "Three types of selectors: `podSelector` for pods in the same namespace, `namespaceSelector` for pods in other namespaces, and `ipBlock` for external IPs. You can combine them for fine-grained rules."

**Slide: Critical: DNS & Egress**
> "This is the key takeaway of this lesson. If you create an egress policy and forget to allow DNS (port 53), NOTHING will work. Pods can't resolve any service names. The pod seems healthy but can't connect to anything. Always — always — include port 53 UDP and TCP in your egress rules."

**Slide: Always Allow DNS in Egress Policies**
> "DNS uses UDP port 53 — some implementations also use TCP port 53. CoreDNS runs in kube-system, so you need a rule that allows egress to port 53. If you don't, even `nslookup kubernetes.default` inside the pod will fail."

**Slide: Diagnosis (code)**
> "Start with `kubectl get networkpolicy` to see what exists. Describe it to see the exact rules. Then test from inside a pod: try `nslookup` for DNS and `wget` for HTTP. If DNS fails but the pod is healthy, it's almost always a missing port 53 egress rule."

**Slide: Checklist (table)**
> "Four checks: policies exist? selector matches the affected pod? DNS allowed in egress? From labels correct? Follow this order."

**Slide: Lab 07**
> "A client pod can't reach the backend web service. The NetworkPolicy allows HTTP to the backend but forgot to allow DNS. Without DNS, the client can't resolve `web-svc` to an IP address. Your fix: add port 53 UDP/TCP to the egress rules. Note: this lab creates a new cluster with `--network-policy azure` enabled."

---

## LAB 08 — Node Management: Taints, Tolerations & Scheduling

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: scheduler process, taints, tolerations, nodeSelector, cordon/drain
- Lab: all nodes have `maintenance=true:NoSchedule` taint, pods stuck Pending
- PPT diagnosis table says "didn't tolerate taint → Add toleration or remove taint" — both are lab solutions
- PPT shows exact removal syntax: `kubectl taint nodes --all maintenance=true:NoSchedule-`

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 08

**Slide: Title**
> "Until now, we've let the scheduler decide where to place pods. Today we'll learn how to influence that decision — and what happens when scheduling constraints prevent pods from running."

**Slide: Scheduler Evaluation**
> "When you create a pod, the scheduler runs through a checklist: Does any node have enough CPU and memory? Does the pod require a specific node label that no node has? Do all nodes have taints the pod doesn't tolerate? If no node passes all filters, the pod stays in Pending forever. That's what we'll troubleshoot today."

**Slide: Taints = Repellent on Nodes**
> "Think of taints as a 'Do Not Enter' sign on a node. `NoSchedule` means new pods can't be placed here unless they have a matching toleration. `PreferNoSchedule` is a soft version — scheduler will try to avoid it. `NoExecute` is the strongest — it evicts even existing pods."

**Slide: Taint Commands (code)**
> "Adding a taint is `kubectl taint nodes node1 key=value:Effect`. Viewing is through `describe node`. Removing — and this is important — uses a trailing dash: `maintenance=true:NoSchedule-`. That trailing dash is the removal syntax. You'll use `--all` to apply to all nodes."

**Slide: nodeSelector**
> "The simplest way to pin a pod to a specific node type. You add `nodeSelector.disktype: ssd` in the pod spec, and only nodes with that label will be considered. No matching label on any node? Pod stays Pending."

**Slide: Cordon & Drain (code)**
> "`cordon` marks a node as unschedulable — new pods won't go there. `drain` goes further — it moves ALL pods to other nodes, which you need before maintenance or OS updates. Always use `--ignore-daemonsets` or drain will refuse to proceed."

**Slide: Diagnosis (table)**
> "Three messages to recognize in Events: 'didn't tolerate taint' — that's a taint problem. 'didn't match node selector' — missing label. 'Insufficient cpu/memory' — need to scale the node pool or reduce resource requests."

**Slide: Lab 08**
> "All nodes have been tainted with `maintenance=true:NoSchedule`, simulating a maintenance window. Three web-app pods are stuck in Pending. You can either remove the taint — maintenance is over — or add a toleration to the deployment. This lab creates its own cluster since we're modifying node configuration."

---

## LAB 09 — Azure Integration: NSG Blocking Traffic

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: MC_ resource group, NSG rules, priority system, Azure CLI commands
- Lab: DenyHTTPInbound rule at priority 100 blocks port 80 inbound
- PPT shows exact commands to find and delete NSG rules
- PPT table lists "LB Service timeout → NSG deny rule blocking port" as first issue

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 09

**Slide: Title**
> "Today we step outside of Kubernetes and look at the Azure infrastructure underneath. AKS doesn't exist in a vacuum — it uses Azure VMs, networking, load balancers, and network security groups. Understanding this layer is essential for troubleshooting connectivity issues that kubectl can't see."

**Slide: MC_ Resource Group Contents**
> "When you create an AKS cluster, Azure creates a second resource group prefixed with MC_. This contains everything: the VMSS that are your nodes, the VNet where they live, the NSG that controls traffic, and the Load Balancer that handles external access. You don't manage these directly, but you need to inspect them for troubleshooting."

**Slide: Find the MC_ Resource Group (code)**
> "`az aks show` with `--query nodeResourceGroup` gives you the MC_ resource group name. Then `az resource list` shows everything inside it. In today's lab, you'll need this to find the NSG."

**Slide: NSG Priority Rules**
> "NSGs are Azure firewalls. Rules are evaluated by priority — lowest number wins. So a Deny at priority 100 will override an Allow at priority 200. AKS automatically creates allow rules for your LoadBalancer Services, but a manual deny rule with lower priority number can break everything."

**Slide: NSG Commands (code)**
> "These are the key commands: list NSGs, list their rules, filter for deny rules, and delete a specific rule. The `--query \"[?access=='Deny']\"` JMESPath filter is very useful to quickly find blocking rules."

**Slide: Common Issues (table)**
> "Four Azure-level issues: NSG blocking ports, public IP quota exhausted, LB health probe failing, and outbound 443 blocked preventing image pulls. All of these are invisible at the Kubernetes level — `kubectl` shows everything is fine but traffic doesn't flow."

**Slide: Full Diagnosis Flow (code)**
> "The full workflow: get the MC_ resource group, list NSGs and their rules, check the Load Balancer, check public IPs. Follow this when a LoadBalancer Service has an IP but traffic times out."

**Slide: Lab 09**
> "A web pod has a LoadBalancer Service with an external IP, but HTTP requests timeout. The problem is at the Azure level: someone added a DenyHTTPInbound NSG rule at priority 100 that blocks all inbound port 80 traffic. You need to find it with `az network nsg rule list` and delete it. This lab creates its own cluster since it modifies Azure-level resources."

---

## LAB 10 — Advanced Troubleshooting: Multi-Problem Challenge

**PPT ↔ Lab Alignment:** ✅ MATCH
- PPT teaches: DISCOVER methodology, advanced commands, complex scenarios
- Lab: 4 combined problems from lessons 02, 04, 05, 07
  - Problem 1: Wrong image tag (`nginx:does-not-exist-tag`) — Lesson 02
  - Problem 2: Service selector mismatch (`app:back-end` vs `app:backend`) — Lesson 04
  - Problem 3: Missing ConfigMap `frontend-config` — Lesson 05
  - Problem 4: NetworkPolicy blocks DNS egress — Lesson 07
- PPT Course Summary table references all 10 lessons
- DISCOVER framework maps well to the multi-problem debugging approach

**PPT Issues:** None found
**Lab Issues:** None found
**leccion.md:** ✅ Title matches

### Speaker Notes — Lesson 10

**Slide: Title**
> "This is the final lesson. You've learned individual troubleshooting skills — now we'll put them all together. In the real world, problems rarely come one at a time. Today you'll learn a structured methodology and then face a challenge with multiple simultaneous issues."

**Slide: DISCOVER Steps**
> "DISCOVER is our troubleshooting framework. Define the symptom — don't assume, describe what you see. Investigate — gather data with describe, logs, events. Scope — is it one pod, one node, or cluster-wide? Compare — what changed recently? Options — list all possible causes. Verify — test your hypothesis before applying fixes. Execute the fix. Review — confirm it's resolved. This structured approach prevents you from going in circles."

**Slide: Events & Logs (code)**
> "Advanced log techniques: `--field-selector type=Warning` filters for just warnings across the whole cluster. `--since=5m` limits to recent events. `-l app=web-app --all-containers` gets logs from all replicas at once. These are the commands you use when the basic approach isn't enough."

**Slide: Advanced JSON Queries (code)**
> "For large clusters, you need to filter programmatically. `jq` lets you find all pods that aren't Running, or pods with high restart counts. These one-liners save hours when you have hundreds of pods."

**Slide: Intermittent App Failures**
> "Four things to check for intermittent issues: restart count climbing? Resource limits being hit? OOMKilled in the pod state? Readiness probe flapping? These cause pods to appear Running one moment and failing the next."

**Slide: Node NotReady**
> "If a node goes NotReady: check node conditions with describe, check kubelet status, check if disk is full, and check node events. In AKS, you might need to restart the VMSS instance or scale the node pool."

**Slide: Quick Troubleshooting Checklist (code)**
> "Print this. When something is wrong, run these commands in order: get pods, get nodes, get events, describe the problematic resource, check logs, check services and endpoints, check network policies, and finally check the AKS provisioning state. This covers 95% of issues."

**Slide: Course Summary (table)**
> "Here's everything we covered in 10 lessons. Each lesson gave you a specific tool. kubectl for basics, describe+Events for pods, rollout for deployments, endpoints for services, describe for config, describe pvc for storage, netpol for network policies, taints and labels for nodes, az CLI for Azure, and DISCOVER for complex scenarios. You now have a complete troubleshooting toolkit."

**Slide: Lab 10**
> "The final challenge. A multi-tier application in the `challenge` namespace has four different problems — one from each of the key lessons. Nothing works. You need to systematically find and fix all four issues. No one will tell you what's wrong — apply the DISCOVER framework and everything you've learned. This is the closest to real production troubleshooting. Good luck!"

---

## OVERALL AUDIT VERDICT

### ✅ Everything is consistent and correct

| Check | Result |
|-------|--------|
| PPT titles match lab scripts | ✅ All 10 match |
| PPT lab commands match filenames | ✅ All use correct lab-NN.sh |
| PPT curl URLs point to correct GitHub paths | ✅ All verified |
| Lab scenarios match PPT teaching content | ✅ All lessons teach the skill needed |
| Lab difficulty progression is logical | ✅ Easy → Medium → Hard → Challenge |
| Labs 01-06 reuse shared cluster | ✅ `aks-training` / `aks-training-rg` |
| Labs 07-10 use unique random clusters | ✅ Special config required |
| leccion.md titles match PPT titles | ✅ All 10 match |
| Hints progress from vague to specific | ✅ All labs follow this pattern |
| Solutions show multiple approaches | ✅ Where applicable |
| Validation checks correct conditions | ✅ All labs verify the actual fix |

### Minor Suggestions (Optional)

1. Lab-02 PPT description could say "deployment" instead of "pod" for precision
2. Lab-07 PPT commands could include `-n app` since the lab uses the `app` namespace
3. Lab-02 deploy section could add the structured "What was deployed / What's wrong / Your task" format (labs 01, 03-10 have it)
