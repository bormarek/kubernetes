# Kubernetes / MicroK8s w praktyce: NGINX, DNS i bezpieczne wdrożenia

Materiał po polsku na podstawie dostępnego fragmentu rozmowy „Uruchamianie Kubernetes krok po kroku”, uzupełniony o samodzielne laboratorium. Czas: około 2–3 godziny. Stan opracowania: 18 października 2026.

W rozmowie działał Deployment `nginx` z 8 replikami, obrazem `nginx:stable`, ConfigMap `nginx-page`, generowaniem strony przez envsubst oraz probes HTTP. W historii były rewizje 1–5, 7 i 8; aktywny ReplicaSet miał hash `75747ff755`. Poniższe ćwiczenia odtwarzają mechanizmy, a nie dokładne numery rewizji ani adresy klastra. Dostępne odpowiedzi poprzedniego asystenta były jedynie odsyłaczami, dlatego nie są traktowane jako odtworzona treść szkolenia.

## 1. Cel i architektura

Po ćwiczeniach potrafisz wdrożyć osiem serwerów WWW, rozpoznać obsługujący Pod, porównać Service zwykły i headless, skonfigurować dynamiczne odkrywanie backendów, odczytać EndpointSlice oraz wykonać aktualizację i rollback.

```text
Przeglądarka / curl
  ├─ IP_węzła:32451 → Service nginx (NodePort) → gotowe Pody nginx
  └─ IP_węzła:32452 → Service nginx-lb (NodePort) → Pod nginx-lb
                                                    │ proxy HTTP
                                                    ▼
                                             Pody nginx × 8
                                                    ▲
               CoreDNS ← nginx-headless ← EndpointSlice / readiness
                    └─ odpowiedzi DNS → resolver w nginx-lb
```

Deployment utrzymuje stan docelowy przez ReplicaSet. Pod jest wymienialną instancją aplikacji; jego IP może się zmienić. Service wybiera Pody etykietami. ConfigMap przechowuje konfigurację bez danych poufnych. DNS i readiness pomagają aktualizować listę dostępnych backendów.

To laboratorium HTTP w sieci lokalnej. Osiem Podów na jednym komputerze nie zapewnia odporności na awarię tego komputera. Jeden Pod `nginx-lb` również pozostaje pojedynczym punktem awarii. Produkcja wymaga osobnych decyzji o TLS, uprawnieniach, rozłożeniu replik, zasobach i monitoringu.

## 2. Przygotowanie środowiska

Potrzebujesz Ubuntu/Linux z działającym snapd, dostępu administratora, internetu do pobierania obrazów i klienta `curl`. Praktyczny punkt startowy to 2 CPU i 4 GiB RAM; dostępne zasoby zależą od pozostałych aplikacji. Polecenia wykonuj w Bash na węźle MicroK8s.

Jeżeli MicroK8s już działa, pomiń instalację. Nie reinstaluj istniejącego klastra.

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s "$USER"
mkdir -p ~/.kube
chmod 0700 ~/.kube
```

Wyloguj się i zaloguj ponownie, aby uaktywnić członkostwo w grupie. Następnie:

```bash
microk8s status --wait-ready
microk8s enable dns
microk8s kubectl version
microk8s kubectl get nodes -o wide
microk8s kubectl -n kube-system get svc kube-dns
```

Instalacja bez `--channel` korzysta z domyślnego kanału snap. Dla powtarzalnego kursu wybierz wspólnie konkretny wspierany kanał i zapisz jego wersję. Węzły muszą mieć status `Ready`, a DNS adres ClusterIP. Obrazy w ćwiczeniu mają tag `nginx:1.28` (linia obsługująca `resolve` w OSS); tag może zmieniać zawartość. Dla pełnej powtarzalności przypnij sprawdzony digest obrazu. Nie używaj starego NGINX poniżej 1.27.3 dla pokazanej konfiguracji dynamicznego upstreamu.

Pracujemy w osobnym namespace, aby nie zmieniać wcześniejszego `nginx` w `default`:

```bash
mkdir -p ~/microk8s-nginx-lab
cd ~/microk8s-nginx-lab
microk8s kubectl create namespace nginx-lab
k() { microk8s kubectl -n nginx-lab "$@"; }
```

Funkcję `k` zdefiniuj ponownie po otwarciu nowego terminala. Jeśli namespace istnieje, sprawdź jego zawartość i upewnij się, że należy do tego laboratorium. Nie zmieniamy domyślnego namespace w kubeconfig.

## 3. Strona z ConfigMap i osiem replik

Utwórz manifest; cytowany delimiter `EOF_YAML` zachowuje `${POD_NAME}` do podstawienia wewnątrz kontenera:

```bash
cat > backend.yaml <<'EOF_YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-page
  namespace: nginx-lab
data:
  index.html.template: |
    <!doctype html>
    <html lang="pl"><meta charset="utf-8">
    <title>Laboratorium NGINX</title>
    <h1>Kubernetes / MicroK8s</h1>
    <p>Wersja strony: v1</p>
    <p>Pod: ${POD_NAME}</p>
    <p>Adres IP: ${POD_IP}</p>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: nginx-lab
  annotations:
    kubernetes.io/change-cause: "Start laboratorium: strona v1"
spec:
  replicas: 8
  revisionHistoryLimit: 10
  minReadySeconds: 5
  progressDeadlineSeconds: 180
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.28
          ports:
            - name: http
              containerPort: 80
          env:
            - name: NGINX_ENVSUBST_OUTPUT_DIR
              value: /usr/share/nginx/html
            - name: NGINX_ENVSUBST_FILTER
              value: '^(POD_NAME|POD_IP)$'
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            timeoutSeconds: 2
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            timeoutSeconds: 2
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests:
              cpu: 25m
              memory: 32Mi
            limits:
              cpu: 250m
              memory: 128Mi
          volumeMounts:
            - name: nginx-html
              mountPath: /etc/nginx/templates/index.html.template
              subPath: index.html.template
              readOnly: true
      volumes:
        - name: nginx-html
          configMap:
            name: nginx-page
EOF_YAML
k apply -f backend.yaml
k rollout status deployment/nginx --timeout=240s
k get deployment nginx
k get pods -l app=nginx -o wide
```

Oczekuj `READY 8/8`, ośmiu Podów `1/1 Running` i nazwy Podu na stronie. Nazwy i IP będą inne niż w rozmowie. `containerPort` opisuje port aplikacji; sam nie wystawia go poza klaster.

Oficjalny entrypoint obrazu NGINX przetwarza pliki `.template` przy starcie i zapisuje wynik do `NGINX_ENVSUBST_OUTPUT_DIR`. Downward API dostarcza nazwę i IP Podu. Sama ConfigMap nie wykonuje podstawiania. Filtr ogranicza podstawienia do dwóch zmiennych.

## 4. NodePort i headless Service

```bash
cat > services.yaml <<'EOF_YAML'
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: nginx-lab
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 32451
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-headless
  namespace: nginx-lab
spec:
  clusterIP: None
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: http
EOF_YAML
k apply -f services.yaml
k get services
microk8s kubectl get nodes -o wide
```

Ustaw osiągalny z klienta adres węzła; adres z rozmowy był tylko przykładem:

```bash
NODE_IP=192.168.0.44   # zastąp swoim adresem z get nodes
curl -fsS "http://${NODE_IP}:32451/"
for i in $(seq 1 30); do
  curl -fsS "http://${NODE_IP}:32451/" | sed -n 's/.*<p>Pod: \(.*\)<\/p>.*/\1/p'
done | sort | uniq -c
```

NodePort 32451 i 32452 muszą być wolne w całym klastrze, także w innych namespace. Sprawdź `microk8s kubectl get svc -A`; w razie kolizji wybierz inne porty z zakresu skonfigurowanego w klastrze (domyślnie 30000–32767) i zmień także polecenia curl. Dostęp wymaga routingu i reguł zapory dopuszczających ruch z sieci ćwiczeniowej.

Zwykły Service ma wirtualny ClusterIP; jego DNS wskazuje na ten adres. Headless (`clusterIP: None`) pozwala klientowi uzyskać adresy gotowych Podów bez wirtualnego IP. Sam nie pełni roli proxy. Tutaj nie ustawiamy `publishNotReadyAddresses`, aby nie publikować niegotowych backendów.

Liczby odpowiedzi nie muszą być równe; rozkład zależy m.in. od połączeń, conntrack i liczby próbek. Odświeżanie przeglądarki nie jest wiarygodnym testem równomierności.

## 5. EndpointSlice oraz DNS

```bash
k get endpointslices -l kubernetes.io/service-name=nginx-headless
k get endpointslices -l kubernetes.io/service-name=nginx-headless -o yaml
k get endpointslices -l kubernetes.io/service-name=nginx-headless \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\t"}{.conditions.ready}{"\t"}{.targetRef.name}{"\n"}{end}'
k run dns-check --image=busybox:1.37 --restart=Never \
  --command -- sleep 3600
k wait --for=condition=Ready pod/dns-check --timeout=120s
k exec dns-check -- nslookup nginx.nginx-lab.svc.cluster.local
k exec dns-check -- nslookup nginx-headless.nginx-lab.svc.cluster.local
```

Porównaj adresy DNS headless z `status.podIP` i EndpointSlice. W spokojnym klastrze IPv4 powinno być osiem gotowych backendów; w trakcie rolloutów wynik jest przejściowy. Może istnieć więcej niż jeden Slice, dlatego odczytujemy wszystkie. W dual-stack adresów może być więcej niż Podów. `cluster.local` jest domyślną domeną klastra — przy innej domenie zmień FQDN także w konfiguracji LB.

EndpointSlice zawiera adresy, porty, wskazania Podów i warunki, np. `ready`, `serving`, `terminating`. To właściwy obiekt do diagnostyki współczesnych Service; stare API Endpoints jest przestarzałe. Nie edytuj ręcznie Slice zarządzanych przez kontroler Service.

## 6. nginx-lb z dynamicznym DNS

NGINX ma kierować ruch bezpośrednio do IP backendów odkrywanych przez headless DNS. Statyczna nazwa upstreamu rozwiązana tylko przy starcie może zachować nieaktualne IP. Użyj `resolve`, pamięci współdzielonej `zone` i resolvera DNS. W otwartym NGINX ta funkcja jest dostępna od 1.27.3.

Pobierz rzeczywisty ClusterIP DNS — nie zakładaj z góry adresu `10.152.183.10`:

```bash
DNS_IP=$(microk8s kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')
printf 'DNS klastra: %s\n' "$DNS_IP"
```

Ten wariant laboratorium zakłada IPv4. Jeśli DNS_IP jest adresem IPv6, dostosuj zapis `resolver` (nawiasy kwadratowe) i politykę rozwiązywania adresów.

```bash
cat > default.conf.template <<'EOF_CONF'
resolver ${DNS_IP} valid=5s ipv6=off;
resolver_timeout 2s;
upstream nginx_backends {
    zone nginx_backends 64k;
    server nginx-headless.nginx-lab.svc.cluster.local:80 resolve;
}
server {
    listen 80;
    location = /healthz {
        access_log off;
        return 200 "ok\n";
    }
    location / {
        proxy_pass http://nginx_backends;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 2s;
        proxy_read_timeout 5s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        add_header X-Upstream-Addr $upstream_addr always;
    }
}
EOF_CONF
k create configmap nginx-lb-conf --from-file=default.conf.template \
  --dry-run=client -o yaml > lb-configmap.yaml
k apply -f lb-configmap.yaml
cat > lb.yaml <<'EOF_YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-lb
  namespace: nginx-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-lb
  template:
    metadata:
      labels:
        app: nginx-lb
    spec:
      containers:
        - name: nginx-lb
          image: nginx:1.28
          ports:
            - name: http
              containerPort: 80
          env:
            - name: DNS_IP
              value: REPLACE_DNS_IP
            - name: NGINX_ENVSUBST_FILTER
              value: '^DNS_IP$'
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: 25m
              memory: 32Mi
            limits:
              cpu: 250m
              memory: 128Mi
          volumeMounts:
            - name: config
              mountPath: /etc/nginx/templates/default.conf.template
              subPath: default.conf.template
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: nginx-lb-conf
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
  namespace: nginx-lab
spec:
  type: NodePort
  selector:
    app: nginx-lb
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 32452
EOF_YAML
sed -i "s/REPLACE_DNS_IP/${DNS_IP}/" lb.yaml
k apply -f lb.yaml
k rollout status deployment/nginx-lb --timeout=180s
k exec deployment/nginx-lb -- nginx -t
k exec deployment/nginx-lb -- nginx -T
curl -fsS -D - "http://${NODE_IP}:32452/"
```

Nagłówek `X-Upstream-Addr` pokazuje adres wybranego backendu, a strona nazwę Podu. Filtr envsubst zachowuje zmienne NGINX `$host`, `$remote_addr`, `$upstream_addr`. `/healthz` sprawdza lokalny proces LB, a nie dostępność wszystkich backendów. Dzięki temu awaria backendów nie powoduje pętli restartów proxy.

`valid=5s` ogranicza czas cache w NGINX, ale nie gwarantuje natychmiastowego wycofania IP: dochodzi propagacja EndpointSlice, cache DNS i istniejące połączenia. Próby ponowienia są tu pokazane dla prostych odczytów HTTP; dla operacji zapisujących dane wymagają osobnej analizy.

## 7. Samonaprawianie i aktualizacja adresów

W drugim terminalu uruchom funkcję `k` i obserwację:

```bash
k get pods -l app=nginx -o wide --watch
```

W pierwszym terminalu usuń jedną instancję wyłącznie z laboratorium:

```bash
POD=$(k get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
k delete pod "$POD"
k rollout status deployment/nginx --timeout=240s
k get pods -l app=nginx -o wide
k get endpointslices -l kubernetes.io/service-name=nginx-headless -o wide
for i in $(seq 1 30); do
  curl --max-time 3 -sS -D - "http://${NODE_IP}:32452/" | sed -n '/X-Upstream-Addr/Ip; /<p>Pod:/p'
  sleep 1
done
```

Nowy Pod powinien mieć inną nazwę; IP może zostać ponownie użyte. Po zbieżności DNS LB powinien korzystać z bieżącego zestawu gotowych backendów bez restartu LB. Podczas propagacji możliwe są krótkie błędy. `rollout status` nie czeka na opróżnienie cache DNS.

## 8. Readiness i liveness — kontrolowana awaria

Readiness po kolejnych niepowodzeniach oznacza Pod jako niegotowy i wycofuje go z normalnej obsługi Service. Nie restartuje kontenera. Liveness po progu niepowodzeń restartuje kontener; nie tworzy nowego Podu. Startup probe, jeśli jest skonfigurowana, wstrzymuje pozostałe probes do pomyślnego startu. Dla prostego NGINX tutaj jej nie potrzebujemy.

Usuń wygenerowaną stronę w jednym Podzie. Nie zmieniasz ConfigMap:

```bash
POD=$(k get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
k exec "$POD" -- rm /usr/share/nginx/html/index.html
k get pod "$POD" --watch
```

Przerwij obserwację Ctrl+C po około minucie i sprawdź:

```bash
k describe pod "$POD"
k logs "$POD" --previous
k get endpointslices -l kubernetes.io/service-name=nginx-headless -o yaml
```

NGINX zwykle zwróci 403 dla katalogu bez indeksu; to niepowodzenie probe. Najpierw zobaczysz `0/1`, potem wzrost `RESTARTS`, a po ponownym wygenerowaniu strony `1/1`. Czas zależy od harmonogramu probes. Jeśli chcesz zobaczyć przejściowe `ready: false`, obserwuj EndpointSlice równolegle — po powrocie do zdrowia ślad zniknie. Pod i jego IP przy restarcie kontenera zwykle pozostają te same.

## 9. ConfigMap v2 i RollingUpdate

Montaż `subPath` nie otrzymuje aktualizacji ConfigMap. Dodatkowo strona jest generowana tylko przy starcie, więc sama zmiana ConfigMap nie odświeża HTML. Restart kontenerów w ramach rollout odczyta nowe dane. Nawet zwykły wolumen ConfigMap z późniejszą aktualizacją nie uruchamia sam envsubst ani przeładowania NGINX.

```bash
cp backend.yaml backend-v1.yaml
sed -i 's/Wersja strony: v1/Wersja strony: v2/' backend.yaml
k apply -f backend.yaml
k annotate deployment/nginx kubernetes.io/change-cause="Strona v2 + rollout restart" --overwrite
k rollout restart deployment/nginx
k rollout status deployment/nginx --timeout=240s
curl -fsS "http://${NODE_IP}:32452/"
k get replicasets -l app=nginx
k rollout history deployment/nginx
```

`maxSurge: 1` pozwala na dziewiąty aktywny Pod, a `maxUnavailable: 0` utrzymuje osiem dostępnych podczas prawidłowego rollout. Kończące pracę Pody mogą chwilowo zwiększyć rzeczywistą liczbę procesów ponad dziewięć. Potrzebny jest zapas zasobów. `minReadySeconds: 5` wymaga stabilnej gotowości przed uznaniem nowej repliki za dostępną. Nie jest to gwarancja braku błędów klienta, szczególnie przy cache DNS bezpośrednich IP.

Skalowanie `k scale deployment/nginx --replicas=8` zmienia liczbę replik, ale nie tworzy nowej rewizji szablonu. `rollout restart` zmienia adnotację szablonu Podu i wywołuje nowy rollout. Zmiana wyłącznie ConfigMap także nie tworzy rewizji Deploymentu.

## 10. Awaria wdrożenia i rollback

Zapisz numer dobrej rewizji po poprzednim rollout. Nie zakładaj, że będzie to 8:

```bash
GOOD_REV=$(k get deployment nginx -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
printf 'Dobra rewizja: %s\n' "$GOOD_REV"
k rollout history deployment/nginx --revision="$GOOD_REV"
k annotate deployment/nginx kubernetes.io/change-cause="Test błędu: nieistniejący obraz" --overwrite
k set image deployment/nginx nginx=nginx:lab-nieistniejacy-tag
k rollout status deployment/nginx --timeout=60s
```

Ostatnie polecenie ma zakończyć się niepowodzeniem. W Bash bez `set -e` kontynuuj poniżej; w skrypcie obsłuż oczekiwany błąd jawnie. Sprawdź przyczynę:

```bash
k get pods -l app=nginx
k get replicasets -l app=nginx
k get events --sort-by=.metadata.creationTimestamp
curl -fsS "http://${NODE_IP}:32452/"
```

Nowa replika powinna zatrzymać się na `ErrImagePull` / `ImagePullBackOff`, a osiem starych pozostać dostępnych, o ile nie ma innych awarii. Po przekroczeniu `progressDeadlineSeconds` Deployment może zgłosić `ProgressDeadlineExceeded`; Kubernetes nie wykonuje wtedy automatycznego rollbacku.

```bash
k rollout undo deployment/nginx --to-revision="$GOOD_REV"
k rollout status deployment/nginx --timeout=240s
k get deployment nginx
k rollout history deployment/nginx
curl -fsS "http://${NODE_IP}:32452/"
```

Bez `--to-revision` cofnięcie wybiera poprzednią rewizję, która nie zawsze jest tą oczekiwaną. Rollback odtwarza szablon Podów, a nie pełny stan wszystkich zasobów. Nie przywraca zawartości ConfigMap ani Service i nie służy do cofania skalowania. Po tym ćwiczeniu strona nadal jest v2.

Aby świadomie przywrócić dane v1:

```bash
k apply -f backend-v1.yaml
k annotate deployment/nginx kubernetes.io/change-cause="Przywrócenie danych strony v1" --overwrite
k rollout restart deployment/nginx
k rollout status deployment/nginx --timeout=240s
curl -fsS "http://${NODE_IP}:32452/"
cp backend-v1.yaml backend.yaml
```

Dla przewidywalnego rollbacku konfiguracji twórz osobne, niezmienne ConfigMap, np. `nginx-page-v1` i `nginx-page-v2`, i zmieniaj ich nazwę w szablonie Deploymentu. Wtedy rewizja wskazuje odpowiednią wersję danych. Zachowuj stare ConfigMap tak długo, jak potrzebne są rollbacki; analogicznie wersjonuj konfigurację LB.

## 11. Dlaczego w rozmowie zniknęła rewizja 6?

W dostępnej historii rewizja 6 i późniejsza 8 miały ten sam hash `75747ff755`, natomiast 7 zawierała `kubectl.kubernetes.io/restartedAt`. To jest zgodne z rollbackiem do wcześniejszego szablonu: kontroler może ponownie wykorzystać wcześniejszy ReplicaSet i nadać mu nowy numer rewizji. Sam hash nie oznacza numeru wersji aplikacji. Bez pełnego stanu klastra jest to wyjaśnienie zgodne z obserwacją, a nie dowód dokładnej sekwencji poleceń.

ReplicaSety z `DESIRED/CURRENT/READY = 0` są normalną historią wdrożeń. Nie uruchamiają dodatkowych ośmiu serwerów. Nie kasuj ich ręcznie podczas nauki rollbacku. `revisionHistoryLimit` ogranicza zachowywaną historię; rewizje nie muszą być ciągłe. `<none>` w CHANGE-CAUSE oznacza brak adnotacji `kubernetes.io/change-cause`, a nie brak zmiany.

```bash
k get replicasets -l app=nginx \
  -o custom-columns='NAME:.metadata.name,REVISION:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,READY:.status.readyReplicas'
k rollout history deployment/nginx
```

Adnotację przyczyny ustawiaj przed zmianą szablonu. Nie polegaj na przestarzałym `--record`.

## 12. Diagnostyka: od objawu do przyczyny

| Objaw | Co sprawdzić | Typowe rozwiązanie |
|---|---|---|
| Pod Pending | `k describe pod NAZWA` | brak zasobów, tainty lub problem węzła; zapewnij zasoby na surge |
| ImagePullBackOff | Events w `describe` | popraw tag, dostęp do rejestru lub łączność |
| CrashLoopBackOff | `k logs NAZWA --previous` | popraw konfigurację; dla LB sprawdź wersję NGINX i resolver |
| Running, ale 0/1 | `k describe pod NAZWA` | sprawdź ścieżkę, port i wynik HTTP probe |
| Service nie odpowiada | `k get svc`, selektory, etykiety Podów, EndpointSlice | popraw selektor/targetPort; przywróć gotowe backendy |
| NodePort nieosiągalny | adres węzła, routing, zapora, zajętość portów | dopasuj adres i dostęp z LAN |
| DNS nie zwraca backendów | `nslookup` z dns-check, CoreDNS, ready w Slice | sprawdź namespace, domenę klastra i readiness |
| LB zwraca 502/504 | `k logs deployment/nginx-lb`, `nginx -T`, nagłówki | sprawdź osiągalność IP backendów i DNS; poczekaj na propagację |
| ConfigMap zmieniona, strona stara | mount subPath i proces generowania | wykonaj kontrolowany rollout restart |
| Rollout utknął przy 8 starych Podach | nowy Pod i zapas zasobów | usuń przyczynę lub wykonaj rollback |

Dodatkowe polecenia:

```bash
k get deploy,rs,pods,svc,cm
k describe deployment nginx
k logs deployment/nginx --tail=50
k logs deployment/nginx-lb --tail=50
k exec deployment/nginx -- cat /usr/share/nginx/html/index.html
k exec deployment/nginx-lb -- cat /etc/resolv.conf
microk8s kubectl -n kube-system get pods -l k8s-app=kube-dns
```

`logs deployment/nginx` wybiera jedną instancję; dla konkretnej awarii podaj nazwę Podu. W razie potrzeby sprawdź ruch z wnętrza klastra: `k exec dns-check -- wget -qO- http://nginx/`. Rozdziela to problem aplikacji/Service od zewnętrznego dostępu przez NodePort.

## 13. Kryteria ukończenia

- Deployment `nginx` ma osiem gotowych replik.
- Port 32451 udostępnia stronę v1/v2 z nazwą obsługującego Podu.
- Headless DNS zwraca aktualne adresy gotowych backendów.
- EndpointSlice daje się powiązać z nazwami i IP Podów.
- Port 32452 działa przez nginx-lb; nagłówek wskazuje backend.
- Usunięty Pod zostaje zastąpiony bez ręcznej zmiany konfiguracji LB.
- Usunięcie HTML prowadzi do utraty readiness i restartu kontenera przez liveness.
- Zmiana strony wymaga ponownego startu; rollout kończy się sukcesem.
- Błędny obraz blokuje nową replikę; rollback przywraca działający szablon.
- Potrafisz wyjaśnić, dlaczego rollback Deploymentu nie cofa danych ConfigMap.

## 14. Sprzątanie

Wykonaj tylko po zakończeniu ćwiczeń. Polecenie usuwa wszystkie zasoby w namespace laboratorium, w tym Pod diagnostyczny:

```bash
microk8s kubectl delete namespace nginx-lab
```

Nie wykonuj `microk8s reset` — usunąłby także pozostałe zasoby klastra. Lokalne pliki YAML możesz zachować jako zapis ćwiczeń.

## 15. Źródła i zakres sprawdzenia

Oficjalne źródła do samodzielnego rozwijania tematów:

- [MicroK8s: instalacja i przygotowanie](https://canonical.com/microk8s/docs/getting-started)
- [MicroK8s: dodatek DNS](https://discuss.kubernetes.io/t/microk8s-addon-dns/22807)
- [Kubernetes: Service, NodePort i headless](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes: EndpointSlice](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [Kubernetes: probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Kubernetes: Deployment, RollingUpdate i rollback](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes: ConfigMap i ograniczenie subPath](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [NGINX: upstream, zone, resolver i resolve](https://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [NGINX 1.27.3: udostępnienie resolve](https://mailman.nginx.org/pipermail/nginx-announce/2024/WSOA5BERDSWSFOBY6H5VO7SICBG6R5B5.html)
- [Oficjalny obraz NGINX: skrypt envsubst](https://github.com/nginx/docker-nginx/blob/master/entrypoint/20-envsubst-on-templates.sh)

Materiał sprawdzono statycznie pod kątem składni manifestów i poleceń Bash. Nie wykonano wdrożenia na klastrze użytkownika ani testu ruchu na żywo. Wyniki w tekście są kryteriami do sprawdzenia podczas laboratorium, a nie raportem z pomiarów.

## 16. Wszystkie polecenia jako osobne skrypty

Każdy blok Bash z tego tutorialu jest dostępny jako osobny, numerowany plik `.sh` w [scripts/](scripts/README.md). Instrukcja wyjaśnia kolejność, zmienne środowiskowe i ćwiczenia uruchamiane w osobnym terminalu. Skrypty zapisują stan potrzebny między procesami (nazwę Podu i numer dobrej rewizji); nie uruchamiaj ich wszystkich automatycznie.
