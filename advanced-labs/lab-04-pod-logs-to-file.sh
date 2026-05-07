#!/usr/bin/env bash
# Lab 04 – kubectl logs + grep into a file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab04"; NS="cka-lab04"
LAB_TITLE="Lab 04 – Pod logs grep to file"
LAB_DESC="
  ${BOLD}Scenario${NC}
  Pod ${CYAN}mypod${NC} prints log lines including 'upgrading webapp …'.
  Save every log line that contains the phrase ${CYAN}upgrading webapp${NC}
  to ${CYAN}/tmp/question04.txt${NC} on your workstation.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: mypod }
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh","-c"]
    args:
    - |
      i=0
      while true; do
        i=$((i+1))
        echo "[$(date)] info heartbeat $i"
        if [ $((i % 3)) -eq 0 ]; then echo "[$(date)] upgrading webapp to v$i"; fi
        sleep 2
      done
YAML
    kubectl -n "$NS" wait --for=condition=Ready pod/mypod --timeout=120s &>/dev/null
    ok "Pod 'mypod' running. Wait ~10s, then save matching lines to /tmp/question04.txt"
}

validate() {
    [[ -s /tmp/question04.txt ]] || { err "/tmp/question04.txt missing or empty"; return 1; }
    grep -q "upgrading webapp" /tmp/question04.txt || { err "File does not contain 'upgrading webapp'"; return 1; }
    grep -v "upgrading webapp" /tmp/question04.txt | grep -q . && { err "File contains lines that don't match the keyword"; return 1; }
    ok "File correctly contains only matching lines."; return 0
}

hint() {
    local a="${1:-0}"
    if [[ $a -lt 2 ]]; then info "Use 'kubectl logs' piped to grep, redirected with '>' to the file."
    else                    info "kubectl -n $NS logs mypod | grep 'upgrading webapp' > /tmp/question04.txt"
    fi
}

solution() { echo -e "\n  ${CYAN}kubectl -n $NS logs mypod | grep 'upgrading webapp' > /tmp/question04.txt${NC}\n"; }

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
