#!/usr/bin/env bash
# Lab 32 – Add a sidecar that streams an app log file via kubectl logs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab32"; NS="cka-lab32"
LAB_TITLE="Lab 32 – Streaming sidecar for legacy app logs"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Deployment ${CYAN}synergy-deployment${NC} runs a legacy app that writes to
  /var/log/synergy-deployment.log. Add a sidecar container ${CYAN}log-streamer${NC}
  (busybox:stable) that runs:
      /bin/sh -c 'tail -n+1 -f /var/log/synergy-deployment.log'
  Both containers must share an emptyDir volume mounted at /var/log.
  Do NOT change the existing main container spec apart from required additions.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: synergy-deployment }
spec:
  replicas: 1
  selector: { matchLabels: { app: synergy } }
  template:
    metadata: { labels: { app: synergy } }
    spec:
      containers:
      - name: synergy
        image: busybox:1.36
        command: ["sh","-c"]
        args:
        - |
          mkdir -p /var/log
          while true; do echo "[$(date)] synergy event" >> /var/log/synergy-deployment.log; sleep 2; done
        volumeMounts:
        - { name: applogs, mountPath: /var/log }
      volumes:
      - { name: applogs, emptyDir: {} }
YAML
    kubectl -n "$NS" rollout status deploy/synergy-deployment --timeout=120s >/dev/null
    ok "Deployment ready. Add the log-streamer sidecar."
}

validate() {
    local d="$(kubectl -n "$NS" get deploy synergy-deployment -o json 2>/dev/null)"
    [[ "$(echo "$d" | jq '.spec.template.spec.containers | length')" -eq 2 ]] \
        || { err "Pod template must have exactly 2 containers"; return 1; }
    echo "$d" | jq -e '.spec.template.spec.containers[] | select(.name=="log-streamer" and (.image|test("busybox")))' &>/dev/null \
        || { err "Sidecar 'log-streamer' (busybox) missing"; return 1; }
    echo "$d" | jq -e '.spec.template.spec.containers[] | select(.name=="log-streamer") | .args[]?, .command[]? | select(test("tail -n\\+1 -f /var/log/synergy-deployment.log"))' &>/dev/null \
        || { err "Sidecar must run: tail -n+1 -f /var/log/synergy-deployment.log"; return 1; }
    echo "$d" | jq -e '.spec.template.spec.containers[] | select(.name=="log-streamer") | .volumeMounts[] | select(.mountPath=="/var/log")' &>/dev/null \
        || { err "Sidecar must mount the shared volume at /var/log"; return 1; }
    [[ "$(echo "$d" | jq '.spec.template.spec.volumes | length')" -eq 1 ]] || { err "Re-use the single existing volume"; return 1; }
    kubectl -n "$NS" rollout status deploy/synergy-deployment --timeout=60s >/dev/null || { err "Rollout not ready"; return 1; }
    ok "Sidecar added and rolled out."
    info "Verify:  kubectl -n $NS logs deploy/synergy-deployment -c log-streamer --tail=5"
    return 0
}
hint() {
    local a="${1:-0}"
    if [[ $a -lt 2 ]]; then info "kubectl -n $NS edit deploy synergy-deployment — add a 2nd container under spec.template.spec.containers."
    else                    info "Use args: ['/bin/sh','-c','tail -n+1 -f /var/log/synergy-deployment.log']  and the same volumeMount as the main container."
    fi
}
solution() {
cat <<EOF

  kubectl -n ${NS} patch deploy synergy-deployment --type=json -p='[
    {"op":"add","path":"/spec/template/spec/containers/-","value":{
      "name":"log-streamer",
      "image":"busybox:stable",
      "args":["/bin/sh","-c","tail -n+1 -f /var/log/synergy-deployment.log"],
      "volumeMounts":[{"name":"applogs","mountPath":"/var/log"}]
    }}
  ]'

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
