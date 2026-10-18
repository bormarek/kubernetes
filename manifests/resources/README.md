# Manifesty części 2 — zasoby CPU i RAM

Instrukcja i diagnostyka: [TUTORIAL-MICROK8S-ZASOBY.md](../../TUTORIAL-MICROK8S-ZASOBY.md).
Wszystkie obiekty ćwiczeń należą do namespace `resources-lab`.
Uruchamiaj z katalogu głównego repozytorium, pojedynczo, zgodnie z tutorialem.
Nie stosuj całego katalogu naraz: warianty mają te same nazwy obiektów.

| Plik | Rola |
|---|---|
| `00-namespace.yaml` | Osobne środowisko ćwiczeń |
| `01-resource-demo.yaml` | 20Mi alokacji, obserwacja top i deklaracji |
| `02-memory-oom.yaml` | Pod Never: alokacja 100Mi, limit 32Mi |
| `03-memory-deployment.yaml` | Ta sama awaria w Deploymencie, restarty Always |
| `04-memory-deployment-fixed.yaml` | Naprawa Deploymentu: limit 256Mi |
| `05-cpu-test-100m.yaml` | Ciągła pętla, quota 100m |
| `06-cpu-test-500m.yaml` | Alternatywa cpu-test, quota 500m |
| `07-cpu-benchmark-500m.yaml` | Jednorazowe sumowanie kwadratów, 500m |
| `08-cpu-benchmark-100m.yaml` | Ten sam benchmark, 100m |

Przed zmianą wariantu samodzielnego Podu usuń poprzedni Pod i zaczekaj na
usunięcie (`delete pod NAZWA --wait=true`). Wariant fixed Deploymentu stosuj
bez usuwania Deploymentu: zmiana szablonu rozpocznie rollout.
Obraz `python:3.12-slim` ma zmienny tag; przypnij digest, jeśli potrzebujesz
powtarzalności. Nie uruchomiono tych manifestów na klastrze użytkownika.
