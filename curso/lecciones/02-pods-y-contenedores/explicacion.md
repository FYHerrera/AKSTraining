# Guía de Explicación — Lección 02: Pods y Contenedores

> Guía slide-por-slide para el instructor. Cada sección corresponde a un slide de la PPT.
> Tiempo estimado total: 35-40 min de teoría + 15-20 min de lab.

---

## Slide 1 — Título

**Qué decir:**
> "Ahora que conocen los basics de kubectl, vamos a profundizar en la unidad más fundamental de Kubernetes: el Pod. Hoy vamos a entender el ciclo de vida de un pod, cómo funcionan las imágenes de contenedores, y cómo diagnosticar los errores más comunes."

**Contexto para el instructor:**
- Título: *Pods y Contenedores*
- Subtítulo: *Ciclo de vida de pods, diagnosticar errores de imagen y arreglar deployments*
- Conectar con la lección anterior: en la 01 usamos `kubectl get pods`, ahora entenderemos qué significan los estados que vimos

---

## Slide 2 — Sección: ¿Qué es un Pod?

**Qué decir:**
> "La unidad desplegable más pequeña en Kubernetes."

**Transición:** Simplemente pasar al siguiente slide rápido — este es un separador de sección.

---

## Slide 3 — Anatomía de un Pod (icon cards)

**Qué decir:**
> "Un Pod NO es un contenedor — es un envoltorio alrededor de uno o más contenedores. Piensen en el pod como una 'casita' donde viven los contenedores juntos."

**Explicar cada tarjeta:**

| Icono | Concepto | Explicación |
|-------|----------|-------------|
| 📦 | **Contenedor(es)** | "Uno o más contenedores ejecutando tu app. Lo clave: comparten la misma red — se comunican por localhost — y los mismos volúmenes de almacenamiento." |
| 🌐 | **IP del Pod** | "Cada pod recibe su propia IP única dentro del cluster. Otros pods pueden hablar directamente con esta IP. No confundir con la IP del nodo." |
| 💾 | **Almacenamiento Compartido** | "Si defines un volumen en el pod, cualquier contenedor dentro del mismo pod puede montarlo. Esto permite compartir archivos entre contenedores." |
| ⚡ | **Efímero** | "Los pods son desechables. Cuando un pod muere, **todo lo que estaba adentro desaparece**. No se repara, se crea uno nuevo. Por eso existen los volúmenes persistentes, que veremos en la Lección 06." |

**Tip para el instructor:** Preguntar al grupo: *"¿Qué pasa con los datos si un pod muere?"* → Reforzar que se pierden a menos que uses PersistentVolumes.

---

## Slide 4 — Manifiesto YAML de un Pod (code)

**Qué decir:**
> "Así se ve un pod en YAML. No necesitan memorizar esto, pero quiero que noten las partes importantes."

**Puntos clave a señalar:**

```yaml
metadata:
  name: web-app              # Nombre del pod
  labels:
    app: web-app             # Labels → los usamos para conectar con Services
spec:
  containers:
  - name: nginx              # Nombre del contenedor (puede haber varios)
    image: nginx:1.25         # registro/repo:tag ← AQUÍ es donde ocurren errores
    resources:
      requests:              # Mínimo garantizado por el scheduler
        cpu: 100m            # 100 milicores = 0.1 CPU
        memory: 128Mi
      limits:                # Techo máximo
        cpu: 500m
        memory: 256Mi
```

**Enfatizar:**
- `image: nginx:1.25` → Si este tag está mal, obtendremos ImagePullBackOff (el error de hoy)
- `requests` vs `limits` → Lo veremos más adelante en la lección
- `labels` → Recordar de Lección 01 que los Services usan labels para encontrar pods

---

## Slide 5 — Sección: Ciclo de Vida del Pod

**Qué decir:**
> "Entender los estados de un pod es clave para troubleshooting. Cuando algo falla, el estado del pod les dice inmediatamente la categoría del problema."

---

## Slide 6 — Flujo del Ciclo de Vida (flow diagram)

**Qué decir:**
> "Todo pod pasa por estos estados. Veámoslos en orden."

**Recorrer el flujo:**

```
Pending  →  Running  →  Succeeded / Failed
```

| Estado | Color | Explicación |
|--------|-------|-------------|
| **Pending** | 🟠 Naranja | "Esperando a que el scheduler le asigne un nodo, o esperando que se descargue la imagen. Si ven un pod atascado en Pending, probablemente no hay recursos suficientes." |
| **Running** | 🟢 Verde | "Al menos un contenedor está corriendo. Este es el estado normal. No significa que la app esté sana — solo que el contenedor arrancó." |
| **Succeeded** | 🔵 Azul | "Todos los contenedores terminaron con código 0. Esto es normal para Jobs y CronJobs, no para pods de larga duración." |
| **Failed** | 🔴 Rojo | "Al menos un contenedor terminó con error (código de salida ≠ 0). Kubernetes intentará recrearlo dependiendo de la restartPolicy." |

---

## Slide 7 — Estados de Error (tabla)

**Qué decir:**
> "Estos son los estados de error que van a encontrar en el día a día de troubleshooting. Memoricen estos cinco."

**Recorrer la tabla enfatizando la causa común:**

| Estado | Qué decir |
|--------|-----------|
| **ImagePullBackOff** | "No puede descargar la imagen. Causa más común: el nombre o tag están mal escritos. También pasa con registros privados sin auth. **Este es el error del lab de hoy.**" |
| **ErrImagePull** | "Es el primer intento fallido. Después de varios reintentos, cambia a ImagePullBackOff. Si ven ErrImagePull, en unos segundos verán ImagePullBackOff." |
| **CrashLoopBackOff** | "El contenedor arranca, crashea, Kubernetes lo reinicia, crashea de nuevo... loop infinito. Causa: error en la app, comando incorrecto, configuración faltante. Lo veremos en la Lección 03." |
| **OOMKilled** | "Out Of Memory Killed. El contenedor usó más memoria que su límite. Kubernetes lo mata inmediatamente. Causa: límite muy bajo o memory leak." |
| **Pending (atascado)** | "El pod no puede ser programado en ningún nodo. Causa: no hay suficiente CPU o memoria disponible en el cluster." |

**Pregunta al grupo:** *"Si ven un pod en ImagePullBackOff, ¿hay logs disponibles?"* → No, porque el contenedor nunca arrancó.

---

## Slide 8 — Sección: Imágenes de Contenedores

**Qué decir:**
> "Vamos a ver cómo Kubernetes encuentra y descarga tu aplicación."

---

## Slide 9 — Formato de Imagen (highlight)

**Qué decir:**
> "Las imágenes siguen el formato: registro / repositorio : tag"

**Recorrer los ejemplos:**

| Imagen | Explicación |
|--------|-------------|
| `nginx:1.25` | "Docker Hub es el registro implícito. Es el más común para imágenes públicas." |
| `mcr.microsoft.com/azuredocs/aci-helloworld` | "Microsoft Container Registry. Aquí están las imágenes oficiales de Microsoft." |
| `myacr.azurecr.io/myapp:v2` | "Azure Container Registry privado. Aquí guardan ustedes las imágenes de su empresa. Necesita autenticación." |

**Enfatizar:**
> "Si el tag no existe, Kubernetes reporta ErrImagePull. Después de fallos repetidos, el estado cambia a ImagePullBackOff. Es exactamente lo que vamos a ver en el lab."

---

## Slide 10 — Pull de Imagen: Éxito vs Fallo (dos columnas)

**Qué decir:**
> "Comparemos qué necesita un pull exitoso vs qué causa un fallo."

**Columna izquierda — ✅ Pull Exitoso:**
- La imagen y el tag existen en el registro
- El cluster tiene acceso de red al registro
- Si es privado: `imagePullSecrets` configurado
- Pod transiciona: Pending → Running

**Columna derecha — ❌ Pull Fallido:**
- Nombre de imagen mal escrito o tag inexistente
- Registro inalcanzable (firewall, DNS)
- Registro privado sin credenciales
- Pod queda atascado en ImagePullBackOff

**Tip:** Mencionar que en entornos enterprise, el firewall bloqueando el registro es un problema muy común.

---

## Slide 11 — Sección: Diagnosticando Problemas de Pods

**Qué decir:**
> "Ahora viene la parte más importante de la lección: el proceso de troubleshooting en 3 pasos. Esto lo van a usar TODOS los días."

---

## Slide 12 — Flujo de Diagnóstico (flow diagram)

**Qué decir:**
> "Este flujo de 3 pasos resuelve el 80% de los problemas con pods."

**Recorrer el flujo con énfasis:**

| Paso | Comando | Qué buscar |
|------|---------|------------|
| **1. GET** | `kubectl get pods` | "Ver la columna STATUS. ¿ImagePullBackOff? ¿CrashLoopBackOff? Eso te dice la categoría del problema." |
| **2. DESCRIBE** | `kubectl describe pod <nombre>` | "Ir directo a la sección EVENTS al final. Ahí Kubernetes te dice exactamente qué pasó y por qué." |
| **3. LOGS** | `kubectl logs <pod>` | "Ver la salida de la aplicación. Usar `--previous` si el contenedor crasheó. NOTA: Si es ImagePullBackOff, NO hay logs porque el contenedor nunca arrancó." |

**Repetir:** *"GET → DESCRIBE → LOGS. GET → DESCRIBE → LOGS."*

---

## Slide 13 — Paso 1: kubectl get pods (code)

**Qué decir:**
> "Primer paso: siempre empezar con `kubectl get pods`."

**Señalar en la salida:**
```
NAME                       READY   STATUS             RESTARTS   AGE
web-app-6d8f9b4c7-abc12   0/1     ImagePullBackOff   0          5m
web-app-6d8f9b4c7-def34   0/1     ImagePullBackOff   0          5m
web-app-6d8f9b4c7-ghi56   0/1     ImagePullBackOff   0          5m
```

- **STATUS = ImagePullBackOff** → Problema de imagen
- **READY = 0/1** → Cero contenedores listos de uno esperado
- **3 pods fallando** → Esto es un Deployment con 3 réplicas, no un pod suelto
- **RESTARTS = 0** → No ha reiniciado porque nunca arrancó

---

## Slide 14 — Paso 2: kubectl describe pod — ¡EVENTS! (code)

**Qué decir:**
> "Ahora hacemos describe del pod y vamos DIRECTO al final, a la sección Events."

**Señalar cada línea relevante:**
```
Events:
  Normal   Pulling    5m    Pulling image "nginx:99.99.99-nonexistent"  ← la imagen
  Warning  Failed     5m    Failed to pull: tag does not exist          ← la causa
  Warning  Failed     5m    Error: ErrImagePull                         ← primer intento
  Warning  Failed     4m    Error: ImagePullBackOff                     ← reintentos
```

**Enfatizar:**
> "¿Ven? Los Events nos dicen EXACTAMENTE qué imagen falló y por qué. 'nginx:99.99.99-nonexistent' — obviamente ese tag no existe. Esta es la técnica #1 de troubleshooting en Kubernetes."

---

## Slide 15 — Insight Clave: Los Events Cuentan la Historia (highlight)

**Qué decir:**
> "Quiero que se graben esto: **la sección Events en kubectl describe SIEMPRE revela la causa raíz.**"

**Tips prácticos:**
- Siempre ir al FINAL de la salida de describe para encontrar Events
- Buscar eventos tipo **Warning** — indican problemas
- La columna **Message** contiene los detalles específicos del error
- En nuestro caso: *"Failed to pull image nginx:99.99.99-nonexistent"*

---

## Slide 16 — Paso 3: kubectl logs (code)

**Qué decir:**
> "El tercer paso es ver los logs de la aplicación."

**Comandos clave:**
```bash
kubectl logs <pod>                          # Logs normales
kubectl logs <pod> --previous               # Logs del contenedor anterior (si crasheó)
kubectl logs -l app=web-app --all-containers # Por label (útil con múltiples réplicas)
```

**Punto importante:**
> "Para ImagePullBackOff, **NO hay logs** porque el contenedor nunca arrancó. Logs son útiles para CrashLoopBackOff, no para errores de imagen."

---

## Slide 17 — Sección: Arreglando un Deployment Roto

**Qué decir:**
> "Ya sabemos diagnosticar. Ahora vamos del diagnóstico a la solución."

---

## Slide 18 — Encontrar la Imagen Incorrecta (code)

**Qué decir:**
> "Una vez que describe nos dijo que la imagen es incorrecta, confirmamos qué imagen tiene el Deployment."

```bash
kubectl get deployment web-app -o yaml | grep image:
#   image: nginx:99.99.99-nonexistent    <-- ¡EL PROBLEMA!
```

**Nota:** `kubectl get deployment web-app -o wide` también muestra la imagen en una columna.

---

## Slide 19 — Arreglar la Imagen (code)

**Qué decir:**
> "Para arreglar, tenemos dos opciones."

**Opción 1 (recomendada):**
```bash
kubectl set image deployment/web-app nginx=nginx:1.25
```
> "La forma más directa. Noten la sintaxis: `nombre-contenedor=nueva-imagen:tag`."

**Opción 2:**
```bash
kubectl edit deployment web-app
# Cambiar manualmente la línea de image
```
> "Abre un editor. Útil para cambios más complejos, pero para solo cambiar la imagen, `set image` es más rápido."

**Verificación:**
```bash
kubectl get pods -w   # El -w es 'watch' — observa en tiempo real
```
> "Después de arreglar, los pods viejos se eliminan y nuevos pods con la imagen correcta se crean. Deben ver los 3 transicionar a Running."

---

## Slide 20 — Sección: Pods Multi-Contenedor

**Qué decir:**
> "Hasta ahora hemos visto pods con un solo contenedor. Pero un pod puede tener varios."

---

## Slide 21 — Patrones Multi-Contenedor (dos columnas)

**Qué decir:**
> "Hay dos patrones principales."

**Init Containers (columna izquierda):**
- Se ejecutan **ANTES** del contenedor principal
- Deben completarse exitosamente primero
- Uso: migraciones de base de datos, setup de configuración, esperar que dependencias estén listas
- Si init falla: Pod en `Init:Error`

> "Ejemplo clásico: un init container que espera a que la base de datos esté disponible antes de arrancar la app."

**Sidecar Containers (columna derecha):**
- Se ejecutan **JUNTO** al contenedor principal
- Comparten red y almacenamiento
- Uso: agentes de logging, proxies (como Envoy/Istio), monitoreo
- Si el sidecar crashea: puede afectar la app

> "Ejemplo clásico: un sidecar que recolecta logs de tu app y los envía a un sistema centralizado."

---

## Slide 22 — Sección: Gestión de Recursos

**Qué decir:**
> "Requests, Limits y OOMKilled — entender esto evita muchos problemas en producción."

---

## Slide 23 — Requests vs Limits (dos columnas)

**Qué decir:**
> "Esta es la diferencia clave que muchos confunden."

**Requests — Mínimo (columna izquierda):**
- Lo que el pod tiene **garantizado**
- El scheduler usa esto para decidir en qué nodo colocar el pod
- Si ningún nodo tiene capacidad suficiente → pod queda **Pending**
- Comando útil: `kubectl describe node | grep Allocated`

**Limits — Máximo (columna derecha):**
- El techo máximo que un contenedor puede usar
- Exceder límite de **CPU** → **throttled** (se hace más lento, pero NO muere)
- Exceder límite de **memoria** → **OOMKilled** inmediatamente
- Comando útil: `kubectl top pods` (uso actual)

**Enfatizar la diferencia CPU vs Memoria:**
> "CPU se throttlea — tu app se pone lenta pero sigue viva. Memoria se mata — OOMKilled, game over. Por eso los limits de memoria son críticos."

---

## Slide 24 — Referencia Completa de Diagnóstico (tabla)

**Qué decir:**
> "Esta es su tabla de referencia rápida. Guárdenla o tómenle screenshot."

| Síntoma | Comando | Qué Buscar |
|---------|---------|------------|
| Pod no arranca | `kubectl get pods` | Columna STATUS |
| ¿Por qué falla? | `kubectl describe pod <nombre>` | Sección Events al final |
| App crashea | `kubectl logs <pod>` | Mensajes de error |
| Crash anterior | `kubectl logs <pod> --previous` | Logs antes del reinicio |
| Imagen incorrecta | `kubectl get deploy -o yaml \| grep image` | Verificar image:tag |
| Arreglar imagen | `kubectl set image deploy/<name> <ctr>=<img:tag>` | Pods → Running |

---

## Slide 25 — Preparación para el Lab (tabla)

**Qué decir:**
> "Antes de entrar al lab, estos son los 5 pasos que van a necesitar."

| Paso | Comando | Propósito |
|------|---------|-----------|
| 1 | `kubectl get pods` | Ver qué pods están fallando y su estado |
| 2 | `kubectl describe pod <nombre>` | Leer Events para encontrar la imagen incorrecta |
| 3 | `kubectl get deploy web-app -o yaml \| grep image` | Confirmar el tag incorrecto |
| 4 | `kubectl set image deployment/web-app nginx=nginx:1.25` | Corregir la imagen |
| 5 | `kubectl get pods -w` | Observar los pods recuperarse a Running |

**Transición al lab:**
> "Ahora es su turno. Van a abrir Cloud Shell y correr el script del lab."

---

## Slide 26 — Lab 02: Arreglar ImagePullBackOff

**Qué decir:**
> "Un deployment llamado 'web-app' tiene 3 réplicas atascadas en ImagePullBackOff. El tag de la imagen es incorrecto. Usen el proceso de diagnóstico en 3 pasos — get, describe, fix — para identificar la imagen incorrecta y corregirla. Las 3 réplicas deben estar Running para aprobar."

**Comando del lab:**
```bash
./lab-02.sh
```

**Si alguien se atora:**
- "¿Ya hiciste `kubectl get pods`? ¿Qué dice STATUS?"
- "¿Ya hiciste `kubectl describe pod`? ¿Qué dice en Events?"
- "¿Ya encontraste la imagen? Ahora usa `kubectl set image` para corregirla."

**Solución rápida (solo si es necesario):**
```bash
kubectl set image deployment/web-app nginx=nginx:1.25
```

---

## Notas Generales para el Instructor

### Errores comunes de los estudiantes en este lab:
1. Intentar eliminar los pods en vez de arreglar el Deployment (los pods se recrean con la misma imagen rota)
2. Olvidar el nombre del contenedor en `kubectl set image` (necesitan `nginx=nginx:1.25`, no solo `nginx:1.25`)
3. No esperar a que los pods nuevos estén Running antes de declarar éxito

### Preguntas frecuentes:
- **"¿Por qué no simplemente borrar el pod?"** → Porque el Deployment lo recrea con la misma imagen incorrecta. Hay que arreglar el Deployment, no el pod.
- **"¿Qué es el backoff en ImagePullBackOff?"** → Kubernetes espera cada vez más tiempo entre reintentos (backoff exponencial): 10s, 20s, 40s, hasta 5 min.
- **"¿Cómo sé el nombre del contenedor para set image?"** → `kubectl get deployment web-app -o yaml | grep -A2 containers:`

### Conexión con próximas lecciones:
- **Lección 03:** Veremos CrashLoopBackOff con Deployments y rollbacks
- **Lección 04:** Veremos cómo los Services usan labels para encontrar pods
- **Lección 06:** Veremos PersistentVolumes para que los datos sobrevivan a pods efímeros
