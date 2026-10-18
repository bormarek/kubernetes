#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
k get endpointslices -l kubernetes.io/service-name=nginx-headless
k get endpointslices -l kubernetes.io/service-name=nginx-headless -o yaml
k get endpointslices -l kubernetes.io/service-name=nginx-headless \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\t"}{.conditions.ready}{"\t"}{.targetRef.name}{"\n"}{end}'
k run dns-check --image=busybox:1.37 --restart=Never \
  --command -- sleep 3600
k wait --for=condition=Ready pod/dns-check --timeout=120s
k exec dns-check -- nslookup nginx.nginx-lab.svc.cluster.local
k exec dns-check -- nslookup nginx-headless.nginx-lab.svc.cluster.local
