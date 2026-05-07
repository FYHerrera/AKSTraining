#!/usr/bin/env bash
# Lab 28 – Edit an NGINX ConfigMap to allow only TLSv1.3.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab28"; NS="cka-lab28"
LAB_TITLE="Lab 28 – Edit ConfigMap (TLSv1.3 only)"
LAB_DESC="
  ${BOLD}Scenario${NC}
  An NGINX configuration is in ConfigMap ${CYAN}nginx-config${NC} (key nginx.conf).
  Today it sets ${CYAN}ssl_protocols TLSv1.2 TLSv1.3;${NC}.
  Edit it so ${CYAN}ONLY${NC} TLSv1.3 is allowed.
"

deploy() {
    ensure_namespace "$NS"
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata: { name: nginx-config }
data:
  nginx.conf: |
    server {
        listen 443 ssl;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
    }
YAML
    ok "ConfigMap nginx-config seeded. Edit it so only TLSv1.3 remains."
}

validate() {
    local conf; conf=$(kubectl -n "$NS" get cm nginx-config -o jsonpath='{.data.nginx\.conf}')
    echo "$conf" | grep -qE 'ssl_protocols\s+TLSv1\.3\s*;' || { err "Expected exactly 'ssl_protocols TLSv1.3;'"; return 1; }
    echo "$conf" | grep -qE 'ssl_protocols.*TLSv1\.2' && { err "TLSv1.2 still present"; return 1; }
    ok "Only TLSv1.3 allowed."; return 0
}
hint() { info "kubectl -n $NS edit cm nginx-config — change the ssl_protocols line."; }
solution() { echo -e "\n  ${CYAN}kubectl -n $NS edit cm nginx-config${NC}\n  Change  'ssl_protocols TLSv1.2 TLSv1.3;'  →  'ssl_protocols TLSv1.3;'\n"; }

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
