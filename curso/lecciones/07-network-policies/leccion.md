# Lección 07 – Network Policies

## Objetivos
- Entender cómo funcionan las Network Policies
- Crear reglas de ingress y egress
- Diagnosticar problemas de conectividad causados por policies

---

## 1. ¿Qué son Network Policies?

Por defecto, **todos los pods pueden hablar con todos**. Las Network Policies son firewalls a nivel de pod que restringen tráfico.

```
Sin NetworkPolicy:       Con NetworkPolicy:
  Pod A ←→ Pod B           Pod A ──X── Pod B
  Pod A ←→ Pod C           Pod A ←───→ Pod C  (permitido)
  Pod B ←→ Pod C           Pod B ──X── Pod C
```

> **IMPORTANTE**: En AKS, debes crear el cluster con `--network-plugin azure` (o `--network-policy azure/calico`) para que las Network Policies funcionen. Azure CNI las soporta.

---

## 2. Anatomía de una Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: default
spec:
  podSelector:              # ¿A qué pods aplica esta regla?
    matchLabels:
      app: backend
  policyTypes:              # ¿Qué tipo de tráfico controla?
  - Ingress                 # Tráfico entrante
  - Egress                  # Tráfico saliente
  ingress:                  # Reglas de entrada
  - from:
    - podSelector:
        matchLabels:
          app: frontend     # Solo permitir desde pods con app=frontend
    ports:
    - protocol: TCP
      port: 80
  egress:                   # Reglas de salida
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

---

## 3. Reglas Clave

### Si no hay NetworkPolicy → todo está permitido
### Si existe al menos una policy para un pod → todo lo NO permitido se bloquea

```yaml
# Esto BLOQUEA TODO el ingress (lista vacía):
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress: []               # ← Sin reglas = bloquea todo

# Esto BLOQUEA TODO el egress:
spec:
  podSelector: {}           # Todos los pods
  policyTypes:
  - Egress
  # ← Sin campo egress = bloquea todo el tráfico saliente
```

---

## 4. Selectores

### podSelector (pods del mismo namespace)
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: frontend
```

### namespaceSelector (pods de otros namespaces)
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: production
    podSelector:
      matchLabels:
        app: api-gateway
```

### ipBlock (IPs externas)
```yaml
ingress:
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
      except:
      - 10.0.1.0/24
```

---

## 5. Caso Especial: DNS

**Error muy común**: Bloquear egress sin permitir DNS.

DNS usa puerto 53 UDP/TCP hacia CoreDNS en `kube-system`. Si bloqueas egress, debes permitir DNS explícitamente:

```yaml
egress:
# Permitir DNS
- to:
  - namespaceSelector: {}   # Cualquier namespace (CoreDNS está en kube-system)
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
# Permitir tráfico a la app
- to:
  - podSelector:
      matchLabels:
        app: database
  ports:
  - protocol: TCP
    port: 5432
```

---

## 6. Patrones Comunes

### Deny All (base de zero-trust)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Permitir solo tráfico específico
```yaml
# Después del deny-all, agrega reglas específicas:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
```

---

## 7. Diagnóstico

```bash
# Ver todas las NetworkPolicies
kubectl get networkpolicy
kubectl get netpol              # Atajo

# Ver detalle de una policy
kubectl describe netpol <name>

# Probar conectividad entre pods
kubectl exec <pod-a> -- wget -qO- http://<service> --timeout=5
kubectl exec <pod-a> -- nc -zv <pod-b-ip> 80 -w 5

# Probar DNS
kubectl exec <pod> -- nslookup kubernetes.default

# Ver labels de pods (para verificar selectores)
kubectl get pods --show-labels

# Ver las policies que aplican a un pod específico
kubectl get netpol -o json | jq '.items[] |
  select(.spec.podSelector.matchLabels.app == "backend") | .metadata.name'
```

### Checklist de diagnóstico

1. ¿Existe alguna NetworkPolicy? → `kubectl get netpol`
2. ¿El selector de la policy coincide con el pod afectado?
3. ¿Las reglas ingress/egress permiten el tráfico necesario?
4. ¿Se permite DNS (port 53) en las reglas egress?
5. ¿Los labels de los pods "from" coinciden con el selector de la regla?

---

## Resumen

| Concepto | Efecto |
|----------|--------|
| Sin NetworkPolicy | Todo permitido |
| policyTypes: [Ingress] sin reglas | Bloquea todo ingress |
| policyTypes: [Egress] sin reglas | Bloquea todo egress (incluyendo DNS) |
| podSelector: {} | Aplica a todos los pods del namespace |

---

## Lab 07

El lab tiene NetworkPolicies bloqueando tráfico legítimo. Deberás identificar qué regla causa el problema y arreglarlo.

```bash
./curso-labs.sh 7
```
