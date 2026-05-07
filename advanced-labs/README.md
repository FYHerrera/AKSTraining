# Advanced Labs — CKA Exam Practice

32 hands-on labs that mirror the real **Certified Kubernetes Administrator (CKA)** practical scenarios. Each lab follows the same `deploy → validate → hint → solution` framework as the rest of this repo, but **does not provision an AKS cluster**. Instead, every lab runs against the **current `kubectl` context**, so you can use:

- An existing AKS cluster,
- A local `kind` / `minikube` cluster,
- [Killercoda](https://killercoda.com/) playgrounds,
- Any other Kubernetes cluster.

```bash
# Quickest local setup
kind create cluster --name cka-practice
cd advanced-labs
chmod +x lab-*.sh
./lab-01-create-pv.sh
```

Each lab creates an isolated namespace `cka-labXX` and offers to delete it on exit.

## Catalog

| # | Topic | Script | CKA skill area |
|---|-------|--------|----------------|
| 01 | Create a PersistentVolume | [lab-01-create-pv.sh](lab-01-create-pv.sh) | Storage |
| 02 | Backup & Restore etcd | [lab-02-etcd-backup-restore.sh](lab-02-etcd-backup-restore.sh) | Cluster admin |
| 03 | Create Ingress + IngressClass | [lab-03-ingress-and-class.sh](lab-03-ingress-and-class.sh) | Services & Networking |
| 04 | Pod logs grep to file | [lab-04-pod-logs-to-file.sh](lab-04-pod-logs-to-file.sh) | Logging / Monitoring |
| 05 | NetworkPolicy by namespace + port | [lab-05-network-policy.sh](lab-05-network-policy.sh) | Services & Networking |
| 06 | Upgrade control plane (kubeadm) | [lab-06-kubeadm-upgrade.sh](lab-06-kubeadm-upgrade.sh) | Cluster lifecycle |
| 07 | Expose port by name (NodePort) | [lab-07-expose-port-by-name.sh](lab-07-expose-port-by-name.sh) | Services |
| 08 | Sidecar with shared volume | [lab-08-sidecar-shared-volume.sh](lab-08-sidecar-shared-volume.sh) | Workloads |
| 09 | Create PVC, resize, record | [lab-09-pvc-resize.sh](lab-09-pvc-resize.sh) | Storage |
| 10 | Fix node Not Ready (kubelet) | [lab-10-node-not-ready.sh](lab-10-node-not-ready.sh) | Troubleshooting |
| 11 | Count Ready, schedulable nodes | [lab-11-ready-schedulable-nodes.sh](lab-11-ready-schedulable-nodes.sh) | Cluster admin |
| 12 | ClusterRole + namespaced RoleBinding | [lab-12-clusterrole-rolebinding.sh](lab-12-clusterrole-rolebinding.sh) | RBAC |
| 13 | Pod with two containers | [lab-13-two-container-pod.sh](lab-13-two-container-pod.sh) | Workloads |
| 14 | Top CPU pod by label | [lab-14-top-cpu-pod.sh](lab-14-top-cpu-pod.sh) | Logging / Monitoring |
| 15 | nodeSelector scheduling | [lab-15-node-selector.sh](lab-15-node-selector.sh) | Scheduling |
| 16 | Drain a node | [lab-16-drain-node.sh](lab-16-drain-node.sh) | Cluster admin |
| 17 | Scale a Deployment | [lab-17-scale-deployment.sh](lab-17-scale-deployment.sh) | Workloads |
| 18 | HA cluster setup with kubeadm | [lab-18-ha-cluster-setup.sh](lab-18-ha-cluster-setup.sh) | Cluster lifecycle |
| 19 | Default StorageClass | [lab-19-storage-class.sh](lab-19-storage-class.sh) | Storage |
| 20 | ResourceQuota + Pod requests | [lab-20-resource-quota.sh](lab-20-resource-quota.sh) | Workloads |
| 21 | Rolling update + rollback | [lab-21-rolling-update-rollback.sh](lab-21-rolling-update-rollback.sh) | Workloads |
| 22 | SecurityContext + node affinity | [lab-22-security-context-affinity.sh](lab-22-security-context-affinity.sh) | Security / Scheduling |
| 23 | Helm template + install | [lab-23-helm-install.sh](lab-23-helm-install.sh) | Workloads |
| 24 | Migrate Ingress → Gateway API | [lab-24-gateway-api.sh](lab-24-gateway-api.sh) | Services & Networking |
| 25 | Install & fix CNI (Flannel CIDR) | [lab-25-cni-flannel.sh](lab-25-cni-flannel.sh) | Cluster lifecycle |
| 26 | JSONPath: cert-manager CRDs | [lab-26-jsonpath-crd.sh](lab-26-jsonpath-crd.sh) | kubectl power-user |
| 27 | Node / kubelet troubleshooting | [lab-27-node-kubelet-troubleshoot.sh](lab-27-node-kubelet-troubleshoot.sh) | Troubleshooting |
| 28 | Edit ConfigMap (TLSv1.3 only) | [lab-28-configmap-tls13.sh](lab-28-configmap-tls13.sh) | Workloads |
| 29 | HorizontalPodAutoscaler | [lab-29-hpa.sh](lab-29-hpa.sh) | Workloads |
| 30 | PriorityClass + Deployment patch | [lab-30-priority-class.sh](lab-30-priority-class.sh) | Scheduling |
| 31 | Prepare node for kubeadm | [lab-31-prepare-node-kubeadm.sh](lab-31-prepare-node-kubeadm.sh) | Cluster lifecycle |
| 32 | Sidecar tail logs | [lab-32-sidecar-logs.sh](lab-32-sidecar-logs.sh) | Workloads |

> Scenario #33 from the source PDF is just a link to extra YouTube content and has no lab.

## Lab anatomy

Each script defines four functions and calls `run_lab`:

```bash
deploy()    { ... # create the broken/initial state in cluster ... }
validate()  { ... # automated check; return 0 on success ... }
hint()      { ... # progressive hints based on $1 attempt count ... }
solution()  { ... # full reference fix ... }
run_lab "<name>" "<title>" "<description>" deploy validate hint solution
```

## Notes on host-level scenarios

A few CKA tasks are inherently *node/host* operations that cannot be performed against an arbitrary kubectl context (etcd backup on a jump server, `kubeadm upgrade`, fixing systemd `kubelet`, installing a CNI on bare nodes, preparing a Linux box with `cri-dockerd`). For these, the lab:

1. **Documents** the exact procedure expected by the exam, with the right commands.
2. **Simulates** what can be simulated inside the cluster (e.g., lab 02 spins up a self-managed `etcd` Pod so you can practise `etcdctl snapshot save/restore` end-to-end).
3. **Validates** what the lab can verify (file produced, parameters correct, etc.).

These labs are clearly marked in their banner with `[Host-level scenario – simulated in cluster]`.
