#!/usr/bin/env bash
# Lab 09 – Create PVC, increase its size and record the action.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab09"; NS="cka-lab09"
LAB_TITLE="Lab 09 – Create PVC, resize and record"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Create PVC ${CYAN}mypvc${NC} (100Mi) in '${NS}' bound to a Pod ${CYAN}myapp${NC}
  (nginx). Then increase the PVC to ${CYAN}200Mi${NC} and ensure the change is
  recorded (managedFields / annotation showing edit).

  ${BOLD}Note${NC}
  In your live cluster the default StorageClass MUST allow expansion
  (allowVolumeExpansion: true). On AKS, default classes already do.
"

deploy() {
    ensure_namespace "$NS"
    ok "Namespace ready. Build PVC + Pod yourself, then resize the PVC."
}

validate() {
    local pvc="$(kubectl -n "$NS" get pvc mypvc -o json 2>/dev/null)"
    [[ -z "$pvc" ]] && { err "PVC mypvc missing"; return 1; }
    [[ "$(echo "$pvc" | jq -r '.spec.resources.requests.storage')" == "200Mi" ]] \
        || { err "PVC requested storage must equal 200Mi"; return 1; }
    kubectl -n "$NS" get pod myapp &>/dev/null || { err "Pod myapp missing"; return 1; }
    ok "PVC resized to 200Mi."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Create PVC at 100Mi, then 'kubectl edit pvc mypvc' and change requests.storage to 200Mi."
    else                       info "Use:  kubectl -n $NS edit pvc mypvc --record (the --record flag adds the action to annotations)."
    fi
}

solution() {
cat <<EOF

  kubectl -n ${NS} apply -f - <<'YAML'
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata: { name: mypvc }
  spec:
    accessModes: [ReadWriteOnce]
    resources: { requests: { storage: 100Mi } }
  ---
  apiVersion: v1
  kind: Pod
  metadata: { name: myapp }
  spec:
    volumes:
    - { name: data, persistentVolumeClaim: { claimName: mypvc } }
    containers:
    - name: nginx
      image: nginx:1.25
      volumeMounts: [{ name: data, mountPath: /data }]
  YAML

  kubectl -n ${NS} edit pvc mypvc --record    # change storage to 200Mi

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
