# Lección 09 – Integración Azure: NSG, Load Balancer y Azure Networking

## Objetivos
- Entender cómo AKS interactúa con recursos Azure (NSG, LB, VNET)
- Diagnosticar problemas a nivel de infraestructura Azure
- Conocer el resource group MC_ (managed) y sus componentes

---

## 1. Arquitectura de Red AKS en Azure

```
┌─────────────────────────────────────────────────────────┐
│ Resource Group: my-aks-rg (TÚ lo creaste)               │
│   └── AKS Cluster: my-cluster                           │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Resource Group: MC_my-aks-rg_my-cluster_region           │
│ (Azure lo crea automáticamente)                          │
│                                                          │
│   ├── VMSS (Virtual Machine Scale Sets) ← nodos         │
│   ├── VNet + Subnets                                     │
│   ├── NSG (Network Security Group) ← firewall            │
│   ├── Load Balancer ← para Services tipo LoadBalancer    │
│   ├── Public IPs                                         │
│   ├── Route Table                                        │
│   └── Managed Identities                                 │
└─────────────────────────────────────────────────────────┘
```

```bash
# Ver el resource group managed
az aks show -g <rg> -n <cluster> --query nodeResourceGroup -o tsv
# Resultado: MC_my-aks-rg_my-cluster_eastus
```

---

## 2. Network Security Groups (NSG)

Los NSG son firewalls a nivel de Azure que controlan tráfico de red hacia/desde subnets y NICs.

```bash
# Listar NSGs en el MC_ resource group
az network nsg list -g MC_my-aks-rg_my-cluster_region -o table

# Ver reglas de un NSG
az network nsg rule list --nsg-name <nsg> -g <mc-rg> -o table
```

### Reglas NSG importantes para AKS

| Dirección | Puerto | Propósito |
|-----------|--------|-----------|
| Inbound | 443 | API Server (si es público) |
| Inbound | 80/443 | LoadBalancer Services |
| Outbound | 443 | Comunicación con API, ACR, MCR |
| Outbound | 53 | DNS |
| Outbound | 123 | NTP |

### Regla de prioridad

Las reglas NSG se evalúan por **prioridad** (número más bajo = más prioritario):

```
Priority 100: Deny Inbound TCP 80      ← Se evalúa PRIMERO (bloquea)
Priority 200: Allow Inbound TCP 80     ← NUNCA se alcanza
```

```bash
# Crear una regla
az network nsg rule create -g <rg> --nsg-name <nsg> \
  --name AllowHTTP --priority 200 \
  --direction Inbound --access Allow \
  --protocol Tcp --destination-port-ranges 80

# Eliminar una regla
az network nsg rule delete -g <rg> --nsg-name <nsg> --name DenyHTTP
```

---

## 3. Azure Load Balancer

Cuando creas un Service tipo `LoadBalancer`, AKS configura el Azure LB automáticamente.

```bash
# Ver el Load Balancer
az network lb list -g <mc-rg> -o table

# Ver reglas de balanceo
az network lb rule list -g <mc-rg> --lb-name kubernetes -o table

# Ver IPs públicas
az network public-ip list -g <mc-rg> -o table
```

### Problemas comunes con LoadBalancer

| Síntoma | Causa posible |
|---------|---------------|
| Service sin External-IP | Cuota de IPs públicas agotada |
| External-IP pero timeout | NSG bloqueando el puerto |
| Intermitente | Health probe del LB fallando |

```bash
# Diagnosticar desde Kubernetes
kubectl describe svc <service-name>
# Buscar en Events:
#   "Error syncing load balancer" → problema de permisos o cuota

# Ver health probes del LB
az network lb probe list -g <mc-rg> --lb-name kubernetes -o table
```

---

## 4. Virtual Network (VNET)

```bash
# Ver la VNET del cluster
az network vnet list -g <mc-rg> -o table

# Ver subnets
az network vnet subnet list -g <mc-rg> --vnet-name <vnet> -o table

# Ver IPs asignadas
az network vnet subnet show -g <mc-rg> --vnet-name <vnet> -n <subnet> \
  --query addressPrefix -o tsv
```

### Problemas comunes de VNET

| Problema | Causa |
|----------|-------|
| No se pueden crear más pods | Subnet sin IPs disponibles |
| Nodos no pueden comunicarse | Route table corrupta |
| No se puede alcanzar servicio externo | UDR (User Defined Routes) mal configurado |

---

## 5. Diagnóstico con Azure CLI

### Paso a paso para problemas de red

```bash
# 1. Identificar el MC_ resource group
MC_RG=$(az aks show -g <rg> -n <cluster> --query nodeResourceGroup -o tsv)

# 2. Listar NSGs y sus reglas
az network nsg list -g $MC_RG -o table
az network nsg rule list --nsg-name <nsg> -g $MC_RG -o table

# 3. Buscar reglas deny sospechosas
az network nsg rule list --nsg-name <nsg> -g $MC_RG \
  --query "[?access=='Deny']" -o table

# 4. Verificar el Load Balancer
az network lb list -g $MC_RG -o table

# 5. Verificar IPs públicas
az network public-ip list -g $MC_RG -o table

# 6. Ver si el cluster tiene permisos sobre la VNET
az aks show -g <rg> -n <cluster> --query "identity" -o json
```

---

## 6. Azure Network Watcher (Herramienta avanzada)

```bash
# IP Flow Verify - ¿Un paquete llegaría de A a B?
az network watcher test-ip-flow \
  --direction Inbound \
  --protocol TCP \
  --local 10.0.0.4:80 \
  --remote 203.0.113.1:12345 \
  --vm <vmss-instance> \
  -g <mc-rg>
```

---

## 7. Managed Identity y Permisos

El cluster AKS necesita permisos para manejar recursos Azure:

```bash
# Ver la identidad del cluster
az aks show -g <rg> -n <cluster> --query "identity" -o json

# Ver las asignaciones de roles
az role assignment list --assignee <principal-id> -o table
```

| Permiso necesario | Para qué |
|-------------------|----------|
| Network Contributor en VNET | Crear/modificar subnets, NSG rules |
| Network Contributor en MC_RG | Crear LB, IPs públicas |
| AcrPull en ACR | Descargar imágenes de ACR |

---

## Resumen

| Qué investigar | Comando Azure CLI |
|----------------|-------------------|
| MC Resource Group | `az aks show -g <rg> -n <c> --query nodeResourceGroup` |
| NSG rules | `az network nsg rule list --nsg-name <nsg> -g <mc-rg>` |
| Load Balancer | `az network lb list -g <mc-rg>` |
| IPs públicas | `az network public-ip list -g <mc-rg>` |
| VNET/Subnets | `az network vnet subnet list -g <mc-rg> --vnet-name <v>` |

---

## Lab 09

El lab crea un LoadBalancer Service funcional pero una regla NSG bloquea el tráfico. Deberás encontrar y eliminar la regla.

```bash
./curso-labs.sh 9
```
