# Lección 10 – Troubleshooting Avanzado: Metodología y Escenarios Complejos

## Objetivos
- Aplicar una metodología estructurada de troubleshooting
- Combinar todo lo aprendido en escenarios complejos
- Conocer herramientas y comandos avanzados

---

## 1. Metodología de Troubleshooting

### El Framework DISCOVER

```
D - Define      → ¿Cuál es el síntoma exacto?
I - Investigate  → Recopilar información (logs, events, describe)
S - Scope        → ¿Afecta un pod, un nodo, todo el cluster?
C - Compare      → ¿Qué cambió? ¿Cuándo empezó?
O - Options      → ¿Cuáles son las posibles causas?
V - Verify       → Probar la hipótesis
E - Execute      → Aplicar el fix
R - Review       → Confirmar que se resolvió
```

---

## 2. Flujo de Diagnóstico Práctico

```
Reporte: "La app no funciona"
           │
           ▼
    ¿Los pods están Running?
    kubectl get pods
           │
     ┌─────┴─────┐
     NO           SÍ
     │            │
     ▼            ▼
  ¿Estado?     ¿El service tiene endpoints?
  Pending →    kubectl get endpoints
  ImagePull →    │
  CrashLoop →  ┌┴────┐
  (ver lecciones  NO    SÍ
   02, 03, 08)   │     │
                 ▼     ▼
          ¿Selector   ¿Se puede conectar
          coincide?   desde otro pod?
          Labels vs     │
          Service    ┌──┴──┐
          (lección    NO    SÍ
           04)       │     │
                     ▼     ▼
              NetworkPolicy?  ¿Externo falla?
              NSG?           LB/NSG/DNS
              (lección       (lección 09)
               07, 09)
```

---

## 3. Comandos Avanzados para Diagnóstico

### Eventos (oro puro para troubleshooting)
```bash
# Todos los eventos, ordenados por tiempo
kubectl get events --sort-by='.lastTimestamp' -A

# Solo warnings
kubectl get events --field-selector type=Warning -A

# Eventos de un pod específico
kubectl get events --field-selector involvedObject.name=<pod>

# Eventos de los últimos 30 minutos
kubectl get events --sort-by='.lastTimestamp' | \
  awk -v d="$(date -d '30 minutes ago' '+%Y-%m-%dT%H:%M')" '$1 >= d'
```

### Logs avanzados
```bash
# Logs de todos los pods con un label
kubectl logs -l app=web-app --all-containers=true

# Follow logs en tiempo real
kubectl logs -f <pod>

# Logs de los últimos 5 minutos
kubectl logs <pod> --since=5m

# Logs de un init container
kubectl logs <pod> -c <init-container-name>

# Logs del container anterior (crasheado)
kubectl logs <pod> --previous
```

### JSON queries potentes
```bash
# Pods que NO están Running
kubectl get pods -A -o json | jq '.items[] |
  select(.status.phase != "Running") |
  {name: .metadata.name, ns: .metadata.namespace, status: .status.phase}'

# Pods con restart count > 5
kubectl get pods -A -o json | jq '.items[] |
  select(.status.containerStatuses[]?.restartCount > 5) |
  {name: .metadata.name, restarts: .status.containerStatuses[0].restartCount}'

# Nodos con condiciones problemáticas
kubectl get nodes -o json | jq '.items[] |
  {name: .metadata.name, conditions: [.status.conditions[] |
  select(.status != "False" and .type != "Ready") | .type]}'
```

---

## 4. Herramientas de Debug

### Debug Pod (Kubernetes 1.23+)
```bash
# Crear un pod de debug que se adjunta a un nodo
kubectl debug node/<node-name> -it --image=busybox

# Debug un pod existente (crea container ephemeral)
kubectl debug <pod> -it --image=busybox --target=<container>
```

### Netshoot (herramienta de red completa)
```bash
# Pod con todas las herramientas de red
kubectl run debug-net --rm -it --image=nicolaka/netshoot -- /bin/bash

# Dentro de netshoot:
curl http://backend-svc
nslookup backend-svc
tcpdump -i eth0
traceroute <ip>
ss -tulnp
iperf3 -c <ip>
```

---

## 5. Problemas Comunes Multi-capa

### Escenario: App intermitente

```bash
# 1. ¿Pods restarting?
kubectl get pods -l app=web --sort-by='.status.containerStatuses[0].restartCount'

# 2. ¿Resource limits?
kubectl top pods -l app=web
kubectl describe pod <pod> | grep -A3 "Limits"

# 3. ¿OOMKilled?
kubectl get pods -o json | jq '.items[].status.containerStatuses[] |
  select(.lastState.terminated.reason == "OOMKilled") |
  {name: .name, reason: .lastState.terminated.reason}'

# 4. ¿Readiness probe fallando intermitente?
kubectl describe pod <pod> | grep -A10 "Conditions:"
```

### Escenario: Nodo NotReady

```bash
# 1. Status del nodo
kubectl describe node <node> | grep -A10 Conditions

# 2. ¿Kubelet funcionando?
# (Desde Azure Portal: Run Command, o SSH al nodo)
systemctl status kubelet

# 3. ¿Disco lleno?
kubectl describe node <node> | grep -A5 "Allocated resources"

# 4. ¿Eventos del nodo?
kubectl get events --field-selector involvedObject.name=<node>
```

### Escenario: Todo estaba bien y dejó de funcionar

```bash
# 1. ¿Cuándo empezó?
kubectl get events --sort-by='.lastTimestamp' -A | tail -30

# 2. ¿Hubo un deployment reciente?
kubectl rollout history deployment/<name>

# 3. ¿Cambió algo en Azure?
az monitor activity-log list -g <rg> --start-time 2024-01-01T00:00:00Z \
  --query "[].{time:eventTimestamp, op:operationName.localizedValue, status:status.value}" -o table

# 4. ¿Hay algún upgrade en progreso?
az aks show -g <rg> -n <cluster> --query provisioningState -o tsv
```

---

## 6. Comandos Azure para Troubleshooting

```bash
# Estado del cluster
az aks show -g <rg> -n <cluster> --query provisioningState -o tsv

# Activity log (qué pasó en Azure)
az monitor activity-log list -g <rg> --offset 1h -o table

# Node pool status
az aks nodepool list -g <rg> --cluster-name <cluster> \
  --query "[].{name:name, status:provisioningState, count:count, vmSize:vmSize}" -o table

# VMSS instances
az vmss list-instances -g <mc-rg> -n <vmss> -o table

# AKS diagnostics
az aks kollect -g <rg> -n <cluster> --storage-account <sa>
```

---

## 7. Checklist de Troubleshooting Rápido

```
□ kubectl get pods -A (¿todo Running?)
□ kubectl get nodes -o wide (¿todos Ready?)
□ kubectl get events --sort-by='.lastTimestamp' (¿errores recientes?)
□ kubectl describe pod <problem-pod> (Events section)
□ kubectl logs <pod> --previous (si crasheó)
□ kubectl get svc,endpoints (¿servicios conectados?)
□ kubectl get netpol (¿políticas bloqueando?)
□ az aks show --query provisioningState (¿cluster healthy?)
```

---

## Resumen Final del Curso

| Lección | Herramienta clave |
|---------|-------------------|
| 01 kubectl | `kubectl get`, `describe`, `logs` |
| 02 Pods | `describe pod` → Events |
| 03 Deployments | `rollout status`, `rollout undo` |
| 04 Services | `get endpoints`, labels matching |
| 05 Config | `describe configmap/secret` |
| 06 Storage | `describe pvc`, StorageClass |
| 07 NetPol | `get netpol`, selector matching |
| 08 Nodos | taints, labels, `describe node` |
| 09 Azure | `az network nsg rule list` |
| 10 Avanzado | Metodología DISCOVER |

---

## Lab 10

El lab final combina múltiples problemas en un solo escenario. Deberás aplicar todo lo aprendido para resolverlo.

```bash
./curso-labs.sh 10
```
