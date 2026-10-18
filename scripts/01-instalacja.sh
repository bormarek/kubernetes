#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
sudo snap install microk8s --classic
sudo usermod -a -G microk8s "$USER"
mkdir -p ~/.kube
chmod 0700 ~/.kube
