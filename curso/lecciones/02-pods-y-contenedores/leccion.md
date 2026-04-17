# Lección 02 – Pods y Contenedores

## Objetivos
- Entender qué es un Pod y su ciclo de vida
- Diagnosticar pods con problemas de imagen (ImagePullBackOff)
- Leer eventos y logs para identificar errores
- Arreglar un Deployment con imagen incorrecta

---

## 1. ¿Qué es un Pod?

Un **Pod** es la unidad más pequeña en Kubernetes. Contiene uno o más contenedores que comparten red y almacenamiento.

### Características clave:
- Cada pod recibe su propia **IP única** dentro del cluster
- Los contenedores dentro del pod se comunican por `localhost`
- Los pods son **efímeros** – cuando mueren, no se reparan; se crean nuevos

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-app
  labels:
    app: web-app
spec:
  containers:
  - name: nginx
    image: nginx:1.25          # registro/repo:tag
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

### Estados normales

| Estado | Significado |
|--------|-------------|
| **Pending** | Esperando ser asignado a un nodo o que se descargue la imagen |
| **Running** | Al menos un contenedor está corriendo |
| **Succeeded** | Todos los contenedores terminaron exitosamente (exit 0) |
| **Failed** | Al menos un contenedor falló (exit ≠ 0) |

### Estados de error (los que verás en troubleshooting)

| Estado | Significado | Causa Común |
|--------|-------------|-------------|
| **ImagePullBackOff** | No puede descargar la imagen del contenedor | Nombre/tag incorrecto, registro privado sin auth |
| **ErrImagePull** | Primer intento de pull falló | La imagen no existe en el registro |
| **CrashLoopBackOff** | El contenedor se reinicia constantemente tras fallar | Error de app, comando incorrecto, config faltante |
| **OOMKilled** | El contenedor excedió el límite de memoria | Límite muy bajo o memory leak |

---

## 3. Imágenes de Contenedores

### Formato
```
registro/repositorio:tag
```

### Ejemplos
```
nginx:1.25                              # Docker Hub (registro implícito)
mcr.microsoft.com/azuredocs/aci-helloworld  # Microsoft Container Registry
myacr.azurecr.io/myapp:v2              # Azure Container Registry privado
```

### ¿Qué pasa cuando el tag no existe?
1. Kubernetes intenta descargar la imagen → **ErrImagePull**
2. Reintenta con backoff exponencial → **ImagePullBackOff**
3. El pod queda atascado hasta que se corrija la imagen

---

## 4. Diagnóstico de Pods – Proceso de 3 Pasos

### Paso 1: Ver estado con `kubectl get pods`
```bash
kubectl get pods
# NAME                       READY   STATUS             RESTARTS   AGE
# web-app-6d8f9b4c7-abc12   0/1     ImagePullBackOff   0          5m
# web-app-6d8f9b4c7-def34   0/1     ImagePullBackOff   0          5m
# web-app-6d8f9b4c7-ghi56   0/1     ImagePullBackOff   0          5m
```
> STATUS te indica la categoría del problema. READY 0/1 = cero contenedores listos.

### Paso 2: Describe (¡SIEMPRE revisar Events!)
```bash
kubectl describe pod web-app-6d8f9b4c7-abc12
```
```
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  5m    default-scheduler  Successfully assigned...
  Normal   Pulling    5m    kubelet            Pulling image "nginx:99.99.99-nonexistent"
  Warning  Failed     5m    kubelet            Failed to pull: tag does not exist
  Warning  Failed     5m    kubelet            Error: ErrImagePull
  Normal   BackOff    4m    kubelet            Back-off pulling image
  Warning  Failed     4m    kubelet            Error: ImagePullBackOff
```
> **Insight clave**: La sección Events SIEMPRE revela la causa raíz. Busca los eventos tipo "Warning".

### Paso 3: Logs (si el contenedor llegó a iniciar)
```bash
kubectl logs web-app-6d8f9b4c7-abc12
kubectl logs web-app-6d8f9b4c7-abc12 --previous    # Si crasheó, ver logs anteriores
kubectl logs -l app=web-app --all-containers         # Todos los pods con ese label
```
> **NOTA**: Para ImagePullBackOff NO hay logs porque el contenedor nunca arrancó.

---

## 5. Arreglando un Deployment con Imagen Incorrecta

### Encontrar la imagen incorrecta
```bash
# Ver la imagen actual del deployment
kubectl get deployment web-app -o wide

# Buscar la imagen en el YAML
kubectl get deployment web-app -o yaml | grep image:
#   image: nginx:99.99.99-nonexistent    <-- ¡EL PROBLEMA!
```

### Corregir la imagen
```bash
# Opción 1: Establecer la imagen correcta directamente
kubectl set image deployment/web-app nginx=nginx:1.25

# Opción 2: Editar el deployment interactivamente
kubectl edit deployment web-app
# Cambiar: image: nginx:99.99.99-nonexistent
# A:       image: nginx:1.25

# Verificar la corrección
kubectl get pods -w   # Observar pods transicionar a Running
```

---

## 6. Pods Multi-Contenedor

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

| Concepto | Qué es | Si se excede |
|----------|--------|--------------|
| **requests** | Mínimo garantizado (el scheduler usa esto) | Pod queda Pending si no hay capacidad |
| **limits** | Máximo que puede usar | CPU → throttled; Memoria → OOMKilled |

```bash
# Ver uso de recursos actual
kubectl top pods
kubectl top nodes

# Si un pod es OOMKilled:
kubectl describe pod <name>  # → State: OOMKilled
```

---

## Resumen – Referencia Rápida

| Síntoma | Comando | Qué Buscar |
|---------|---------|------------|
| Pod no arranca | `kubectl get pods` | Columna STATUS |
| ¿Por qué falla? | `kubectl describe pod <nombre>` | Sección Events al final |
| App crashea | `kubectl logs <pod>` | Mensajes de error |
| Crash anterior | `kubectl logs <pod> --previous` | Logs antes del reinicio |
| Imagen incorrecta | `kubectl get deploy -o yaml \| grep image` | Verificar image:tag |
| Arreglar imagen | `kubectl set image deploy/<name> <ctr>=<img:tag>` | Pods deben ir a Running |

---

## Lab 02 – Arreglar ImagePullBackOff

El lab despliega un **Deployment** llamado `web-app` con **3 réplicas** usando una imagen inexistente (`nginx:99.99.99-nonexistent`). Todos los pods quedan en ImagePullBackOff.

### Tu tarea:
1. Diagnosticar con `kubectl get pods` y `kubectl describe pod`
2. Identificar la imagen incorrecta
3. Corregirla con `kubectl set image deployment/web-app nginx=nginx:1.25`
4. Verificar que las 3 réplicas estén Running

```bash
./lab-02.sh
```
