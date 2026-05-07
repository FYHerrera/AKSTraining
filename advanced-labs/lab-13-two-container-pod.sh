#!/usr/bin/env bash
# Lab 13 – Pod with two containers (redis + memcached).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab13"; NS="cka-lab13"
LAB_TITLE="Lab 13 – Pod with two containers"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Create Pod ${CYAN}twocontainerpod${NC} in '${NS}' with two containers:
    - container 1: image ${CYAN}redis${NC}
    - container 2: image ${CYAN}memcached${NC}

  ${BOLD}Tip${NC}
    kubectl run twocontainerpod --image=redis --dry-run=client -o yaml > 13.yaml
    # then add the second container under spec.containers
"

deploy() { ensure_namespace "$NS"; ok "Build twocontainerpod with redis + memcached."; }

validate() {
    local p="$(kubectl -n "$NS" get pod twocontainerpod -o json 2>/dev/null)"
    [[ -z "$p" ]] && { err "Pod missing"; return 1; }
    [[ "$(echo "$p" | jq '.spec.containers | length')" -eq 2 ]] || { err "Need exactly 2 containers"; return 1; }
    echo "$p" | jq -e '[.spec.containers[].image] | map(test("redis"))   | any' &>/dev/null || { err "redis container missing"; return 1; }
    echo "$p" | jq -e '[.spec.containers[].image] | map(test("memcached"))| any' &>/dev/null || { err "memcached container missing"; return 1; }
    [[ "$(echo "$p" | jq -r '.status.phase')" == "Running" ]] || { err "Pod not Running"; return 1; }
    ok "Two-container pod is Running."; return 0
}
hint() { info "kubectl -n $NS run twocontainerpod --image=redis --dry-run=client -o yaml > 13.yaml ; then add memcached container."; }
solution() {
cat <<EOF

  kubectl -n ${NS} apply -f - <<'YAML'
  apiVersion: v1
  kind: Pod
  metadata: { name: twocontainerpod }
  spec:
    containers:
    - { name: redis,     image: redis }
    - { name: memcached, image: memcached }
  YAML

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
