#!/usr/bin/env bash
# Lab 08 – Add a sidecar to an existing pod that already has a volume mount.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab08"; NS="cka-lab08"
LAB_TITLE="Lab 08 – Add a sidecar with shared volume"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Pod ${CYAN}webapp${NC} runs a single nginx container with an existing
  emptyDir volume mounted at /var/www. Add a SECOND container ${CYAN}sidecar${NC}
  (busybox:1.36) that runs:
      tail -f /var/www/access.log
  using the SAME volume.

  ${BOLD}Tip${NC}
  Save the original pod spec with ${CYAN}kubectl get po webapp -o yaml > pod.yaml${NC},
  edit it and ${CYAN}kubectl replace --force -f pod.yaml${NC}.
  Re-use the existing 'volumes' section – do NOT add a new one.

  ${BOLD}Docs${NC} https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: webapp }
spec:
  volumes:
  - { name: shared-data, emptyDir: {} }
  containers:
  - name: nginx
    image: nginx:1.25
    volumeMounts:
    - { name: shared-data, mountPath: /var/www }
YAML
    kubectl -n "$NS" wait --for=condition=Ready pod/webapp --timeout=120s &>/dev/null
    ok "Pod 'webapp' running with one container. Add the sidecar."
}

validate() {
    local p="$(kubectl -n "$NS" get pod webapp -o json 2>/dev/null)"
    [[ -z "$p" ]] && { err "Pod missing"; return 1; }
    [[ "$(echo "$p" | jq '.spec.containers | length')" -eq 2 ]] || { err "Pod must have exactly 2 containers"; return 1; }
    echo "$p" | jq -e '.spec.containers[] | select(.name=="sidecar") | .image | test("busybox")' &>/dev/null \
        || { err "Second container must be named 'sidecar' using busybox image"; return 1; }
    [[ "$(echo "$p" | jq '.spec.volumes | length')" -eq 1 ]] || { err "Should reuse the existing single 'volumes' entry"; return 1; }
    echo "$p" | jq -e '.spec.containers[] | select(.name=="sidecar") | .volumeMounts[] | select(.mountPath=="/var/www")' &>/dev/null \
        || { err "sidecar must mount the shared volume at /var/www"; return 1; }
    ok "Sidecar added correctly."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Pods are immutable in many fields; export YAML, edit, and 'kubectl replace --force'."
    elif [[ $a -lt 4 ]]; then info "Add the sidecar under spec.containers[]; mount 'shared-data' at /var/www."
    else                       info "Command:  command: ['sh','-c','tail -f /var/www/access.log']"
    fi
}

solution() {
cat <<EOF

  kubectl -n ${NS} get pod webapp -o yaml > /tmp/webapp.yaml
  # Edit /tmp/webapp.yaml and add under spec.containers:
  #
  # - name: sidecar
  #   image: busybox:1.36
  #   command: ["sh","-c","tail -f /var/www/access.log"]
  #   volumeMounts:
  #   - { name: shared-data, mountPath: /var/www }
  #
  kubectl -n ${NS} replace --force -f /tmp/webapp.yaml

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
