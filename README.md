# Kubernetes / MicroK8s — szkolenie praktyczne

Materiały i ćwiczenia po polsku. Czytaj tutorial przed uruchamianiem poleceń:
część ćwiczeń celowo powoduje awarie i kończy się usuwaniem zasobów laboratorium.

1. [NGINX, DNS i bezpieczne wdrożenia](TUTORIAL-MICROK8S-NGINX.md) — Deployment,
   Service, EndpointSlice, probes, aktualizacje i rollback.
   [Osobne skrypty Bash](scripts/README.md).
2. [CPU, RAM i throttling](TUTORIAL-MICROK8S-ZASOBY.md) — requests/limits,
   `kubectl top`, Allocated resources, OOMKilled, CrashLoopBackOff, cgroups v2
   i benchmark Python. [Manifesty YAML](manifests/resources/README.md).

Każda część używa osobnego namespace. Kolejny planowany temat: klasy QoS.
