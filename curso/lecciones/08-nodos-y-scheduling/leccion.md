# Lección 08 – Gestión de Nodos: Taints, Tolerations y Scheduling

## Objetivos
- Entender cómo el scheduler asigna pods a nodos
- Usar taints, tolerations, nodeSelector y affinity
- Diagnosticar pods que no pueden ser schedulados

---

## 1. ¿Cómo Decide el Scheduler?

Cuando creas un pod, el scheduler evalúa:

```
1. ¿El nodo tiene recursos suficientes? (CPU, memoria)
2. ¿El pod tiene nodeSelector que el nodo no cumple?
3. ¿El nodo tiene taints que el pod no tolera?
4. ¿Hay reglas de affinity/anti-affinity?
```

Si ningún nodo pasa todos los filtros → pod queda **Pending**.

---

## 2. Taints y Tolerations

Los **taints** son "repelentes" en los nodos. Solo pods con la **toleration** correcta pueden schedularse ahí.

### Aplicar un taint a un nodo
```bash
# Formato: key=value:efecto
kubectl taint nodes node1 dedicated=gpu:NoSchedule

# Efectos posibles:
# NoSchedule      → No agenda nuevos pods (existentes no se mueven)
# PreferNoSchedule → Intenta evitar, pero no es estricto
# NoExecute       → No agenda nuevos + desaloja existentes
```

### Ver taints de un nodo
```bash
kubectl describe node <name> | grep -A5 Taints
# Taints: dedicated=gpu:NoSchedule
```

### Tolerations en el pod
```yaml
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
```

### Quitar un taint
```bash
# El guión al final (-) remueve el taint
kubectl taint nodes node1 dedicated=gpu:NoSchedule-

# Quitar de todos los nodos
kubectl taint nodes --all dedicated=gpu:NoSchedule-
```

---

## 3. NodeSelector

La forma más simple de elegir un nodo:

```yaml
spec:
  nodeSelector:
    disktype: ssd              # El nodo DEBE tener este label
```

```bash
# Ver labels de nodos
kubectl get nodes --show-labels

# Agregar label a un nodo
kubectl label nodes node1 disktype=ssd

# Quitar label
kubectl label nodes node1 disktype-
```

Si ningún nodo tiene el label → pod queda Pending.

---

## 4. Node Affinity (más flexible que nodeSelector)

```yaml
spec:
  affinity:
    nodeAffinity:
      # Requisito obligatorio
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: agentpool
            operator: In
            values: ["pool1", "pool2"]
      
      # Preferencia (mejor esfuerzo)
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: zone
            operator: In
            values: ["eastus-1"]
```

### Operadores
| Operador | Significado |
|----------|-------------|
| `In` | Valor está en la lista |
| `NotIn` | Valor NO está en la lista |
| `Exists` | El key existe (no importa valor) |
| `DoesNotExist` | El key no existe |

---

## 5. Taints en AKS

AKS puede tener taints automáticos en ciertos escenarios:

| Taint | Significado |
|-------|-------------|
| `node.kubernetes.io/not-ready` | Nodo no está listo |
| `node.kubernetes.io/unreachable` | Nodo no responde |
| `node.kubernetes.io/memory-pressure` | Nodo con poca memoria |
| `node.kubernetes.io/disk-pressure` | Nodo con poco disco |
| `node.kubernetes.io/unschedulable` | Nodo marcado con cordon |

### Cordon y Drain

```bash
# Cordon: no agendar nuevos pods (no mueve existentes)
kubectl cordon node1
# El nodo recibe taint: node.kubernetes.io/unschedulable:NoSchedule

# Uncordon: permitir scheduling de nuevo
kubectl uncordon node1

# Drain: mover todos los pods a otros nodos (para mantenimiento)
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data

# Un drain hace cordón + eviction de pods
```

---

## 6. System Pools vs User Pools en AKS

```bash
# Ver node pools
az aks nodepool list -g <rg> --cluster-name <cluster> -o table
```

| Pool | Propósito | Taint |
|------|-----------|-------|
| System pool | kube-system pods | `CriticalAddonsOnly=true:NoSchedule` |
| User pool | Tus aplicaciones | Ninguno (por defecto) |

---

## 7. Diagnóstico de Scheduling

```bash
# Pod en Pending – ver por qué
kubectl describe pod <name>
# Buscar en Events:
#   Warning  FailedScheduling  0/3 nodes are available:
#     1 node(s) had taint {dedicated: gpu}, that the pod didn't tolerate
#     2 node(s) didn't match Pod's node affinity/selector

# Ver capacidad vs uso de nodos
kubectl top nodes
kubectl describe node <name> | grep -A5 "Allocated resources"

# Ver taints de todos los nodos
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
TAINTS:.spec.taints[*].key

# Ver labels de todos los nodos
kubectl get nodes --show-labels
```

### Tabla de diagnóstico

| Mensaje en Events | Causa | Fix |
|-------------------|-------|-----|
| "didn't tolerate taint" | Nodo tiene taint, pod no tiene toleration | Añadir toleration o quitar taint |
| "didn't match node selector" | nodeSelector con label que no existe | Añadir label al nodo o quitar selector |
| "Insufficient cpu/memory" | Nodo sin recursos | Escalar el node pool o reducir requests |
| "didn't match pod affinity" | Regla de affinity no satisfecha | Revisar affinity rules |

---

## Resumen

| Acción | Comando |
|--------|---------|
| Ver taints | `kubectl describe node <n> \| grep -A5 Taints` |
| Agregar taint | `kubectl taint nodes <n> key=val:NoSchedule` |
| Quitar taint | `kubectl taint nodes <n> key=val:NoSchedule-` |
| Agregar label | `kubectl label nodes <n> key=value` |
| Cordon nodo | `kubectl cordon <n>` |
| Drain nodo | `kubectl drain <n> --ignore-daemonsets` |

---

## Lab 08

El lab tiene nodos con taints que impiden el scheduling de pods. Deberás encontrar y resolver el problema.

```bash
./curso-labs.sh 8
```
