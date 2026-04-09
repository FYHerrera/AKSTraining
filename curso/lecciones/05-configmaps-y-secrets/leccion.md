# Lección 05 – ConfigMaps y Secrets

## Objetivos
- Entender cómo externalizar configuración con ConfigMaps
- Manejar datos sensibles con Secrets
- Diagnosticar pods que fallan por configuración faltante

---

## 1. ¿Por qué ConfigMaps y Secrets?

**Nunca** hardcodear configuración ni credenciales en la imagen del container. En su lugar:

| Tipo de dato | Recurso |
|--------------|---------|
| URLs, feature flags, config general | **ConfigMap** |
| Contraseñas, tokens, certificados | **Secret** |

---

## 2. ConfigMaps

### Crear un ConfigMap

```bash
# Desde literal
kubectl create configmap app-config \
  --from-literal=DATABASE_HOST=db.example.com \
  --from-literal=LOG_LEVEL=info

# Desde archivo
kubectl create configmap nginx-config --from-file=nginx.conf

# Ver contenido
kubectl get configmap app-config -o yaml
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_HOST: "db.example.com"
  LOG_LEVEL: "info"
  app.properties: |
    server.port=8080
    server.timeout=30
```

### Usar en un Pod

**Como variables de entorno:**
```yaml
spec:
  containers:
  - name: app
    image: myapp:v1
    env:
    - name: DATABASE_HOST
      valueFrom:
        configMapKeyRef:
          name: app-config       # Nombre del ConfigMap
          key: DATABASE_HOST     # Key específica

    # O cargar TODAS las keys como env vars:
    envFrom:
    - configMapRef:
        name: app-config
```

**Como archivo montado (volumen):**
```yaml
spec:
  containers:
  - name: app
    image: myapp:v1
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config     # Los keys se vuelven archivos aquí
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```

---

## 3. Secrets

Los Secrets son como ConfigMaps pero para datos sensibles. Los valores se guardan en base64 (NO es encriptación, es codificación).

### Crear un Secret

```bash
# Desde literal
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=S3cureP@ss!

# Ver (los valores aparecen en base64)
kubectl get secret db-creds -o yaml
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
data:
  username: YWRtaW4=          # base64 de "admin"
  password: UzNjdXJlUEBzcyE=  # base64 de "S3cureP@ss!"
```

```bash
# Decodificar un valor
echo "YWRtaW4=" | base64 --decode    # → admin
```

### Usar en un Pod

```yaml
spec:
  containers:
  - name: app
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-creds
          key: password
```

---

## 4. Errores Comunes

### Pod falla porque el ConfigMap/Secret no existe

```
Events:
  Warning  Failed  kubelet  Error: configmap "app-config" not found
```

El pod queda en `CreateContainerConfigError`.

**Fix:**
```bash
# Verificar que existe
kubectl get configmap app-config
kubectl get secret db-creds

# Si no existe, crearlo
kubectl create configmap app-config --from-literal=KEY=value
```

### Key incorrecta

```yaml
# Error: el key "DB_HOST" no existe en el ConfigMap
valueFrom:
  configMapKeyRef:
    name: app-config
    key: DB_HOST        # ← ¿Existe esta key?
```

```bash
# Verificar las keys disponibles
kubectl describe configmap app-config
```

### Pod referencia un key optional

```yaml
env:
- name: OPTIONAL_VAR
  valueFrom:
    configMapKeyRef:
      name: maybe-config
      key: value
      optional: true          # Si no existe, el pod arranca igual
```

---

## 5. Buenas Prácticas

```bash
# 1. Nunca poner secrets en el YAML que se commitea a Git
# 2. Usar nombres descriptivos
# 3. Verificar que ConfigMap/Secret existe ANTES de deploy
# 4. Usar 'optional: true' solo cuando sea realmente opcional

# Ver qué pods usan un ConfigMap
kubectl get pods -A -o json | jq '.items[] | 
  select(.spec.containers[].env[]?.valueFrom.configMapKeyRef.name == "app-config") |
  .metadata.name'
```

---

## 6. Diagnóstico Rápido

```bash
# Pod en CreateContainerConfigError
kubectl describe pod <name>
# → Buscar en Events: "configmap not found" o "secret not found"

# Verificar que el ConfigMap tiene los keys esperados
kubectl get configmap <name> -o yaml

# Verificar que el Secret tiene los keys esperados  
kubectl get secret <name> -o jsonpath='{.data}'

# Ver las env vars dentro de un pod que SÍ funciona
kubectl exec <pod> -- env | sort
```

---

## Resumen

| Acción | Comando |
|--------|---------|
| Ver ConfigMaps | `kubectl get configmap` |
| Ver contenido | `kubectl describe configmap <name>` |
| Crear desde literal | `kubectl create configmap <name> --from-literal=K=V` |
| Ver Secrets (keys) | `kubectl get secret <name> -o jsonpath='{.data}'` |
| Decodificar secret | `echo "<base64>" \| base64 --decode` |
| Ver env vars de un pod | `kubectl exec <pod> -- env` |

---

## Lab 05

El lab tiene una aplicación que falla porque le falta configuración (ConfigMap/Secret). Deberás crear los recursos faltantes.

```bash
./curso-labs.sh 5
```
