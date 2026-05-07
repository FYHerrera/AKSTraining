#!/usr/bin/env bash
# Lab 02 – Backup & Restore etcd  [Host-level scenario – simulated in cluster]
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LAB_NAME="cka-lab02"; NS="cka-lab02"
LAB_TITLE="Lab 02 – Backup & Restore etcd  [simulated]"
LAB_DESC="
  ${BOLD}Scenario${NC} (CKA exam wording)
  On the Jump Server an etcd-as-a-service is running with mTLS certificates
  in /opt. Take a snapshot, then restore it.

  ${BOLD}Simulation${NC}
  This lab launches a single-node etcd Pod ${CYAN}etcd-server${NC} so you can
  practice ${CYAN}etcdctl snapshot save${NC} and ${CYAN}snapshot restore${NC}
  end-to-end.

  ${BOLD}Goal${NC}
    1. Save a snapshot to /tmp/etcd-snap.db inside the etcd-server pod.
    2. Demonstrate restore into /var/lib/etcd-restore (inside the pod).

  ${BOLD}Real exam steps (Jump Server)${NC}
    sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \\
      --cacert=/opt/ca.crt --cert=/opt/etcd.crt --key=/opt/etcd.key \\
      snapshot save /opt/snapshot.db
    sudo systemctl stop etcd
    DATA_DIR=\$(ps -ef | grep etcd | grep -oP '(?<=--data-dir=)\\S+')
    sudo mv \$DATA_DIR /var/lib/etcd.old
    sudo ETCDCTL_API=3 etcdctl snapshot restore /opt/snapshot.db --data-dir=/var/lib/etcd
    sudo chown -R etcd:etcd /var/lib/etcd
    sudo systemctl start etcd
"

deploy() {
    ensure_namespace "$NS"
    log "Launching standalone etcd pod..."
    kubectl -n "$NS" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: etcd-server, labels: { app: etcd } }
spec:
  containers:
  - name: etcd
    image: quay.io/coreos/etcd:v3.5.12
    command: ["etcd","--data-dir=/var/lib/etcd","--listen-client-urls=http://0.0.0.0:2379","--advertise-client-urls=http://127.0.0.1:2379"]
YAML
    kubectl -n "$NS" wait --for=condition=Ready pod/etcd-server --timeout=120s &>/dev/null || warn "etcd pod slow to start"
    ok "etcd-server pod is up. Now produce a snapshot at /tmp/etcd-snap.db inside it."
    info "Try:  kubectl -n $NS exec etcd-server -- sh -c 'ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snap.db'"
}

validate() {
    kubectl -n "$NS" exec etcd-server -- sh -c "test -s /tmp/etcd-snap.db" 2>/dev/null \
        || { err "/tmp/etcd-snap.db missing or empty in etcd-server pod"; return 1; }
    kubectl -n "$NS" exec etcd-server -- sh -c "ETCDCTL_API=3 etcdctl --write-out=table snapshot status /tmp/etcd-snap.db" >/dev/null 2>&1 \
        || { err "Snapshot file is not a valid etcd snapshot"; return 1; }
    ok "Snapshot is valid."; return 0
}

hint() {
    local a="${1:-0}"
    if   [[ $a -lt 2 ]]; then info "Use 'kubectl exec etcd-server -n $NS -- ...' and ETCDCTL_API=3 etcdctl snapshot save."
    elif [[ $a -lt 4 ]]; then info "Validate with:  etcdctl snapshot status /tmp/etcd-snap.db -w table"
    else                       info "On the real exam: stop the etcd service, rename data-dir, restore, chown, start service."
    fi
}

solution() {
cat <<EOF

  # 1) Snapshot inside the pod
  kubectl -n ${NS} exec etcd-server -- sh -c \\
    "ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snap.db"

  # 2) Verify
  kubectl -n ${NS} exec etcd-server -- sh -c \\
    "ETCDCTL_API=3 etcdctl --write-out=table snapshot status /tmp/etcd-snap.db"

  # 3) Restore (into a new data dir)
  kubectl -n ${NS} exec etcd-server -- sh -c \\
    "ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-snap.db --data-dir=/var/lib/etcd-restore"

EOF
}

run_lab "$LAB_NAME" "$LAB_TITLE" "$LAB_DESC" deploy validate hint solution
