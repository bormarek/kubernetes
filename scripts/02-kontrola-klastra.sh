#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
microk8s status --wait-ready
microk8s enable dns
microk8s kubectl version
microk8s kubectl get nodes -o wide
microk8s kubectl -n kube-system get svc kube-dns
