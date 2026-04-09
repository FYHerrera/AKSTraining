# Lección 02 – Pods y Contenedores

## Objetivos
- Entender qué es un Pod y su ciclo de vida
- Diagnosticar pods con problemas de imagen
- Leer eventos y logs para identificar errores

---

## 1. ¿Qué es un Pod?

Un **Pod** es la unidad más pequeña en Kubernetes. Contiene uno o más contenedores que comparten red y almacenamiento.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mi-pod
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:1.25          # imagen:tag
    ports:
    - containerPort: 80
    resources:
      requests:                # Mínimo garantizado
        cpu: 100m
        memory: 128Mi
      limits:                  # Máximo permitido
        cpu: 500m
        memory: 256Mi
```

---

## 2. Ciclo de Vida de un Pod

```
Pending → Running → Succeeded/Failed
          ↓    ↑
       CrashLoopBackOff
```

### Estados comunes

| Estado | Significado |
|--------|-------------|
| **Pending** | Esperando ser asignado a un nodo o que se descargue la imagen |
| **Running** | Al menos un contenedor está corriendo |
| **Succeeded** | Todos los contenedores terminaron exitosamente (exit 0) |
| **Failed** | Al menos un contenedor falló (exit ≠ 0) |
| **CrashLoopBackOff** | El contenedor se reinicia constantemente tras fallar |
| **ImagePullBackOff** | No puede descargar la imagen del contenedor |
| **ErrImagePull** | Error al intentar descargar la imagen |

---

## 3. Imágenes de Contenedores

```
registro/repositorio:tag
```

Ejemplos:
```
nginx:1.25                              # Docker Hub (implícito)
mcr.microsoft.com/azuredocs/aci-helloworld  # Microsoft Container Registry
myacr.azurecr.io/myapp:v2              # Azure Container Registry privado
```

### Errores comunes con imágenes

| Error | Causa |
|-------|-------|
| `ErrImagePull` | Imagen o tag no existe, o no hay permisos |
| `ImagePullBackOff` | Reintentos de pull fallando (backoff exponencial) |
| `InvalidImageName` | Nombre de imagen malformado |

---

## 4. Diagnóstico de Pods

### Paso 1: Ver estado
```bash
kubectl get pods
# NAME       READY   STATUS             RESTARTS   AGE
# web-app    0/1     ImagePullBackOff   0          5m
```

### Paso 2: Describe (SIEMPRE revisar Events)
```bash
kubectl describe pod web-app
```
```
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  5m    default-scheduler  Successfully assigned...
  Normal   Pulling    5m    kubelet            Pulling image "nginx:99.99"
  Warning  Failed     5m    kubelet            Failed to pull image "nginx:99.99":
                                                tag does not exist
  Warning  Failed     5m    kubelet            Error: ErrImagePull
  Normal   BackOff    4m    kubelet            Back-off pulling image "nginx:99.99"
  Warning  Failed     4m    kubelet            Error: ImagePullBackOff
```

### Paso 3: Logs (si el contenedor llegó a iniciar)
```bash
kubectl logs web-app
kubectl logs web-app --previous    # Si crasheó, ver logs anteriores
```

---

## 5. Crear y Manejar Pods

```bash
# Crear un pod rápido
kubectl run test --image=nginx:1.25

# Crear un pod temporal para debug
kubectl run debug --image=busybox:1.36 --rm -it -- /bin/sh

# Ver YAML de un pod existente
kubectl get pod test -o yaml

# Cambiar la imagen de un pod (vía deployment)
kubectl set image deployment/web-app nginx=nginx:1.26

# Eliminar un pod
kubectl delete pod test
```

---

## 6. Contenedores Init y Sidecar

Un pod puede tener:
- **Init containers**: Se ejecutan ANTES del contenedor principal
- **Sidecar containers**: Se ejecutan JUNTO al contenedor principal

```yaml
spec:
  initContainers:               # Se ejecuta primero
  - name: init-db
    image: busybox
    command: ['sh', '-c', 'until nslookup db-service; do sleep 2; done']
  containers:                   # Se ejecuta después
  - name: app
    image: myapp:v1
```

Si un init container falla, el pod queda en `Init:Error` o `Init:CrashLoopBackOff`.

---

## 7. Resources: Requests y Limits

| Concepto | Qué es |
|----------|--------|
| **requests** | Lo mínimo que el pod necesita (el scheduler usa esto) |
| **limits** | Lo máximo que puede usar (si excede memory → OOMKilled) |

```bash
# Ver uso de recursos actual
kubectl top pods
kubectl top nodes

# Si un pod es OOMKilled:
kubectl describe pod <name>  # → State: OOMKilled
```

---

## Resumen

| Para diagnosticar... | Usa... |
|---------------------|--------|
| Estado del pod | `kubectl get pods` |
| Por qué falló | `kubectl describe pod <name>` → Events |
| Qué imprime el app | `kubectl logs <pod>` |
| Logs del crash anterior | `kubectl logs <pod> --previous` |
| Probar desde dentro | `kubectl exec -it <pod> -- /bin/sh` |

---

## Lab 02

El lab te presentará un pod con una imagen incorrecta. Deberás diagnosticar y arreglar el problema.

```bash
./curso-labs.sh 2
```
