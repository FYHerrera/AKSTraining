# Curso AKS Troubleshooting – Para Ingenieros de Soporte

Curso práctico de 10 lecciones con labs interactivos. Cada lección enseña conceptos clave y el lab correspondiente los pone a prueba.

## Estructura del Curso

| # | Lección | Lab | Dificultad |
|---|---------|-----|------------|
| 01 | Fundamentos de kubectl | Scavenger Hunt: encontrar info del cluster | ★☆☆ |
| 02 | Pods y Contenedores | Arreglar un pod con imagen incorrecta | ★☆☆ |
| 03 | Deployments y ReplicaSets | Arreglar un rollout fallido | ★★☆ |
| 04 | Services y Networking | Servicio no conecta con los pods | ★★☆ |
| 05 | ConfigMaps y Secrets | App falla por configuración faltante | ★★☆ |
| 06 | Storage y Volúmenes | PVC atascado en Pending | ★★☆ |
| 07 | Network Policies | Tráfico bloqueado entre pods | ★★★ |
| 08 | Gestión de Nodos | Nodos con taints impiden scheduling | ★★★ |
| 09 | Integración Azure (NSG/LB) | NSG bloquea tráfico externo | ★★★ |
| 10 | Troubleshooting Avanzado | Escenario multi-problema | ★★★ |

## Cómo usar el curso

### 1. Leer la lección
```
# Cada lección está en LABs/curso/lecciones/
# Leer en orden antes de hacer el lab
```

### 2. Hacer el lab correspondiente

**Azure Cloud Shell (recomendado):**
```bash
chmod +x curso-labs.sh
./curso-labs.sh          # Menú interactivo
./curso-labs.sh 1        # Lab específico por número
```

**Bash local (WSL/Linux/Mac):**
```bash
cd LABs/curso/labs/bash
chmod +x curso-lab-*.sh
./curso-lab-01-kubectl.sh
```

## Orden recomendado

Las lecciones van de lo básico a lo avanzado. Se recomienda:

1. **Semana 1** – Lecciones 01-03 (Fundamentos)
2. **Semana 2** – Lecciones 04-06 (Networking y Config)
3. **Semana 3** – Lecciones 07-08 (Políticas y Nodos)
4. **Semana 4** – Lecciones 09-10 (Azure e Integración)

## Requisitos

- Suscripción Azure activa
- Azure Cloud Shell o terminal con `az`, `kubectl`, `jq`
- `az login` ejecutado antes de cada sesión

## Costo estimado

Cada lab crea un cluster AKS temporal (~$0.40/hr con Standard_D8ds_v5).
Labs típicos duran 30-60 min. **Siempre hacer cleanup al terminar.**
