#!/usr/bin/env bash
# Lab 19 – Default StorageClass with WaitForFirstConsumer.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab19"; NS="cka-lab19"
LAB_TITLE="Lab 19 – Default StorageClass 'low-latency'"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Create StorageClass ${CYAN}low-latency${NC}:
    - provisioner: rancher.io/local-path
    - volumeBindingMode: WaitForFirstConsumer
    - mark it as the DEFAULT StorageClass

  Do NOT modify existing Deployments or PVCs.
  If another StorageClass is currently default, unset it.
"

deploy() {
    ensure_namespace "$NS"
    ok "Create the StorageClass 'low-latency' as the new default."
}

validate() {
    local sc="$(kubectl get sc low-latency -o json 2>/dev/null)"
    [[ -z "$sc" ]] && { err "StorageClass 'low-latency' missing"; return 1; }
    [[ "$(echo "$sc" | jq -r '.provisioner')" == "rancher.io/local-path" ]] || { err "provisioner mismatch"; return 1; }
    [[ "$(echo "$sc" | jq -r '.volumeBindingMode')" == "WaitForFirstConsumer" ]] || { err "volumeBindingMode mismatch"; return 1; }
    [[ "$(echo "$sc" | jq -r '.metadata.annotations."storageclass.kubernetes.io/is-default-class"')" == "true" ]] \
        || { err "Not marked as default class"; return 1; }
    local defaults
    defaults=$(kubectl get sc -o json | jq '[.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class"=="true")] | length')
    [[ "$defaults" -eq 1 ]] || { err "Exactly ONE default StorageClass expected (found $defaults)"; return 1; }
    ok "low-latency is the unique default StorageClass."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Set annotation 'storageclass.kubernetes.io/is-default-class: \"true\"'."
    else                       info "Unset the previous default:  kubectl patch sc <old> -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
    fi
}

solution() {
cat <<EOF

  # Unset previous default if any
  for sc in \$(kubectl get sc -o name); do
    kubectl patch \$sc -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
  done

  kubectl apply -f - <<'YAML'
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: low-latency
    annotations: { storageclass.kubernetes.io/is-default-class: "true" }
  provisioner: rancher.io/local-path
  volumeBindingMode: WaitForFirstConsumer
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
