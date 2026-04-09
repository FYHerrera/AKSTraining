# Lección 06 – Storage y Volúmenes

## Objetivos
- Entender PersistentVolume (PV), PersistentVolumeClaim (PVC) y StorageClass
- Diagnosticar PVCs atascados en Pending
- Conocer los tipos de almacenamiento en AKS

---

## 1. El Problema

Los containers son efímeros – cuando un pod se reinicia, sus datos se pierden. Para persistir datos, usamos **Volúmenes**.

---

## 2. Conceptos Clave

```
StorageClass      →  Define CÓMO se crea el almacenamiento
PersistentVolume  →  Un disco real provisionado
PVC (Claim)       →  La solicitud de un pod para obtener almacenamiento
```

```
Pod → PVC → PV → Azure Disk / Azure Files
        ↑
  StorageClass (provisionador)
```

---

## 3. StorageClass en AKS

AKS viene con StorageClasses predefinidas:

```bash
kubectl get storageclass
```

| StorageClass | Tipo | Acceso |
|-------------|------|--------|
| `default` / `managed` | Azure Managed Disk (SSD) | ReadWriteOnce |
| `managed-premium` | Azure Premium SSD | ReadWriteOnce |
| `managed-csi` | Azure Disk CSI | ReadWriteOnce |
| `managed-csi-premium` | Azure Premium Disk CSI | ReadWriteOnce |
| `azurefile` | Azure Files | ReadWriteMany |
| `azurefile-csi` | Azure Files CSI | ReadWriteMany |
| `azurefile-csi-premium` | Azure Files Premium CSI | ReadWriteMany |

### Modos de acceso

| Modo | Abreviación | Significado |
|------|-------------|-------------|
| ReadWriteOnce | RWO | Un solo nodo puede montar lectura/escritura |
| ReadWriteMany | RWX | Múltiples nodos pueden montar lectura/escritura |
| ReadOnlyMany | ROX | Múltiples nodos en solo lectura |

> **Regla importante**: Azure Disks solo soportan RWO. Si necesitas RWX → usa Azure Files.

---

## 4. PersistentVolumeClaim (PVC)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: managed-csi        # Debe existir
  resources:
    requests:
      storage: 10Gi
```

### Usar en un Pod

```yaml
spec:
  containers:
  - name: app
    image: myapp:v1
    volumeMounts:
    - name: data
      mountPath: /data                 # Ruta dentro del container
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc              # Nombre del PVC
```

---

## 5. Ciclo de Vida del PVC

```
PVC creado → Pending → Bound → (en uso) → Released
```

| Estado | Significado |
|--------|-------------|
| **Pending** | Esperando que se provisione el PV |
| **Bound** | PV asignado exitosamente |
| **Lost** | El PV fue eliminado pero el PVC sigue |

---

## 6. Errores Comunes

### PVC stuck en Pending

```bash
kubectl get pvc
# NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# data-pvc   Pending                                       wrong-sc       5m
```

**Causas**:

| Causa | Diagnóstico |
|-------|-------------|
| StorageClass no existe | `kubectl get sc` → verificar nombre |
| Zona incorrecta | Disco en zona 1, nodo en zona 2 |
| Cuota excedida | `kubectl describe pvc` → Events |
| accessModes incompatible | RWX con Azure Disk (solo soporta RWO) |

```bash
# SIEMPRE describe el PVC para ver Events
kubectl describe pvc data-pvc
```

### StorageClass no existe

```bash
kubectl describe pvc data-pvc
# Events:
#  Warning  ProvisioningFailed  storageclass "fast-ssd" not found
```

**Fix**: Cambiar el storageClassName a uno que exista:
```bash
kubectl get sc    # Ver StorageClasses disponibles
```

### WaitForFirstConsumer

Algunas StorageClasses usan `WaitForFirstConsumer` – el PVC queda en Pending hasta que un Pod lo use. Esto es **normal**.

```bash
kubectl describe sc managed-csi
# VolumeBindingMode: WaitForFirstConsumer
```

---

## 7. Azure Disk vs Azure Files

| Característica | Azure Disk | Azure Files |
|---------------|-----------|-------------|
| Acceso | RWO (un nodo) | RWX (múltiples nodos) |
| Performance | Alta (SSD/Premium) | Media |
| Caso de uso | Bases de datos | Archivos compartidos |
| Cambio de nodo | Detach/Attach (lento) | Ningún problema |
| StorageClass | managed-csi | azurefile-csi |

---

## 8. Diagnóstico Rápido

```bash
# Ver PVCs y su estado
kubectl get pvc

# Ver PVs (discos provisionados)
kubectl get pv

# Ver StorageClasses
kubectl get sc

# Diagnosticar PVC Pending
kubectl describe pvc <name>

# Ver eventos de provisioning
kubectl get events --sort-by='.lastTimestamp' | grep -i pvc

# Ver si el pod está esperando el volumen
kubectl describe pod <name> | grep -A5 "Volumes:"
```

---

## Resumen

| Problema | Qué hacer |
|----------|-----------|
| PVC Pending | `kubectl describe pvc` → check Events |
| StorageClass no found | `kubectl get sc` → usar nombre correcto |
| AccessMode error | Disk=RWO, Files=RWX |
| WaitForFirstConsumer | Normal, se resuelve cuando un pod lo usa |

---

## Lab 06

El lab tiene un PVC atascado en Pending. Deberás diagnosticar la causa y arreglarlo.

```bash
./curso-labs.sh 6
```
