#!/usr/bin/env bash
# Wspólne ustawienia; ładowane przez source w skryptach ćwiczeń.
LAB_DIR="${LAB_DIR:-$HOME/microk8s-nginx-lab}"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"
k() { microk8s kubectl -n nginx-lab "$@"; }
require_node_ip() { : "${NODE_IP:?Ustaw NODE_IP, np. NODE_IP=192.168.0.44 bash scripts/06-test-nodeport.sh}"; }
