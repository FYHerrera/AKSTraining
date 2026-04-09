# Lección 01 – Fundamentos de kubectl y Arquitectura AKS

## Objetivos
- Entender la arquitectura de un cluster AKS
- Dominar los comandos básicos de kubectl
- Saber obtener información clave del cluster

---

## 1. Arquitectura de AKS

Un cluster AKS tiene dos planos:

```
┌─────────────────────────────────────────────────┐
│                 Control Plane                    │
│  (Administrado por Azure – no lo ves)            │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │API Server│ │  etcd    │ │ Controller Manager│ │
│  └──────────┘ └──────────┘ └──────────────────┘ │
│  ┌──────────┐ ┌──────────────────────────────┐   │
│  │Scheduler │ │ Cloud Controller Manager     │   │
│  └──────────┘ └──────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                    │
                    │ API (443)
                    │
┌─────────────────────────────────────────────────┐
│                  Worker Nodes                    │
│  ┌─────────────────────────────────────────────┐ │
│  │ Node 1                                      │ │
│  │  kubelet ─ kube-proxy ─ container runtime   │ │
│  │  ┌────┐ ┌────┐ ┌────┐                      │ │
│  │  │Pod │ │Pod │ │Pod │                       │ │
│  │  └────┘ └────┘ └────┘                      │ │
│  └─────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────┐ │
│  │ Node 2                                      │ │
│  │  kubelet ─ kube-proxy ─ container runtime   │ │
│  │  ┌────┐ ┌────┐                              │ │
│  │  │Pod │ │Pod │                               │ │
│  │  └────┘ └────┘                              │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### Componentes clave
| Componente | Función |
|-----------|---------|
| **API Server** | Punto de entrada para todas las operaciones (kubectl habla con él) |
| **etcd** | Base de datos que guarda todo el estado del cluster |
| **Scheduler** | Decide en qué nodo colocar cada pod |
| **Controller Manager** | Mantiene el estado deseado (replicas, etc.) |
| **kubelet** | Agente en cada nodo que ejecuta los pods |
| **kube-proxy** | Configura reglas de red en cada nodo |
| **CoreDNS** | Resolución DNS interna del cluster |

---

## 2. Conectarse al Cluster

```bash
# Login a Azure
az login

# Ver suscripciones
az account list -o table

# Seleccionar suscripción
az account set --subscription "<nombre-o-id>"

# Obtener credenciales del cluster
az aks get-credentials --resource-group <rg> --name <cluster>

# Verificar conexión
kubectl cluster-info
```

---

## 3. Comandos Esenciales de kubectl

### Ver recursos
```bash
# Nodos del cluster
kubectl get nodes
kubectl get nodes -o wide              # Más detalle (IPs, versión, OS)

# Pods
kubectl get pods                        # Namespace default
kubectl get pods -n kube-system         # Namespace específico
kubectl get pods --all-namespaces       # Todos los namespaces
kubectl get pods -A                     # Atajo de --all-namespaces

# Todos los recursos
kubectl get all
kubectl get all -A
```

### Describir recursos (MUY IMPORTANTE para troubleshooting)
```bash
# Describe muestra EVENTOS – clave para diagnosticar problemas
kubectl describe node <nombre>
kubectl describe pod <nombre>
kubectl describe pod <nombre> -n <namespace>
```

### Logs
```bash
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container>   # Si el pod tiene varios containers
kubectl logs <pod-name> --previous       # Logs del container anterior (crasheado)
kubectl logs -l app=web-app              # Logs por label
```

### Ejecutar comandos dentro de un pod
```bash
kubectl exec <pod> -- <comando>
kubectl exec <pod> -- ls /app
kubectl exec -it <pod> -- /bin/sh        # Shell interactivo
```

### Formatos de salida
```bash
kubectl get pods -o wide                 # Tabla con más columnas
kubectl get pods -o yaml                 # YAML completo
kubectl get pods -o json                 # JSON completo
kubectl get pods -o jsonpath='{.items[*].metadata.name}'  # Campos específicos
```

---

## 4. Namespaces

Los namespaces son divisiones lógicas del cluster.

```bash
# Ver namespaces
kubectl get namespaces

# Namespaces por defecto en AKS:
# - default         → donde van los recursos si no especificas namespace
# - kube-system     → componentes del sistema (CoreDNS, kube-proxy, etc.)
# - kube-public     → recursos públicos
# - kube-node-lease → heartbeats de los nodos
```

---

## 5. Labels y Selectors

Los labels son pares key=value que se asignan a los recursos. Son la base de cómo Kubernetes conecta todo.

```bash
# Ver labels de pods
kubectl get pods --show-labels

# Filtrar por label
kubectl get pods -l app=nginx
kubectl get pods -l "app=nginx,tier=frontend"
kubectl get pods -l "app in (nginx, apache)"

# Ver labels de nodos
kubectl get nodes --show-labels
```

---

## 6. Contextos (cambiar entre clusters)

```bash
# Ver contextos disponibles
kubectl config get-contexts

# Ver contexto actual
kubectl config current-context

# Cambiar de contexto
kubectl config use-context <nombre>
```

---

## Resumen de Comandos Clave

| Acción | Comando |
|--------|---------|
| Ver nodos | `kubectl get nodes -o wide` |
| Ver pods en todo el cluster | `kubectl get pods -A` |
| Diagnosticar un pod | `kubectl describe pod <name>` |
| Ver logs | `kubectl logs <pod>` |
| Shell en un pod | `kubectl exec -it <pod> -- /bin/sh` |
| Ver eventos | `kubectl get events --sort-by='.lastTimestamp'` |
| Ver todo en un namespace | `kubectl get all -n <ns>` |

---

## Lab 01

Con estos conocimientos deberías poder completar el **Lab 01 – Application Down + Scavenger Hunt**.
Primero diagnostica por qué la web-app no tiene endpoints y arréglala, luego demuestra tus habilidades con kubectl explorando el cluster.

```bash
chmod +x lab-01.sh && ./lab-01.sh
```
