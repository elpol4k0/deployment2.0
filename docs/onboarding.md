# Onboarding – in ein bestehendes 2.0-Projekt einsteigen

> Für Entwickler, die zu einem laufenden Projekt dazukommen. Hier wird **nichts neu aufgesetzt** – dafür siehe [02](02-gitlab-projekt.md) bis [06](06-erstes-deployment.md).

---

## 1. Zugänge besorgen

Bevor du loslegst, brauchst du:

- [ ] Zugriff auf die GitLab-Kunden-Gruppe (mindestens Developer)
- [ ] Deinen persönlichen SSH-Key bei `gitlab.agiqon.de` hinterlegt (`Preferences → SSH Keys`)
- [ ] Die Werte für `DEPLOY_TOKEN_USER`, `DEPLOY_TOKEN` und `SW_COMPOSER_TOKEN` – aus `Settings → CI/CD → Variables` der Projektgruppe
- [ ] Zugang zum Staging-Server (für Datenbank-Dumps und Logs)

---

## 2. Projekt klonen

```bash
git clone git@gitlab.agiqon.de:<kunde>/project.git
cd project
```

Der Default-Branch ist `develop`.

---

## 3. `auth.json` anlegen

```bash
cp auth.json.dist auth.json
```

Und mit den Token-Werten aus Schritt 1 befüllen:

```json
{
    "gitlab-token": {
        "gitlab.agiqon.de": {
            "username": "<DEPLOY_TOKEN_USER>",
            "token": "<DEPLOY_TOKEN>"
        }
    },
    "bearer": {
        "packages.shopware.com": "<SW_COMPOSER_TOKEN>"
    }
}
```

Die Datei ist gitignored und wird nie committet.

---

## 4. Lokale Umgebung starten

Beide Wege liegen im Projekt bereit. Nimm den, mit dem du lieber arbeitest – Kollegen im selben Projekt können den jeweils anderen nutzen.

| Umgebung | Start | Besonderheit |
|---|---|---|
| Docker | `docker compose up -d` | dockware, MariaDB 11.8, Mailpit; Shop unter http://localhost |
| devenv/Nix | `direnv allow` + `devenv up` | MySQL 8.4, MailHog, Redis; Shop unter `http://<projekt>.localhost` |

Details: [04 – Lokale Umgebung](04-lokale-umgebung.md).

> **Für die Fehlersuche:** Lässt sich ein Fehler bei einem Kollegen nicht nachstellen, prüfe zuerst, welchen Stack er nutzt – die Datenbank-Engines unterscheiden sich.

---

## 5. Installieren

```bash
make deployment-install
```

Das Target installiert Composer-Abhängigkeiten, wendet die Flex-Recipes an (dabei entstehen `bin/console`, `src/Kernel.php` usw.), richtet Shopware ein und baut die Assets.

> **Achtung:** `make deployment-install` führt `system:install --create-database` aus und legt damit eine **leere** Shopware-Installation an. Wenn du stattdessen mit den Daten aus Staging arbeiten willst, spiele nach dem Install den Dump ein (Schritt 6).

---

## 6. Datenbank aus Staging übernehmen

```bash
# auf dem Staging-Server
mysqldump -u <user> -p <datenbank> > staging.sql

# lokal einspielen
mysql -u root -proot shopware < staging.sql
bin/console cache:clear
```

Danach in der lokalen `.env` prüfen, dass `APP_URL` auf die lokale Adresse zeigt, und im Admin die Sales-Channel-Domains anpassen – sonst leiten Links auf die Staging-Domain.

Medien werden nicht mit übertragen. Für lokale Tests genügt in der Regel der Platzhalter; bei Bedarf `shared/public/media` per rsync holen.

---

## 7. Assets bauen

```bash
make build-js
```

Für die tägliche Arbeit:

```bash
make watch-storefront   # Storefront-Dev-Server
make watch-admin        # Administration-Dev-Server
```

---

## Arbeiten im Projekt

### Branch-Workflow

```
feature/<name> → Merge Request → develop → Staging deployt automatisch
                                    ↓
                  Merge Request develop → main → Production deployt automatisch
```

- Feature-Branches lösen **kein** Deployment aus
- Ein Merge nach `develop` deployt nach Staging
- Ein Merge nach `main` deployt nach Production

### Vor jedem Push

```bash
make check-ci       # CS-Check + PHPStan + PHPUnit
make cs-fix         # Code-Style automatisch korrigieren
```

> **Beachte:** Die Qualitäts-Jobs in der Pipeline haben `allow_failure: true` und blockieren nichts. Die Prüfung liegt damit in deiner Verantwortung – `make check-ci` lokal laufen zu lassen, ist kein optionaler Schritt.

### Plugins

Welche Plugins das Projekt nutzt, steht im `require`-Block der `composer.json`:

- `agiqon/*` mit `dev-main` → projekteigenes oder globales Plugin aus GitLab
- `store.shopware.com/*` → gekauftes Store-Plugin
- Pfade unter `custom/` → lokal eingebundene Plugins

Wie du Plugins hinzufügst und aktualisierst: [plugins/README.md](plugins/README.md).

**Wichtig:** Nach einer Änderung in einem Plugin-Repo passiert im Projekt nichts von allein. Du musst im Projekt-Repo eine Pipeline auslösen.

### Umschalten zwischen Staging- und Prod-Ständen

```bash
make deployment-use-staging   # eigene Plugins auf dev-develop
make deployment-use-prod      # eigene Plugins auf dev-main
```

> **Achtung:** Diese Targets ändern `composer.json` und `composer.lock`. Nach dem Umschalten immer `git diff` prüfen und nichts versehentlich nach `main` committen.

---

## Wo finde ich was?

| Thema | Ort |
|---|---|
| Pipeline-Logs | GitLab → `CI/CD → Pipelines` → Job anklicken |
| Deployment-Ausgabe | Job `stage-deploy` bzw. `deploy-production` (läuft mit `-vvv`) |
| Shopware-Logs auf dem Server | `<deploy_path>/shared/var/log/` |
| Aktives Release | `<deploy_path>/current` (Symlink) |
| Server-Konfiguration | `.deployment/deploy.php` |
| Alle Make-Targets | `make help` |

---

## Häufige Stolpersteine beim Einstieg

| Symptom | Ursache |
|---|---|
| `bin/console: No such file or directory` | Flex-Recipes noch nicht gelaufen → `composer symfony:recipes:install --yes` |
| Composer-Fehler 401/403 | `auth.json` fehlt oder Token abgelaufen |
| Docker-Stack startet nicht | Port 22 belegt → Mapping auf `2222:22` ändern |
| `make ai-*` schlägt fehl | `.ai`-Submodul nicht initialisiert → `git submodule update --init --recursive .ai` |

Ausführlich: [troubleshooting.md](troubleshooting.md).
