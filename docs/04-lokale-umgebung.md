# 04 – Lokale Umgebung einrichten

> Lokalen Stack starten und Shopware installieren.
> Vorher: [03 – Projekt aufsetzen](03-projekt-aufsetzen.md) · Danach: [05 – Server vorbereiten](05-server-vorbereiten.md)

Es gibt zwei gleichwertige Wege: **Docker** oder **devenv/Nix**. Beide Konfigurationen liegen immer im Projekt, und jeder Entwickler nutzt den Stack, mit dem er lieber arbeitet – im selben Projekt können Kollegen problemlos unterschiedliche Wege fahren.

> **Gut zu wissen für die Fehlersuche:** Die beiden Stacks unterscheiden sich in Datenbank (MariaDB 11.8 vs. MySQL 8.4) und Mail-Catcher (Mailpit vs. MailHog). Tritt ein Fehler nur bei einem Kollegen auf, lohnt der erste Blick darauf, welcher Stack dort läuft.

---

## Voraussetzung: `auth.json`

Egal welcher Weg – die `auth.json` muss im Projekt-Root liegen und befüllt sein, **bevor** der erste `composer install` läuft. Siehe [02 – GitLab-Projekt](02-gitlab-projekt.md).

---

## Weg A – Docker

### Stack konfigurieren

In `docker-compose.yml` wurden in Schritt [03](03-projekt-aufsetzen.md) bereits die `[projekt_name]`-Platzhalter ersetzt – inklusive des Compose-Projektnamens in Zeile 11:

```yaml
name: <projekt_name>
```

Er präfixt Volumes und Netzwerke und hält damit mehrere parallel laufende Projekte auseinander.

Prüfe zusätzlich die Versionen im `shop`-Service (Zeile 32–36):

```yaml
environment:
    - XDEBUG_ENABLED=1
    - FILEBEAT_ENABLED=0
    - PHP_VERSION=8.4
    - NODE_VERSION=24
```

### Services

| Service | Image | Erreichbar unter |
|---|---|---|
| `shop` | `dockware/web:latest` | http://localhost (Ports 22, 80, 8888 Watch-Admin, 9999 Watch-Storefront) |
| `db` | `mariadb:11.8` | `localhost:3306` – DB `shopware`, User `shopware`/`shopware`, root-PW `root` |
| `mailpit` | `axllent/mailpit:v1.22` | http://localhost:8025 (SMTP `localhost:1025`) |
| `adminer` | `adminer:4.8.1` | http://localhost:8080 |
| `redis` | `redis:7.4-alpine` | auskommentiert – bei Bedarf aktivieren |

> **Achtung:** Der `shop`-Service mappt Port `22:22` (`docker-compose.yml:19`). Auf jedem Rechner mit laufendem SSH-Daemon kollidiert das. Ändere das Mapping auf `"2222:22"`, wenn der Stack nicht startet.

### Starten

```bash
docker compose up -d
```

Anschließend arbeitest du **im Container**:

```bash
docker compose exec shop bash
```

Das Projektverzeichnis wird in `/var/www/html` gemountet.

---

## Weg B – devenv (Nix)

### Voraussetzungen

- [Nix](https://nixos.org/download) mit aktivierten Flakes
- [devenv](https://devenv.sh/getting-started/)
- [direnv](https://direnv.net/) (optional, aber empfohlen – `.envrc` liegt im Projekt)

### Konfiguration

In `devenv.nix` wurde in Schritt [03](03-projekt-aufsetzen.md) `[PROJECT]` ersetzt. Daraus ergibt sich die lokale URL:

```
http://<projekt>.localhost
```

### Services

| Service | Version / Port |
|---|---|
| Caddy | `http://<projekt>.localhost` |
| MySQL | `pkgs.mysql84`, DB `shopware`, User `shopware`/`shopware` |
| Redis | Port 6379 (auch als PHP-Session-Handler konfiguriert) |
| MailHog | SMTP `localhost:1025` |
| Elasticsearch / RabbitMQ | auskommentiert |

Zusätzlich laufen zwei Hintergrundprozesse (`devenv.nix:114ff`):

- `queue-worker` – `messenger:consume --time-limit=300 async low_priority failed scheduler_shopware`
- `scheduled-task-runner` – `scheduled-task:run`

PHP 8.4 mit `xdebug` (Port 9003), `redis`, `amqp`, `grpc`, `zstd`; Node 24; `shopware-cli` ist im Shell-Environment enthalten.

### Starten

```bash
direnv allow     # einmalig, falls direnv genutzt wird
devenv up
```

> **Hinweis:** Docker und devenv nutzen unterschiedliche Datenbanken (MariaDB 11.8 vs. MySQL 8.4) und Mail-Catcher (Mailpit vs. MailHog). Bei Migrationen und SQL-Modes kann das relevant werden. Lässt sich ein Fehler bei einem Kollegen nicht reproduzieren, prüfe zuerst, welcher Stack dort läuft – und im Zweifel gegen den zweiten Stack gegentesten.

---

## Gemeinsam: Shopware installieren

Ein einziges Kommando erledigt den kompletten Erstaufsatz:

```bash
make deployment-install
```

Das Target (`Makefile:52-61`) führt der Reihe nach aus:

| Schritt | Kommando | Bedeutung |
|---|---|---|
| 1 | `cd .deployment && composer install` | Deployer 8 installieren |
| 2 | `composer install --no-scripts` | Shopware + Plugins installieren |
| 3 | `composer bin all install --no-scripts` | PHPStan, CS-Fixer, Rector nach `vendor-bin/` |
| 4 | `composer symfony:recipes:install --yes` | Flex-Recipes anwenden → erzeugt `bin/console`, `src/Kernel.php`, `config/bundles.php` … |
| 5 | `chmod 755 bin/* .local/*` | Ausführungsrechte setzen |
| 6 | `bin/console system:setup --force` | Erzeugt `.env` inkl. `APP_SECRET` und `INSTANCE_ID` |
| 7 | `bin/console system:install --create-database --basic-setup --shop-locale=de-DE` | Datenbank anlegen, Grundinstallation, **deutsche Standardsprache** |
| 8 | `make build-js` | Storefront und Administration bauen |

> **Wichtig:** `--shop-locale=de-DE` sorgt dafür, dass Shopware Deutsch als Standardsprache führt. Wird die Datenbank ohne diesen Parameter erzeugt, ist Englisch die Systemsprache und die Korrektur nachträglich aufwendig.

### Wenn `system:setup` interaktiv nachfragt

Bei abweichender Konfiguration kannst du den Schritt einzeln ausführen:

```bash
bin/console system:setup
```

| Frage | Antwort (Docker) | Antwort (devenv) |
|---|---|---|
| Environment | `dev` | `dev` |
| URL | `http://localhost` | `http://<projekt>.localhost` |
| Blue Green Deployment | `no` | `no` |
| Database user | `root` | `root` |
| Database password | `root` | *(leer)* |
| Database host | `<projekt_name>_db` | `localhost` |
| Database port | `3306` | `3306` |
| Database name | `shopware` | `shopware` |
| Database SSL CA / Cert / Key | *(leer)* | *(leer)* |
| Skip verification | `yes` | `yes` |

---

## Nacharbeit

### 1. `.env` prüfen

```bash
cat .env
```

`APP_SECRET` und `INSTANCE_ID` müssen jetzt echte Werte enthalten und nicht mehr `change-me-to-a-random-string-32-chars-min`.

### 2. `APP_SECRET` in GitLab nachtragen

Den Wert aus der `.env` als CI/CD-Variable `APP_SECRET` in der Projektgruppe hinterlegen – das war der offene Punkt aus [02](02-gitlab-projekt.md).

### 3. `install.lock` prüfen

```bash
ls -la install.lock
```

Existiert die Datei nicht, lege sie leer an:

```bash
touch install.lock
```

Sie gehört zu den `shared_files` (`deploy.php:17-23`) und wird auf dem Server separat benötigt.

### 4. JavaScript bauen

Falls Schritt 8 von `make deployment-install` fehlgeschlagen ist, lassen sich beide Teile einzeln bauen:

```bash
make build-storefront
make build-admin
```

---

## Der Alltag

| Kommando | Zweck |
|---|---|
| `make build-js` | Storefront + Administration bauen |
| `make watch-storefront` | Storefront-Dev-Server (Hot Proxy) |
| `make watch-admin` | Administration-Dev-Server |
| `make cache-clear` / `make cache-warmup` | Shopware-Cache |
| `make check-ci` | CS-Check + PHPStan + PHPUnit – **vor jedem Push** |
| `make cs-fix` | Code-Style automatisch korrigieren |
| `make deployment-update-composer` | Abhängigkeiten aktualisieren |
| `make help` | Alle Targets anzeigen |

> **Achtung:** Für den Build gibt es zwei Wege. `make build-*` nutzt `shopware-cli` und ist deckungsgleich mit der CI-Pipeline – nutze diesen. Die Composer-Scripts `composer build:js`, `build:js:admin`, `build:js:storefront` rufen direkt npm auf und können abweichende Ergebnisse liefern.

---

## Checkliste

- [ ] `auth.json` liegt im Projekt-Root und ist befüllt
- [ ] Lokaler Stack läuft (`docker compose up -d` bzw. `devenv up`)
- [ ] `make deployment-install` fehlerfrei durchgelaufen
- [ ] Shop lokal erreichbar, Admin unter `/admin`
- [ ] `.env` enthält echte Werte für `APP_SECRET` und `INSTANCE_ID`
- [ ] `APP_SECRET` als CI/CD-Variable in GitLab hinterlegt
- [ ] `install.lock` existiert
- [ ] `make build-js` erfolgreich

---

→ [05 – Server vorbereiten](05-server-vorbereiten.md)
