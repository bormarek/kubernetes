#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
require_node_ip
curl -fsS "http://${NODE_IP}:32451/"
for i in $(seq 1 30); do
  curl -fsS "http://${NODE_IP}:32451/" | sed -n 's/.*<p>Pod: \(.*\)<\/p>.*/\1/p'
done | sort | uniq -c
