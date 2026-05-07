#!/usr/bin/env bash
# Lab 14 – Find the highest-CPU pod with a given label and write name to file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab14"; NS="cka-lab14"
LAB_TITLE="Lab 14 – Top CPU pod by label"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Several pods labelled ${CYAN}mylabel=cpupods${NC} run in '${NS}'.
  Identify the one consuming the MOST CPU and write ONLY its name
  to ${CYAN}/tmp/question14.txt${NC}.

  ${BOLD}Hint${NC}  kubectl top pod -l mylabel=cpupods -n ${NS}
  Run a few times to be sure (the first reading can be misleading).
"

deploy() {
    ensure_namespace "$NS"
    if ! kubectl top pod -n kube-system &>/dev/null; then
        warn "metrics-server is not installed/ready. The lab will deploy pods, but 'kubectl top' may fail."
        warn "Install metrics-server first:  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
    for i in 1 2 3; do
        kubectl -n "$NS" run "cpupod-$i" --image=polinux/stress \
            --labels="mylabel=cpupods" --restart=Never \
            --command -- stress --cpu "$i" --timeout 1800s >/dev/null 2>&1 || true
    done
    sleep 15
    ok "Three pods 'cpupod-1/2/3' running with increasing CPU pressure (cpupod-3 highest)."
}

validate() {
    [[ -s /tmp/question14.txt ]] || { err "/tmp/question14.txt missing"; return 1; }
    local answer expected
    answer=$(tr -d '[:space:]' < /tmp/question14.txt)
    expected=$(kubectl -n "$NS" top pod -l mylabel=cpupods --no-headers 2>/dev/null \
        | sort -k2 -h -r | head -1 | awk '{print $1}')
    [[ -z "$expected" ]] && { err "Unable to query metrics — install metrics-server"; return 1; }
    [[ "$answer" == "$expected" ]] || { err "Wrote '$answer' but top says '$expected'"; return 1; }
    ok "Correct: $expected"; return 0
}
hint() { info "kubectl -n $NS top pod -l mylabel=cpupods --no-headers | sort -k2 -hr | head -1"; }
solution() { echo -e "\n  ${CYAN}kubectl -n $NS top pod -l mylabel=cpupods --no-headers | sort -k2 -hr | head -1 | awk '{print \$1}' > /tmp/question14.txt${NC}\n"; }

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
