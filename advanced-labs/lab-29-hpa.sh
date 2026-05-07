#!/usr/bin/env bash
# Lab 29 – Create an HPA for a Deployment.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab29"; NS="autoscale"
LAB_TITLE="Lab 29 – HorizontalPodAutoscaler"
LAB_DESC="
  ${BOLD}Scenario${NC}
  In namespace ${CYAN}autoscale${NC} a Deployment ${CYAN}apache-server${NC} is
  running. Create an HPA ${CYAN}apache-server${NC} that:
    - targets that Deployment
    - 50% average CPU per Pod
    - min 1, max 4 replicas
    - downscale stabilization window: 30 seconds

  Requires metrics-server in the cluster.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: apache-server }
spec:
  replicas: 1
  selector: { matchLabels: { app: apache } }
  template:
    metadata: { labels: { app: apache } }
    spec:
      containers:
      - name: apache
        image: httpd:2.4
        resources:
          requests: { cpu: "100m" }
          limits:   { cpu: "500m" }
YAML
    kubectl -n "$NS" rollout status deploy/apache-server --timeout=120s >/dev/null
    ok "Deployment apache-server ready. Create the HPA."
}

validate() {
    local h="$(kubectl -n "$NS" get hpa apache-server -o json 2>/dev/null)"
    [[ -z "$h" ]] && { err "HPA apache-server missing"; return 1; }
    [[ "$(echo "$h" | jq -r '.spec.scaleTargetRef.name')" == "apache-server" ]] || { err "scaleTargetRef.name must be apache-server"; return 1; }
    [[ "$(echo "$h" | jq -r '.spec.minReplicas')" == "1" ]] || { err "minReplicas != 1"; return 1; }
    [[ "$(echo "$h" | jq -r '.spec.maxReplicas')" == "4" ]] || { err "maxReplicas != 4"; return 1; }
    echo "$h" | jq -e '.spec.metrics[] | select(.type=="Resource" and .resource.name=="cpu" and .resource.target.averageUtilization==50)' &>/dev/null \
        || { err "Must target CPU averageUtilization=50"; return 1; }
    [[ "$(echo "$h" | jq -r '.spec.behavior.scaleDown.stabilizationWindowSeconds')" == "30" ]] \
        || { err "behavior.scaleDown.stabilizationWindowSeconds must be 30"; return 1; }
    ok "HPA configured correctly."; return 0
}
hint() {
    local a="${1:-0}"
    if [[ $a -lt 2 ]]; then info "kubectl -n $NS autoscale deploy apache-server --cpu-percent=50 --min=1 --max=4"
    else                    info "Edit the HPA to add spec.behavior.scaleDown.stabilizationWindowSeconds: 30"
    fi
}
solution() {
cat <<EOF

  kubectl -n ${NS} apply -f - <<'YAML'
  apiVersion: autoscaling/v2
  kind: HorizontalPodAutoscaler
  metadata: { name: apache-server }
  spec:
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: apache-server
    minReplicas: 1
    maxReplicas: 4
    metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 50 }
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 30
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
