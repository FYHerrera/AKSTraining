# Lección 03 – Deployments y ReplicaSets

## Objetivos
- Entender Deployments, ReplicaSets y su relación
- Hacer rollouts y rollbacks
- Diagnosticar deployments fallidos

---

## 1. ¿Qué es un Deployment?

Un **Deployment** es la forma estándar de desplegar aplicaciones. Maneja:
- Cantidad de réplicas (pods idénticos)
- Rolling updates (actualizaciones sin downtime)
- Rollbacks (revertir cambios)

```
Deployment → ReplicaSet → Pod(s)
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3                    # Cantidad de pods
  selector:
    matchLabels:
      app: web-app               # DEBE coincidir con template.labels
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                # Pods extra durante update
      maxUnavailable: 0          # Pods que pueden estar caídos
  template:
    metadata:
      labels:
        app: web-app             # Labels de los pods
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
```

---

## 2. Relación Deployment → ReplicaSet → Pods

```
Deployment: web-app
    │
    ├── ReplicaSet: web-app-6d4f5b7c8  (imagen: nginx:1.25) ← actual
    │       ├── Pod: web-app-6d4f5b7c8-abc12
    │       ├── Pod: web-app-6d4f5b7c8-def34
    │       └── Pod: web-app-6d4f5b7c8-ghi56
    │
    └── ReplicaSet: web-app-3a2b1c0d9  (imagen: nginx:1.24) ← anterior
            └── (0 pods - escalado a 0)
```

```bash
# Ver todo junto
kubectl get deployment,replicaset,pods -l app=web-app

# Ver historial de revisiones
kubectl rollout history deployment/web-app
```

---

## 3. Scaling (Escalar)

```bash
# Escalar manualmente
kubectl scale deployment web-app --replicas=5

# Ver el progreso
kubectl get pods -l app=web-app -w     # -w = watch (tiempo real)
```

---

## 4. Rolling Updates

Cuando cambias la imagen (o cualquier campo del template), Kubernetes hace un rolling update:

```bash
# Actualizar imagen
kubectl set image deployment/web-app nginx=nginx:1.26

# Ver progreso del rollout
kubectl rollout status deployment/web-app
```

Qué pasa internamente:
1. Se crea un nuevo ReplicaSet con la nueva imagen
2. Se escala el nuevo RS gradualmente (sube)
3. Se escala el viejo RS gradualmente (baja)
4. Resultado: 0 downtime

---

## 5. Rollbacks

Si un update sale mal:

```bash
# Ver historial
kubectl rollout history deployment/web-app

# Revertir al anterior
kubectl rollout undo deployment/web-app

# Revertir a una revisión específica
kubectl rollout undo deployment/web-app --to-revision=2

# Pausar un rollout problemático
kubectl rollout pause deployment/web-app

# Reanudar
kubectl rollout resume deployment/web-app
```

---

## 6. Health Checks (Probes)

Los probes son cruciales – muchos problemas de CrashLoop se deben a probes mal configurados.

### Tipos de probes

| Probe | Propósito | Si falla... |
|-------|-----------|------------|
| **livenessProbe** | ¿El container está vivo? | kubelet lo reinicia |
| **readinessProbe** | ¿Puede recibir tráfico? | Se saca del Service |
| **startupProbe** | ¿Terminó de arrancar? | No evalúa liveness/readiness |

### Métodos de probe

```yaml
# HTTP GET - el más común
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10     # Esperar antes del primer check
  periodSeconds: 5            # Cada cuánto revisar
  failureThreshold: 3         # Fallos antes de actuar

# TCP Socket
livenessProbe:
  tcpSocket:
    port: 3306

# Exec command
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
```

### Errores típicos con probes

| Problema | Síntoma |
|----------|---------|
| Puerto incorrecto en probe | CrashLoopBackOff (liveness mata el pod) |
| Path inexistente | CrashLoopBackOff |
| initialDelaySeconds muy bajo | App no arranca, liveness la mata |
| Sin readinessProbe | Tráfico llega antes de que la app esté lista |

---

## 7. Diagnóstico de Deployments

```bash
# Estado general
kubectl get deployment web-app

# Condiciones detalladas
kubectl describe deployment web-app

# Ver el rollout
kubectl rollout status deployment/web-app

# Eventos recientes
kubectl get events --sort-by='.lastTimestamp' | grep web-app

# Ver la spec actual vs una revisión anterior
kubectl rollout history deployment/web-app --revision=2
```

### Deployment atascado – señales

```
# CONDITIONS en describe:
# Available = False → pods no están ready
# Progressing = False → timeout en el rollout

# Causas comunes:
# - Imagen no existe
# - Probe configurado mal
# - Resources insuficientes
# - nodeSelector sin match
```

---

## 8. Modificar Deployments

```bash
# Editar en vivo (abre editor)
kubectl edit deployment web-app

# Patch JSON (cambio específico)
kubectl patch deployment web-app --type=json \
  -p='[{"op": "replace", "path": "/spec/replicas", "value": 5}]'

# Aplicar desde YAML
kubectl apply -f deployment.yaml
```

---

## Resumen

| Acción | Comando |
|--------|---------|
| Ver deployment | `kubectl get deploy web-app` |
| Ver pods de un deployment | `kubectl get pods -l app=web-app` |
| Historial de versiones | `kubectl rollout history deploy/web-app` |
| Rollback | `kubectl rollout undo deploy/web-app` |
| Escalar | `kubectl scale deploy/web-app --replicas=5` |
| Cambiar imagen | `kubectl set image deploy/web-app nginx=nginx:1.26` |
| Ver progreso | `kubectl rollout status deploy/web-app` |

---

## Lab 03

El lab tiene un Deployment con un rollout fallido. Deberás investigar por qué y hacer un rollback o fix.

```bash
./curso-labs.sh 3
```
