#!/usr/bin/env bash
# Lab 20 – Namespace + ResourceQuota + Pod with requests/limits.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab20"; NS="dev-team"
LAB_TITLE="Lab 20 – ResourceQuota + Pod resources"
LAB_DESC="
  ${BOLD}Scenario${NC}
    1. Create namespace ${CYAN}dev-team${NC}.
    2. Create a ResourceQuota ${CYAN}team-quota${NC} in dev-team:
         requests.cpu=2, requests.memory=4Gi, limits.cpu=4, limits.memory=8Gi
    3. Create a Pod ${CYAN}quota-pod${NC} (image nginx) WITH explicit
       requests AND limits for CPU and memory (any values within the quota).
"

deploy() { ensure_namespace "$NS"; ok "Namespace dev-team ready. Create the quota and the pod."; }

validate() {
    local rq="$(kubectl -n "$NS" get resourcequota team-quota -o json 2>/dev/null)"
    [[ -z "$rq" ]] && { err "ResourceQuota 'team-quota' missing"; return 1; }
    for k in requests.cpu requests.memory limits.cpu limits.memory; do
        echo "$rq" | jq -e ".spec.hard.\"$k\"" &>/dev/null || { err "Quota missing key $k"; return 1; }
    done
    local p="$(kubectl -n "$NS" get pod quota-pod -o json 2>/dev/null)"
    [[ -z "$p" ]] && { err "Pod 'quota-pod' missing"; return 1; }
    for j in '.spec.containers[0].resources.requests.cpu' '.spec.containers[0].resources.requests.memory' \
             '.spec.containers[0].resources.limits.cpu'  '.spec.containers[0].resources.limits.memory'; do
        echo "$p" | jq -e "$j" &>/dev/null || { err "Pod must define $j"; return 1; }
    done
    [[ "$(echo "$p" | jq -r '.status.phase')" == "Running" ]] || { err "Pod not Running"; return 1; }
    ok "Quota + Pod look good."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "kind: ResourceQuota; spec.hard map keyed by 'requests.cpu', 'limits.memory', etc."
    else                       info "Pod must include both 'requests' AND 'limits' under resources or it will be rejected."
    fi
}

solution() {
cat <<EOF

  kubectl apply -f - <<'YAML'
  apiVersion: v1
  kind: ResourceQuota
  metadata: { name: team-quota, namespace: dev-team }
  spec:
    hard:
      requests.cpu: "2"
      requests.memory: 4Gi
      limits.cpu: "4"
      limits.memory: 8Gi
  ---
  apiVersion: v1
  kind: Pod
  metadata: { name: quota-pod, namespace: dev-team }
  spec:
    containers:
    - name: nginx
      image: nginx
      resources:
        requests: { cpu: "200m", memory: "256Mi" }
        limits:   { cpu: "500m", memory: "512Mi" }
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
