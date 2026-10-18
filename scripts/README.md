# Skrypty laboratorium MicroK8s

Każdy z 21 bloków Bash tutorialu ma osobny, numerowany plik `.sh`.
`00-common.sh` zawiera wspólną funkcję `k`, katalog roboczy i kontrolę NODE_IP.
Skrypty uruchamiaj pojedynczo, po przeczytaniu odpowiedniego rozdziału tutorialu.
Nie uruchamiaj całego katalogu w pętli: obejmuje instalację, celowe awarie i usuwanie zasobów.

```bash
# Z katalogu głównego sklonowanego repozytorium:
bash scripts/01-instalacja.sh  # tylko jeśli MicroK8s nie jest zainstalowany
# Następnie wyloguj się i zaloguj ponownie.
bash scripts/02-kontrola-klastra.sh
bash scripts/03-namespace.sh
bash scripts/04-backend.sh
bash scripts/05-services.sh
export NODE_IP=192.168.0.44  # zastąp osiągalnym adresem własnego węzła
bash scripts/06-test-nodeport.sh
```

Kontynuuj według numerów i poniższej tabeli. Wymagania: Bash, MicroK8s,
standardowe narzędzia Linux i curl. Nie uruchamiaj skryptów przez `sh`.
Pliki YAML i konfiguracja NGINX są generowane przez skrypty w
`${LAB_DIR:-$HOME/microk8s-nginx-lab}`. Opcjonalny LAB_DIR ustawiaj identycznie
we wszystkich terminalach. NODE_IP ustawiaj również w każdym terminalu testującym HTTP.
Skrypt 09 sam pobiera DNS_IP, więc nie zależy od zmiennych procesu skryptu 08.
Skrypt 12 zapisuje nazwę Podu do diagnostyki 13, a 15 zapisuje dobrą rewizję dla 17.
Nie nadpisuj pliku good-revision.txt przez ponowne uruchomienie 15 przed rollbackiem.

Skrypt 10 działa w osobnym terminalu; obserwację kończy Ctrl+C.
W 12 przerwij obserwację po około minucie; następnie uruchom 13.
Skrypt 15 celowo wdraża nieistniejący obraz i obsługuje oczekiwane niepowodzenie.
Skrypt 14 uruchom raz po wdrożeniu v1, aby zachować prawidłową kopię v1.
Skrypt 21 usuwa cały namespace nginx-lab — uruchom go dopiero po ćwiczeniach.
Skrypty zakładają kolejność i stan laboratorium; nie wszystkie są idempotentne.
Przed użyciem sprawdź wolne NodePort 32451/32452 i ewentualnie dopasuj pliki.

| Plik | Odpowiada blokowi Bash w tutorialu |
|---|---|
| [01-instalacja.sh](01-instalacja.sh) | 1 |
| [02-kontrola-klastra.sh](02-kontrola-klastra.sh) | 2 |
| [03-namespace.sh](03-namespace.sh) | 3 |
| [04-backend.sh](04-backend.sh) | 4 |
| [05-services.sh](05-services.sh) | 5 |
| [06-test-nodeport.sh](06-test-nodeport.sh) | 6 |
| [07-endpointslice-dns.sh](07-endpointslice-dns.sh) | 7 |
| [08-adres-dns.sh](08-adres-dns.sh) | 8 |
| [09-nginx-lb.sh](09-nginx-lb.sh) | 9 |
| [10-obserwacja-podow.sh](10-obserwacja-podow.sh) | 10 |
| [11-samonaprawianie.sh](11-samonaprawianie.sh) | 11 |
| [12-awaria-probes.sh](12-awaria-probes.sh) | 12 |
| [13-diagnostyka-probes.sh](13-diagnostyka-probes.sh) | 13 |
| [14-rolling-update-v2.sh](14-rolling-update-v2.sh) | 14 |
| [15-bledny-obraz.sh](15-bledny-obraz.sh) | 15 |
| [16-diagnostyka-rolloutu.sh](16-diagnostyka-rolloutu.sh) | 16 |
| [17-rollback.sh](17-rollback.sh) | 17 |
| [18-przywrocenie-v1.sh](18-przywrocenie-v1.sh) | 18 |
| [19-historia-rewizji.sh](19-historia-rewizji.sh) | 19 |
| [20-diagnostyka.sh](20-diagnostyka.sh) | 20 |
| [21-sprzatanie.sh](21-sprzatanie.sh) | 21 |

Weryfikacja: `bash -n` dla wszystkich plików. Nie wykonano wdrożenia na żywym klastrze.
