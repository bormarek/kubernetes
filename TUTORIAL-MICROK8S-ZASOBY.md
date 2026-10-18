# Kubernetes / MicroK8s w praktyce — część 2: CPU, RAM i throttling

Dalszy ciąg [szkolenia NGINX, DNS i wdrożenia](TUTORIAL-MICROK8S-NGINX.md).
Czas: około 60–90 minut. Stan opracowania: 18 października 2026.
Przechodzimy od działania aplikacji do jej zachowania przy ograniczonych zasobach.
Nie potrzebujesz działającego NGINX z części 1; wystarczy sprawny klaster MicroK8s.

Ćwiczenia odtwarzają requests/limits, celowy brak pamięci, restarty i ograniczanie
CPU. Wyniki benchmarku 1,556 s i 7,198 s pochodzą z dostępnego fragmentu rozmowy
„Uruchamianie Kubernetes krok po kroku”. Dostępne odpowiedzi asystenta są tylko
odsyłaczami; poniższe manifesty i instrukcje są samodzielnym opracowaniem,
a nie odtworzeniem nieudostępnionych odpowiedzi.

## 1. Przygotowanie i pliki

Polecenia wykonuj w Bash na węźle MicroK8s, z katalogu głównego tego repozytorium.
Używamy nowego namespace `resources-lab`, niezależnego od `nginx-lab` i `default`.
Jeśli już istnieje, sprawdź jego zawartość i upewnij się, że służy temu laboratorium.
Potrzebny jest internet do pobrania obrazu Python i wolne zasoby na testowe Pody.
Ćwiczenie cgroups zakłada Linux z cgroups v2.

```bash
microk8s status --wait-ready
microk8s kubectl get nodes -o wide
microk8s kubectl version
microk8s enable metrics-server
microk8s kubectl apply -f manifests/resources/00-namespace.yaml
k() { microk8s kubectl -n resources-lab "$@"; }
k get pods
```

Funkcję `k` zdefiniuj ponownie w każdym terminalu. Nie zmienia ona kubeconfig.
`metrics-server` jest dodatkiem całego klastra; jeśli już działa, użyj istniejącego.
Poczekaj na gotowość dodatku i pierwsze próbki metryk.
Zapisz wersje MicroK8s, Kubernetes, kernela oraz obraz/digest, jeśli porównujesz wyniki.
Tag `python:3.12-slim` jest zmienny; do ścisłej powtarzalności przypnij sprawdzony digest.

Manifesty są w [manifests/resources/](manifests/resources/README.md).
**Stosuj je pojedynczo według kolejności poniżej.** Nie wykonuj `apply -f` na całym
katalogu: zawiera celowe awarie i alternatywne wersje tych samych obiektów.

## 2. Requests i limits: co deklarujemy?

Każdy kontener w przykładach ma blok zasobów, np.:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 16Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

| Pole / jednostka | Znaczenie |
|---|---|
| `requests.cpu` | Uwzględniane przy planowaniu Podu; wpływa też na udział CPU przy konkurencji |
| `requests.memory` | Uwzględniane przy planowaniu; nie przydziela z góry fizycznych stron RAM |
| `limits.cpu` | Ogranicza czas CPU przez quota; obciążenie może być throttlowane |
| `limits.memory` | Granica pamięci kontenera; przekroczenie może wywołać OOM kill |
| `100m` / `500m` | 0,1 / 0,5 jednostki CPU; `1000m` = 1 CPU |
| `32Mi` / `100Mi` / `256Mi` | 32 / 100 / 256 × 1024² bajtów |

100m nie oznacza 10% całego wielordzeniowego komputera ani przypięcia do jednego
rdzenia. Request nie jest górną granicą użycia. Scheduler dobiera węzeł na podstawie
requests i dostępnego `Allocatable`; nie opiera tej decyzji na chwilowym `top`.
Pod może pozostawać `Pending`, choć komputer aktualnie wygląda na bezczynny.
W naszych przykładach request nie przekracza limitu.

## 3. kubectl top a Allocated resources

Uruchom [resource-demo](manifests/resources/01-resource-demo.yaml), który alokuje
20 MiB i potem śpi. Pełny manifest zawiera jawne requests i limits CPU/RAM:

```bash
k apply -f manifests/resources/01-resource-demo.yaml
k wait --for=condition=Ready pod/resource-demo --timeout=120s
k logs resource-demo
microk8s kubectl top nodes
k top pods --containers
NODE=$(k get pod resource-demo -o jsonpath='{.spec.nodeName}')
microk8s kubectl describe node "$NODE"
k get pod resource-demo -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```

W `describe node` znajdź `Capacity`, `Allocatable`, `Non-terminated Pods` oraz
`Allocated resources`. Ostatnia sekcja sumuje deklaracje requests i limits Podów
na tym węźle, także z innych namespace. Procenty odnoszą się do `Allocatable`.
Suma limitów może przekraczać 100% — to overcommit, a nie pomiar przeciążenia.

`top` pokazuje niedawne zużycie CPU i metrykę pamięci working set; nie jest
zestawieniem rezerwacji ani dokładnym licznikiem bajtów obiektów Python.
Śpiący proces może zużywać niemal 0m CPU przy zadeklarowanych 100m.
RAM obejmuje też interpreter i inne narzuty. Krótkotrwały Pod może skończyć się
przed zebraniem próbki. Brak metryk nie oznacza zużycia równego zero.

Gdy pojawia się `Metrics API not available` lub brak danych:

```bash
microk8s kubectl -n kube-system get deployment metrics-server
microk8s kubectl -n kube-system get pods -l k8s-app=metrics-server
microk8s kubectl -n kube-system logs deployment/metrics-server --tail=50
microk8s kubectl get apiservice v1beta1.metrics.k8s.io
```

Sprawdź gotowość dodatku, komunikację z kubeletami i błędy certyfikatów w logach;
po starcie daj mu czas na próbki. Nie wyłączaj weryfikacji TLS jako pierwszej reakcji.

## 4. OOMKilled: limit 32Mi, alokacja 100Mi, exit 137

[Manifest memory-oom](manifests/resources/02-memory-oom.yaml) uruchamia pojedynczy
Pod z `restartPolicy: Never`. Python jako główny proces kontenera wykonuje:

```python
import time
print("Próba alokacji 100 MiB", flush=True)
buf = bytearray(100 * 1024 * 1024)
print("Przydzielono 100 MiB", flush=True)
time.sleep(3600)
```

`bytearray` tworzy i inicjalizuje pamięć; samo zadeklarowanie wielkości w komentarzu
nie wystarczyłoby do testu. Limit 32Mi obejmuje także interpreter.

```bash
k apply -f manifests/resources/02-memory-oom.yaml
k get pod memory-oom --watch
```

Po zakończeniu kontenera przerwij obserwację Ctrl+C i odczytaj stan:

```bash
k describe pod memory-oom
k logs memory-oom
k get pod memory-oom -o jsonpath='{range .status.containerStatuses[*]}{.name}{" reason="}{.state.terminated.reason}{" exit="}{.state.terminated.exitCode}{" restarts="}{.restartCount}{"\n"}{end}'
```

Oczekuj `reason=OOMKilled`, `exit=137`, bez restartów. Faza Podu to `Failed`,
a kolumna STATUS może pokazywać `OOMKilled`. Kod 137 zwykle oznacza
128 + 9, czyli zakończenie przez SIGKILL. **Sam kod 137 nie dowodzi OOM** —
potwierdź powód w statusie i kontekst w `describe`. Log może zawierać tylko
pierwszy komunikat: SIGKILL nie pozwala aplikacji posprzątać ani wypisać wyjątku.
Przy innym środowisku możliwy jest np. `MemoryError`; wtedy sprawdź faktyczny limit,
politykę swap/cgroups i status zakończenia, zamiast zakładać oczekiwany wynik.

## 5. Ten sam błąd w Deploymencie: CrashLoopBackOff

Deployment ma jedną replikę i ten sam kod, ale Pody Deploymentu używają
`restartPolicy: Always` (tutaj domyślnie). Kubelet ponawia start kontenera
w tym samym Podzie; ReplicaSet utrzymuje zadaną liczbę Podów.

```bash
k apply -f manifests/resources/03-memory-deployment.yaml
k get pods -l app=memory-demo --watch
```

Po kilku restartach i zaobserwowaniu `CrashLoopBackOff` przerwij Ctrl+C:

```bash
POD=$(k get pods -l app=memory-demo -o jsonpath='{.items[0].metadata.name}')
k describe pod "$POD"
k logs "$POD" --previous
k get pod "$POD" -o jsonpath='{range .status.containerStatuses[*]}{.name}{" waiting="}{.state.waiting.reason}{" lastReason="}{.lastState.terminated.reason}{" lastExit="}{.lastState.terminated.exitCode}{" restarts="}{.restartCount}{"\n"}{end}'
k get events --sort-by=.metadata.creationTimestamp
```

`OOMKilled` wyjaśnia poprzednie zakończenie. `CrashLoopBackOff` oznacza oczekiwanie
z opóźnieniem przed kolejną próbą restartu, a nie osobną przyczynę awarii ani fazę
Podu. Pomiędzy próbami STATUS może się zmieniać. `--previous` czyta log poprzedniej
instancji kontenera; przed pierwszym restartem może jeszcze nie być dostępny.
Sam restart lub usunięcie Podu nie naprawia zbyt małego limitu w szablonie.

Naprawiamy źródło konfiguracji: [wariant fixed](manifests/resources/04-memory-deployment-fixed.yaml)
różni się wyłącznie limitem pamięci **256Mi**. Request pozostaje 16Mi:

```bash
k apply -f manifests/resources/04-memory-deployment-fixed.yaml
k rollout status deployment/memory-demo --timeout=180s
k get pods -l app=memory-demo
k logs deployment/memory-demo
k get deployment memory-demo -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```

Oczekuj nowego Podu `1/1 Running` i logu `Przydzielono 100 MiB`.
Zmiana szablonu uruchamia rollout; zerowe RESTARTS nowego Podu nie kasuje historii
awarii starego. Bez probes `Ready` oznacza tu uruchomiony kontener, więc sprawdź
też log i stabilność przez chwilę. Dla rzeczywistej aplikacji dobieramy requests
na podstawie obserwacji, a nie pozostawiamy mechanicznie laboratoryjnych 16Mi.
Ponowne zastosowanie pliku 03 przywróci awarię. Nie zmieniamy zasobów istniejącego
samodzielnego Podu w miejscu — do kolejnych eksperymentów odtwarzamy Pody.

Przed pomiarami CPU usuń obiekty z poprzednich ćwiczeń:

```bash
k delete pod resource-demo memory-oom --ignore-not-found
k delete deployment memory-demo --ignore-not-found
```

## 6. cgroups v2: cpu.max, cpu.stat i 100m

Uruchom ciągłe obciążenie jednego wątku. To celowo zajęta pętla, a nie benchmark
czasu wykonania zadania:

```bash
k apply -f manifests/resources/05-cpu-test-100m.yaml
k wait --for=condition=Ready pod/cpu-test --timeout=120s
k exec cpu-test -- cat /proc/self/cgroup
k exec cpu-test -- cat /sys/fs/cgroup/cgroup.controllers
k exec cpu-test -- cat /sys/fs/cgroup/cpu.max
k exec cpu-test -- cat /sys/fs/cgroup/cpu.stat
sleep 10
k exec cpu-test -- cat /sys/fs/cgroup/cpu.stat
k top pod cpu-test
```

W cgroups v2 `/proc/self/cgroup` zwykle ma wpis `0::/...`. Sprawdzamy pliki
**wewnątrz kontenera**, bez zgadywania ścieżek Podów na hoście. W zależności od
runtime/montażu ścieżka widoczna w kontenerze może wymagać dopasowania.
Brak `cpu.max` może oznaczać cgroups v1, inną ścieżkę lub niewłączony kontroler CPU;
sprawdź konfigurację węzła. Nie edytuj ręcznie plików cgroup zarządzanych przez kubelet.

Dla typowego okresu 100000 mikrosekund `cpu.max` przy 100m pokaże:

```text
10000 100000
```

Pierwsza liczba to quota czasu CPU, druga to okres, obie w µs.
10000 / 100000 = 0,1 CPU. Po wyczerpaniu budżetu runnable proces czeka na jego
odnowienie. To limit łącznego czasu CPU kontenera, nie stała prędkość zegara.
Okres może być inaczej skonfigurowany; interpretuj iloraz faktycznych wartości.
`max 100000` oznacza brak quota na tej cgroup; ograniczać mogą jeszcze przodkowie.

W `cpu.stat` porównuj przyrosty dwóch odczytów w tej samej instancji kontenera:

| Licznik | Interpretacja |
|---|---|
| `usage_usec` | Zużyty czas CPU w mikrosekundach |
| `nr_periods` | Liczba okresów rozliczania quota |
| `nr_throttled` | Liczba okresów z throttlingiem |
| `throttled_usec` | Łączny czas throttlingu w mikrosekundach |

W aktywnej pętli oczekuj wzrostu `nr_throttled` i `throttled_usec`; `top` po
ustabilizowaniu próbek zwykle pokaże okolice 100m. To ograniczanie CPU, nie OOM:
proces nadal działa. Iloraz przyrostów `nr_throttled / nr_periods` opisuje udział
okresów z throttlingiem, a nie procent utraconej wydajności. Czas throttlingu
nie jest uniwersalną miarą opóźnienia aplikacji, szczególnie przy wielu wątkach.

## 7. Porównanie z 500m

Usuń Pod, zaczekaj na usunięcie i utwórz wariant z limitem 500m, z tym samym
requestem 100m. Nie porównujemy dwóch obciążeń działających jednocześnie:

```bash
k delete pod cpu-test --wait=true
k apply -f manifests/resources/06-cpu-test-500m.yaml
k wait --for=condition=Ready pod/cpu-test --timeout=120s
k exec cpu-test -- cat /sys/fs/cgroup/cpu.max
k exec cpu-test -- cat /sys/fs/cgroup/cpu.stat
sleep 10
k exec cpu-test -- cat /sys/fs/cgroup/cpu.stat
k top pod cpu-test
```

Dla okresu 100000 µs oczekuj `50000 100000`, czyli 0,5 CPU. Pętla nadal chce
całego jednego CPU, dlatego również przy 500m może być throttlowana, nawet
w każdym okresie. Zyskuje większy budżet, a nie obietnicę zerowego throttlingu.
Liczniki nowego kontenera zaczynają się od nowa; nie odejmuj ich od starego Podu.

Przed benchmarkiem zatrzymaj generator obciążenia:

```bash
k delete pod cpu-test --wait=true
```

## 8. Benchmark Python: 5 mln iteracji

Mierzymy dokładnie ten sam fragment w obu wariantach:

```python
start = time.perf_counter()
result = sum(i * i for i in range(5_000_000))
elapsed = time.perf_counter() - start
```

To 5 mln iteracji obliczania i sumowania kwadratów, potocznie „5 mln operacji”;
nie jest to dokładnie 5 mln instrukcji procesora. Pełny kod z importem `time`
i wypisaniem wyniku znajduje się w manifestach. Pomiar wewnątrz procesu nie
obejmuje pobrania obrazu, planowania ani całego czasu uruchamiania Podu.
Samodzielny Pod ma `restartPolicy: Never`, więc po sukcesie nie zapętla testu.

Najpierw 500m:

```bash
k apply -f manifests/resources/07-cpu-benchmark-500m.yaml
k wait --for=jsonpath='{.status.phase}'=Succeeded pod/cpu-benchmark --timeout=180s
k logs cpu-benchmark
k get pod cpu-benchmark -o jsonpath='{.spec.nodeName}{"\n"}{.status.containerStatuses[0].imageID}{"\n"}'
```

Następnie 100m — Pod o tej samej nazwie trzeba najpierw usunąć:

```bash
k delete pod cpu-benchmark --wait=true
k apply -f manifests/resources/08-cpu-benchmark-100m.yaml
k wait --for=jsonpath='{.status.phase}'=Succeeded pod/cpu-benchmark --timeout=180s
k logs cpu-benchmark
k get pod cpu-benchmark -o jsonpath='{.spec.nodeName}{"\n"}{.status.containerStatuses[0].imageID}{"\n"}'
```

W obu przypadkach wynik obliczenia powinien wynosić `41666654166667500000`.
Przy timeout sprawdź `get pod`, `describe` i `logs`; oczekiwanie na `Succeeded`
nie kończy się automatycznie sukcesem, gdy Pod zakończy się błędem.

Wyniki z rozmowy (nie nowe pomiary na tym klastrze):

| Limit CPU | Wynik | Execution time |
|---|---|---|
| 500m | 41666654166667500000 | 1,556 s |
| 100m | 41666654166667500000 | 7,198 s |

7,198 / 1,556 ≈ **4,63×**: przy 100m zadanie trwało około 4,63 razy dłużej.
Stosunek quota to 5×, ale rzeczywisty stosunek czasów nie musi wynosić dokładnie
5. Znaczenie mają wersja Pythona, CPU, obciążenie hosta, harmonogram i granice
okresów quota. Nie traktuj pojedynczej pary wyników jako gwarancji wydajności.

Powtórz każdą konfigurację kilka razy, zapisuj czasy i porównuj mediany.
Utrzymuj ten sam węzeł, obraz i kod oraz podobne obciążenie. W klastrze
wielowęzłowym sprawdź `nodeName`; w razie potrzeby dodaj w obu wariantach
jednakowy `nodeSelector` z rzeczywistą etykietą wybranego węzła.
Nie uruchamiaj równolegle `cpu-test`: konkurowałby z benchmarkiem.
Dodatkowy pomiar przez `kubectl exec cpu-test -- python3 ...` podczas aktywnej
pętli współdzieliłby z nią quota kontenera i nie byłby porównywalnym testem.

## 9. Diagnostyka od objawu do przyczyny

| Objaw | Sprawdzenie | Dalszy krok |
|---|---|---|
| `Pending` | `k describe pod NAZWA`, Events | Sprawdź `Insufficient cpu/memory`, requests, Allocatable, tainty i selektory |
| `OOMKilled`, 137 | stan zakończenia / `lastState`, limit RAM | Oszacuj cały working set, ogranicz alokację lub popraw limit |
| `CrashLoopBackOff` | `k logs NAZWA --previous`, `k describe pod NAZWA` | Napraw przyczynę poprzedniego zakończenia w szablonie |
| CPU około 100m mimo zapasu na hoście | `cpu.max`, przyrosty `cpu.stat` | Sprawdź quota kontenera i ewentualne limity przodków |
| Brak `top` | Metrics API i log metrics-server | Poczekaj na próbki, sprawdź addon i komunikację |
| Benchmark `Completed`, brak `exec` | `k logs cpu-benchmark` | Zakończony kontener nie obsłuży `exec`; użyj osobnego cpu-test |
| `Forbidden` przy zmianie Podu | rodzaj obiektu i zmieniane pole | Odtwórz samodzielny Pod lub zmień szablon Deploymentu |
| `ImagePullBackOff` | Events Podu | Sprawdź rejestr, tag i dostęp do internetu |

Nie podnoś limitu CPU w odpowiedzi na OOM ani RAM wyłącznie z powodu throttlingu.
`Allocated resources` pomaga zrozumieć planowanie, `top` zużycie, a status i cgroups
wyjaśniają zachowanie procesu. Łącz te źródła zamiast wnioskować z jednej kolumny.

## 10. Sprzątanie i kryteria ukończenia

Po zapisaniu wyników usuń **tylko namespace tego laboratorium**:

```bash
microk8s kubectl delete namespace resources-lab
```

Usuwa to również zakończony benchmark i ewentualne pozostawione Pody.
Nie używaj `microk8s reset`. Nie wyłączaj metrics-server, jeśli służy innym
ćwiczeniom lub użytkownikom. Pliki w repozytorium pozostają jako materiał.

Ćwiczenie jest ukończone, gdy potrafisz:

- odróżnić requests/limits od metryk i wyjaśnić `Allocated resources`;
- wskazać `OOMKilled` oraz 137 dla alokacji 100Mi przy limicie 32Mi;
- znaleźć przyczynę `CrashLoopBackOff` i przywrócić stabilny Deployment z 256Mi;
- odczytać quota 100m i 500m z `cpu.max` oraz przyrosty throttlingu z `cpu.stat`;
- powtórzyć benchmark, potwierdzić identyczny wynik i policzyć stosunek czasów;
- usunąć zasoby testowe bez naruszania poprzedniej części szkolenia.

## 11. Co dalej: QoS

Kolejna część połączy requests/limits z klasami **Guaranteed, Burstable,
BestEffort** oraz zachowaniem przy presji pamięci i eksmisji Podów.
Już teraz, przed sprzątaniem, możesz sprawdzić:

```bash
k get pod cpu-benchmark -o jsonpath='{.status.qosClass}{"\n"}'
```

Przy pokazanych zasobach oczekuj `Burstable`: request pamięci jest mniejszy od
limitu. Klasa QoS sama nie chroni przed przekroczeniem własnego limitu RAM.
Szczegóły i porównanie klas pozostawiamy do kolejnego laboratorium.

## 12. Źródła i zakres weryfikacji

- [Kubernetes: zarządzanie zasobami kontenerów](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes: ćwiczenie limitu pamięci i OOM](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/)
- [Kubernetes: ćwiczenie limitu CPU](https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-resource/)
- [Linux: cgroups v2, kontroler CPU](https://www.kernel.org/doc/html/v6.14/admin-guide/cgroup-v2.html#cpu)
- [Kubernetes: cykl życia Podu i restarty](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Kubernetes: klasy QoS](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [MicroK8s: dodatki, w tym metrics-server](https://canonical.com/microk8s/docs/addons)

Sprawdzono statycznie YAML, osadzony kod Python, polecenia Bash i spójność
wariantów. Próba `kubectl --dry-run=client` nie mogła zakończyć się z powodu
braku działającego API Kubernetes w środowisku opracowania. Nie wykonano wdrożenia na klastrze użytkownika ani nowych pomiarów
OOM/throttlingu. Wartości 1,556 s i 7,198 s są obserwacjami z rozmowy;
pozostałe opisane stany to oczekiwane wyniki do potwierdzenia podczas ćwiczeń.
