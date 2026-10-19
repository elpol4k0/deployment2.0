# 05 – Server vorbereiten

> Zielserver für Staging und Production einrichten, bevor die erste Pipeline deployt.
> Vorher: [04 – Lokale Umgebung](04-lokale-umgebung.md) · Danach: [06 – Erstes Deployment](06-erstes-deployment.md)

Die Schritte gelten für Staging **und** Production. Führe sie für jede Umgebung einmal durch.

---

## 1. Public Key hinterlegen

Der Public Key zum `SSH_PRIVATE_KEY` aus [02 – GitLab-Projekt](02-gitlab-projekt.md) muss auf dem Server hinterlegt werden (`~/.ssh/authorized_keys` bzw. über das Hoster-Interface).

Ohne diesen Key kann die Pipeline sich nicht verbinden und der Deploy-Job bricht mit `Permission denied (publickey)` ab.

---

## 2. Verzeichnis anlegen

Lege das Verzeichnis an, das in `.deployment/deploy.php` als `deploy_path` eingetragen ist – im Template:

```
/var/www/share/<domain>
```

Deployer legt darin selbst `releases/`, `current` und `.dep/` an. Was du **von Hand** anlegen musst, ist `shared/`.

---

## 3. `shared/` befüllen

Alles unter `shared/` überlebt jedes Deployment und wird in jedes Release hineinverlinkt. Definiert in `.deployment/deploy.php:17-32`.

```bash
mkdir -p /var/www/share/<domain>/shared/public
```

### `shared/.env`

Kopiere die lokale `.env` auf den Server nach `shared/.env` und passe an:

```dotenv
APP_ENV=prod
APP_SECRET=<Wert aus der lokalen .env – identisch zur CI-Variable>
APP_URL=https://<domain>
APP_TIMEZONE=Europe/Berlin
INSTANCE_ID=<Wert aus der lokalen .env>

DATABASE_URL=mysql://<user>:<passwort>@<db-host>:3306/<datenbank>

MAILER_DSN=smtp://<user>:<pass>@<smtp-host>:587

COMPOSER_HOME=/var/www/share/<domain>/shared/.composer

BLUE_GREEN_DEPLOYMENT=0
```

> **Achtung:** `APP_SECRET` und `INSTANCE_ID` müssen zwischen den Umgebungen **stabil** bleiben. Werden sie nachträglich geändert, invalidieren Sessions und bestehende Integrationen.

> **Achtung:** `APP_ENV=prod` – nicht `dev`. Andernfalls läuft der Shop mit Debug-Ausgaben und deutlich langsamer.

### Weitere shared-Dateien

Deployer erwartet folgende Dateien und Verzeichnisse. Was nicht existiert, legt Deployer beim ersten Lauf leer an – `.env` und `install.lock` musst du jedoch selbst befüllen:

| Pfad | Anmerkung |
|---|---|
| `shared/.env` | siehe oben |
| `shared/install.lock` | leere Datei genügt: `touch shared/install.lock` |
| `shared/public/robots.txt` | siehe Schritt 5 |
| `shared/public/.htaccess` | optional, hosterabhängig |
| `shared/public/.user.ini` | optional, hosterabhängig |
| `shared/config/jwt/` | JWT-Keys |
| `shared/files/`, `shared/var/log/` | |
| `shared/public/media/`, `sitemap/`, `thumbnail/` | Medien-Verzeichnisse |

---

## 4. Datenbank vorbereiten

1. Dump der lokalen Datenbank erzeugen:
   ```bash
   mysqldump -u root -p shopware > shopware.sql
   ```
2. Datenbank auf dem Zielserver anlegen und den Dump einspielen.
3. Die Zugangsdaten in `shared/.env` unter `DATABASE_URL` eintragen.

---

## 5. `robots.txt` anlegen

Datei `shared/public/robots.txt` mit folgendem Inhalt anlegen und `[WEBSEITENURL]` ersetzen:

```
User-agent: *
Allow: /
Disallow: /admin
Disallow: /api
Disallow: /account
Disallow: /account/login
Disallow: /checkout
Disallow: /checkout/register
Disallow: /compare
Disallow: /wishlist
Disallow: /register
Disallow: /newsletter
Disallow: */widgets/
Disallow: */navigation/
Disallow: */bundles/
Sitemap: [WEBSEITENURL]/sitemap.xml
```

> **Hinweis für Staging:** Auf Staging-Systemen sollte die `robots.txt` alles sperren (`Disallow: /`), damit der Testshop nicht indexiert wird.

---

## 6. DocumentRoot auf `current/public` umstellen

Der Webserver muss auf den Symlink `current/public` zeigen, nicht auf das Verzeichnis selbst.

**Maxcluster:**

```bash
rm -rf htdocs
ln -s current/public/ htdocs
```

**Andere Hoster:** DocumentRoot der vHost-Konfiguration auf `/var/www/share/<domain>/current/public` setzen.

> **Kontrolle:** Zeigt der Browser die Seite „Shopware Root Directory – You should not be able to see this page", steht der DocumentRoot noch auf dem Projekt-Root statt auf `public/`.

---

## 7. Scheduled Tasks und Message Queue einrichten

Der Shopware-Admin-Worker ist im Template aktiviert. Zusätzlich müssen Message Consumer und Scheduled Tasks **serverseitig** laufen.

### Maxcluster: Supervisor

`Webserver → Supervisor` im Admin-Interface.

```ini
[program:messenger-consume-async]
command=php {ROOT}/bin/console messenger:consume --time-limit=295 --memory-limit=512M async
numprocs=3
startsecs=0
autostart=true
autorestart=true
process_name=%(program_name)s_%(process_num)02d

[program:scheduled-task-run]
command=php {ROOT}/bin/console scheduled-task:run --time-limit=295 --memory-limit=512M
numprocs=1
startsecs=0
autostart=true
autorestart=true
process_name=%(program_name)s_%(process_num)02d
```

`{ROOT}` ist der absolute Pfad zu `current`, also z. B. `/var/www/share/<domain>/current`.

> **Hinweis:** Der Deployer-Task `shopware6:messenger:stop` beendet die Worker des **vorherigen** Releases nach jedem Deployment (`deploy-shopware6.php:44-48`). Supervisor startet sie anschließend automatisch im neuen Release neu.

### Andere Hoster: Cronjob

Beide Kommandos alle 5 Minuten anstoßen:

```bash
{ROOT}/bin/console messenger:consume --time-limit=295 --memory-limit=512M async
{ROOT}/bin/console scheduled-task:run --time-limit=295 --memory-limit=512M
```

---

## 8. Passwortschutz aktivieren

Staging-Systeme – und Live-Systeme bis zum Go-Live – bekommen einen HTTP-Passwortschutz.

> **Achtung:** Bei allen Hostern außer Maxcluster muss `/api` vom Passwortschutz **ausgenommen** werden. Sonst schlagen API-Zugriffe und der Health-Check des Deployments fehl.

---

## 9. PHP-FPM-Socket prüfen

`.deployment/deploy.php` räumt nach jedem Deployment den OPcache über den FPM-Socket auf:

```php
->set('cachetool', '/var/run/php8.3-fpm-<domain>.sock')
```

Prüfe auf dem Server, wie der Socket tatsächlich heißt:

```bash
ls /var/run/php*-fpm*.sock
```

und korrigiere den Pfad in `deploy.php`. Stimmt er nicht, bricht der Task `cachetool:clear:opcache` am Ende des Deployments ab.

---

## Checkliste (pro Umgebung)

- [ ] Public Key des Deploy-Schlüssels hinterlegt, `ssh` vom Runner aus möglich
- [ ] `deploy_path`-Verzeichnis angelegt, Pfad identisch zu `deploy.php`
- [ ] `shared/.env` angelegt, `APP_ENV=prod`, `DATABASE_URL`, `APP_URL`, `COMPOSER_HOME` gesetzt
- [ ] `shared/install.lock` angelegt
- [ ] Datenbank angelegt und Dump eingespielt
- [ ] `shared/public/robots.txt` angelegt
- [ ] DocumentRoot auf `current/public` gesetzt
- [ ] Supervisor bzw. Cronjobs für `messenger:consume` und `scheduled-task:run` eingerichtet
- [ ] Passwortschutz aktiv, `/api` ausgenommen
- [ ] `cachetool`-Socket-Pfad in `deploy.php` gegen den Server geprüft

---

→ [06 – Erstes Deployment](06-erstes-deployment.md)
