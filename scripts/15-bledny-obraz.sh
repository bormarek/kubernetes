#!/usr/bin/env bash
set -euo pipefail
# Czytaj opis ćwiczenia w TUTORIAL-MICROK8S-NGINX.md.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"
GOOD_REV=$(k get deployment nginx -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
printf '%s\n' "$GOOD_REV" > "$LAB_DIR/good-revision.txt"
printf 'Dobra rewizja: %s\n' "$GOOD_REV"
k rollout history deployment/nginx --revision="$GOOD_REV"
k annotate deployment/nginx kubernetes.io/change-cause="Test błędu: nieistniejący obraz" --overwrite
k set image deployment/nginx nginx=nginx:lab-nieistniejacy-tag
if k rollout status deployment/nginx --timeout=60s; then
  echo "Nieoczekiwany sukces wdrożenia; sprawdź obraz." >&2
  exit 1
else
  echo "Rollout nie zakończył się sukcesem — teraz wykonaj diagnostykę i rollback."
fi
