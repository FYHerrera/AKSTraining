# Lección 04 – Services y Networking

## Objetivos
- Entender los tipos de Service en Kubernetes
- Diagnosticar problemas de conectividad entre pods
- Entender DNS interno y cómo los Services conectan pods

---

## 1. ¿Qué es un Service?

Los pods son efímeros (se crean y destruyen). Un **Service** da una IP estable y nombre DNS para acceder a un grupo de pods.

```
                    ┌────────────┐
                    │  Service   │
    Otros pods ──►  │  web-svc   │
    (o externos)    │ 10.0.0.100 │
                    └─────┬──────┘
                          │ selector: app=web
                    ┌─────┼──────┐
                    ▼     ▼      ▼
                 ┌─────┐┌─────┐┌─────┐
                 │Pod 1││Pod 2││Pod 3│
                 │app= ││app= ││app= │
                 │web  ││web  ││web  │
                 └─────┘└─────┘└─────┘
```

---

## 2. Tipos de Service

### ClusterIP (default)
Accesible solo dentro del cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  type: ClusterIP            # Solo interno
  selector:
    app: backend              # ← DEBE coincidir con labels de los pods
  ports:
  - port: 80                  # Puerto del service
    targetPort: 8080          # Puerto del container
```

### NodePort
Abre un puerto en cada nodo (30000-32767).

```yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080           # Accesible en <nodeIP>:30080
```

### LoadBalancer
Crea un Azure Load Balancer con IP pública.

```yaml
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
```

```bash
# Ver la IP externa asignada
kubectl get svc web-svc
# NAME      TYPE          CLUSTER-IP   EXTERNAL-IP    PORT(S)
# web-svc   LoadBalancer  10.0.0.100   20.1.2.3       80:30123/TCP
```

---

## 3. DNS Interno

Kubernetes tiene **CoreDNS** que resuelve nombres de servicios automáticamente.

```
<service-name>.<namespace>.svc.cluster.local
```

Ejemplos:
```bash
# Desde un pod en el mismo namespace:
curl http://backend-svc               # ← funciona (mismo namespace)
curl http://backend-svc.default       # ← también funciona
curl http://backend-svc.default.svc.cluster.local  # ← FQDN completo

# Desde un pod en OTRO namespace:
curl http://backend-svc.production    # ← necesitas el namespace
```

### Probar DNS desde un pod
```bash
# Crear pod temporal para debug
kubectl run debug --image=busybox:1.36 --rm -it -- /bin/sh

# Dentro del pod:
nslookup backend-svc
nslookup kubernetes.default
wget -qO- http://backend-svc
```

---

## 4. Cómo un Service Encuentra los Pods

La conexión es por **labels**:

```
Service selector:  app=backend  ──────┐
                                      │ ¿Match?
Pod labels:        app=backend  ──────┘ ✓ SÍ → incluido
Pod labels:        app=frontend ──────  ✗ NO → excluido
```

### Endpoints

Los **Endpoints** son la lista de IPs de pods que un Service envía tráfico.

```bash
# Ver qué pods está incluyendo un service
kubectl get endpoints backend-svc
# NAME          ENDPOINTS                         AGE
# backend-svc   10.244.0.5:8080,10.244.1.3:8080   5m
```

**Si endpoints está vacío** → el Service no encuentra pods (selector no coincide).

---

## 5. Errores Comunes de Networking

### Service sin endpoints
```bash
kubectl get endpoints my-svc
# ENDPOINTS: <none>
```
**Causa**: El `selector` del Service no coincide con los `labels` de los pods.

**Diagnóstico**:
```bash
# Ver selector del service
kubectl describe svc my-svc | grep Selector

# Ver labels de los pods
kubectl get pods --show-labels

# ¿Coinciden?
```

### Port vs TargetPort
```yaml
ports:
- port: 80           # Puerto al que te conectas (Service)
  targetPort: 8080    # Puerto real del container
```

Si tu app escucha en 8080 pero pones `targetPort: 80` → connection refused.

### Pod no puede resolver DNS
```bash
kubectl exec my-pod -- nslookup kubernetes.default
# ** server can't find kubernetes.default: NXDOMAIN
```

**Causas**: NetworkPolicy bloqueando egress, CoreDNS caído, o pod sin acceso a kube-dns.

```bash
# Verificar CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

## 6. Diagnóstico de Conectividad

### Checklist paso a paso

```bash
# 1. ¿El service existe y tiene la IP?
kubectl get svc web-svc

# 2. ¿Tiene endpoints (pods asociados)?
kubectl get endpoints web-svc

# 3. ¿Los pods están Running?
kubectl get pods -l app=web

# 4. ¿El selector coincide con los labels?
kubectl describe svc web-svc | grep Selector
kubectl get pods --show-labels | grep web

# 5. ¿El puerto es correcto?
kubectl describe svc web-svc | grep Port
kubectl describe pod <pod> | grep "Container Port"

# 6. ¿Se puede conectar desde otro pod?
kubectl exec debug -- wget -qO- http://web-svc --timeout=5
```

---

## 7. Ingress (Bonus)

Para rutas HTTP/HTTPS más avanzadas, se usa **Ingress** + un Ingress Controller.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
```

---

## Resumen

| Situación | Qué revisar |
|-----------|-------------|
| Service sin respuesta | `kubectl get endpoints <svc>` |
| Endpoints vacío | Comparar `selector` del Service vs `labels` de pods |
| DNS no resuelve | `kubectl get pods -n kube-system -l k8s-app=kube-dns` |
| LoadBalancer sin IP | `kubectl describe svc <svc>` → Events |
| Connection refused | Verificar `targetPort` vs puerto real del container |

---

## Lab 04

El lab tiene un Service que no puede conectarse con sus pods. Deberás encontrar por qué y arreglarlo.

```bash
./curso-labs.sh 4
```
