#!/usr/bin/env bash
# Lab 01 – Create a PersistentVolume (hostPath) and bind it via a PVC + Pod.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab01"; NS="cka-lab01"
LAB_TITLE="Lab 01 – Create a PersistentVolume"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Create a hostPath PV named ${CYAN}task-pv${NC} of 1Gi at /mnt/data with
  ReadWriteOnce access. Then create a PVC ${CYAN}task-pvc${NC} (500Mi) and a
  Pod ${CYAN}task-pv-pod${NC} (nginx) that mounts the PVC at /usr/share/nginx/html.

  ${BOLD}Docs${NC} https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/
"

deploy()   { ensure_namespace "$NS"; info "Nothing pre-created. Build PV, PVC and Pod yourself in namespace '${NS}'."; }

validate() {
    local pv pvc pod
    pv=$(kubectl get pv task-pv -o json 2>/dev/null) || { err "PV 'task-pv' missing"; return 1; }
    [[ "$(echo "$pv" | jq -r '.spec.capacity.storage')" == "1Gi" ]] || { err "PV capacity != 1Gi"; return 1; }
    echo "$pv" | jq -e '.spec.accessModes | index("ReadWriteOnce")' &>/dev/null || { err "PV must allow RWO"; return 1; }
    pvc=$(kubectl -n "$NS" get pvc task-pvc -o json 2>/dev/null) || { err "PVC missing"; return 1; }
    [[ "$(echo "$pvc" | jq -r '.status.phase')" == "Bound" ]] || { err "PVC not Bound"; return 1; }
    pod=$(kubectl -n "$NS" get pod task-pv-pod -o json 2>/dev/null) || { err "Pod missing"; return 1; }
    [[ "$(echo "$pod" | jq -r '.status.phase')" == "Running" ]] || { err "Pod not Running"; return 1; }
    ok "PV, PVC and Pod look good."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Read the docs page; copy the PV / PVC / Pod manifests from the example."
    elif [[ $a -lt 4 ]]; then info "PV is cluster-scoped; PVC and Pod are in '${NS}'. Don't forget storageClassName: \"\" or 'manual'."
    else                       info "Use the same storageClassName ('manual') on PV and PVC so they bind."
    fi
}

solution() {
cat <<EOF

  kubectl apply -f - <<'YAML'
  apiVersion: v1
  kind: PersistentVolume
  metadata: { name: task-pv, labels: { type: local } }
  spec:
    storageClassName: manual
    capacity: { storage: 1Gi }
    accessModes: [ReadWriteOnce]
    hostPath: { path: "/mnt/data" }
  ---
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata: { name: task-pvc, namespace: ${NS} }
  spec:
    storageClassName: manual
    accessModes: [ReadWriteOnce]
    resources: { requests: { storage: 500Mi } }
  ---
  apiVersion: v1
  kind: Pod
  metadata: { name: task-pv-pod, namespace: ${NS} }
  spec:
    volumes:
    - name: task-pv-storage
      persistentVolumeClaim: { claimName: task-pvc }
    containers:
    - name: web
      image: nginx
      volumeMounts:
      - { name: task-pv-storage, mountPath: /usr/share/nginx/html }
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
