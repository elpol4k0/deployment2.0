# 03 – Projekt aus dem Template aufsetzen

> Template klonen und alle Platzhalter ersetzen.
> Vorher: [02 – GitLab-Projekt](02-gitlab-projekt.md) · Danach: [04 – Lokale Umgebung](04-lokale-umgebung.md)

---

## 1. Template klonen

```bash
git clone git@gitlab.agiqon.de:deployment/examples/deployment-2.0.git <projektname>
cd <projektname>
rm -rf .git
git init --initial-branch=develop
git remote add origin <REPO_LINK>
```

Das Entfernen von `.git` löst das Projekt von der Template-Historie. Alternativ kannst du das Template in GitLab als *Template* nutzen und direkt ein neues Repository erzeugen.

> **Hinweis:** Noch nicht pushen. Der erste Push löst eine Pipeline aus, die mangels vorbereitetem Server zwangsläufig scheitert. Der Push erfolgt in [06 – Erstes Deployment](06-erstes-deployment.md).

---

## 2. Dateien umbenennen

| Von | Nach | Anmerkung |
|---|---|---|
| `.gitlab-ci.yml.dist` | `.gitlab-ci.yml` | wird eingecheckt; erst dadurch startet überhaupt eine Pipeline |
| `auth.json.dist` | `auth.json` | gitignored, siehe [02](02-gitlab-projekt.md) |
| `.env.dist` | `.env` | gitignored; wird alternativ von `bin/console system:setup` erzeugt |
| `config/packages/local.yaml.dist` | `config/packages/local.yaml` | optional, für lokale Symfony-Overrides |

> **Nicht umbenennen:** `.php-cs-fixer.dist.php`. Das `.dist` ist hier PHP-CS-Fixer-Konvention und kein Platzhalter.

> **Ebenfalls nicht umbenennen:** die Dateien in `.ci/`. Sie tragen kein `.dist`-Suffix und werden direkt bearbeitet. Nur der Einstiegspunkt `.gitlab-ci.yml.dist` wird umbenannt.

---

## 3. Platzhalter ersetzen

Alle Platzhalter im Überblick. Arbeite die Tabelle von oben nach unten ab.

### `composer.json`

| Zeile | Platzhalter | Ersetzen durch |
|---|---|---|
| 2 | `agiqon/project-name` | `agiqon/<projektname>` |
| 74–77 | `[SHOPWARE_VERSION]` (4×) | z. B. `~6.6.10` – in allen vier `shopware/*`-Paketen identisch |
| 66 | `[LINK_TO_REPOSITORY]` | Pfad zum Plugin-Repo des Kunden, z. B. `kunde/mein-plugin.git` |
| 84 | `agiqon/[PLUGIN_NAME]` | Name des projekteigenen Plugins – **oder Zeile löschen** |
| 86 | `store.shopware.com/[PLUGIN_NAME]` | Name des Store-Plugins – **oder Zeile löschen** |
| 41 | `https://gitlab.agiqon.de/general/.../agiqoncore.git` | **auf SSH umstellen:** `git@gitlab.agiqon.de:general/shopware-6/plugins/agiqoncore.git` |

> **Achtung – agiqoncore-URL:** Globale AGIQON-Plugins werden ausschließlich per Deploy Key über SSH geladen. Der vorbereitete HTTPS-Eintrag in Zeile 41 funktioniert nicht und muss umgestellt werden, sobald das Projekt `agiqon/core` nutzt – das ist der Regelfall. Wird `agiqon/core` **nicht** genutzt, sind Zeile 39–42 und Zeile 83 zu entfernen. Siehe [plugins/globale-plugins.md](plugins/globale-plugins.md).

> **Achtung:** Werden keine eigenen bzw. keine Store-Plugins genutzt, müssen die Zeilen 84/86 **und** der zugehörige `repositories`-Eintrag (Zeile 64–67) entfernt werden. Sonst scheitert `composer install` an einem nicht auflösbaren Paket.

### `.env`

| Zeile | Platzhalter | Ersetzen durch |
|---|---|---|
| 4 | `APP_SECRET=change-me-to-a-random-string-32-chars-min` | wird von `system:setup` erzeugt |
| 5 | `APP_URL=https://[DOMAIN]` | lokale URL, z. B. `http://localhost` |
| 7 | `INSTANCE_ID=change-me-to-a-random-string-32-chars-min` | wird von `system:setup` erzeugt |
| 9 | `DATABASE_URL` | passend zur gewählten lokalen Umgebung |

Am einfachsten lässt du `.env` in Schritt [04](04-lokale-umgebung.md) von `bin/console system:setup` erzeugen – `make deployment-install` macht das automatisch.

### `auth.json`

| Zeile | Platzhalter |
|---|---|
| 4 | `[tokenUserName]` |
| 5 | `[tokenToken]` |
| 9 | `[shopwareBearerToken]` |

Werte aus [02 – GitLab-Projekt](02-gitlab-projekt.md).

### `.ci/` – Pipeline-Definitionen

Die Pipeline ist auf `.ci/` aufgeteilt; `.gitlab-ci.yml` enthält nur `stages:` und die `include:`-Liste. Die Platzhalter liegen deshalb in den Einzeldateien:

| Datei | Platzhalter | Ersetzen durch |
|---|---|---|
| `.ci/build-js-base.yml` | `vendor/[customer]` | Vendor-Verzeichnis des Kunden, z. B. `vendor/kunde` |
| `.ci/deploy-stage.yml` | `[STAGING SERVER IP]` | IP des Staging-Servers |
| `.ci/deploy-prod.yml` | `[PROD SERVER IP]` | IP des Live-Servers |

> **Die Dateien in `.ci/` haben kein `.dist`-Suffix** und werden direkt bearbeitet. Nur `.gitlab-ci.yml.dist` wird umbenannt – das ist die Sicherung, dass vor dem bewussten Umbenennen keine Pipeline startet.

Die `chown`-Zeile in `.ci/build-js-base.yml` lautet:

```yaml
- sudo chown docker:docker bin auth.json vendor/agiqon vendor/store.shopware.com vendor/[customer] -R
```

> **Achtung:** `chown` bricht ab, sobald einer der aufgelisteten Pfade nicht existiert – und mit ihm der ganze `build-js`-Job. **Entferne die Vendor-Pfade, die dein Projekt nicht nutzt**: `vendor/agiqon` ohne globale Plugins, `vendor/store.shopware.com` ohne Store-Plugins.

**SSH-Block in `.ci/composer-base.yml`:** Der mit `### THIS PART ONLY IF GLOBAL PLUGIN REPOS ARE USED ###` markierte Block lädt `COMPOSER_DEPLOY_KEY` in den SSH-Agent und wird für alle globalen AGIQON-Plugins gebraucht. Er **bleibt stehen**, sobald das Projekt globale Plugins nutzt – was auf die meisten Projekte zutrifft, weil bereits `agiqon/core` dazugehört. Entfernen nur, wenn das Projekt gar keine globalen Plugins einbindet.

Die beiden `composer config`-Zeilen darunter bleiben in jedem Fall stehen – sie authentifizieren die projekteigenen Plugin-Repos und den Shopware Store.

**Umgebungen ergänzen:** Soll das Projekt mehr als Staging und Production haben, siehe [01 – Pipeline erweitern](01-architektur.md#4-pipeline-erweitern) und `.ci/README.md`.

### `.deployment/deploy.php`

| Zeile | Platzhalter | Ersetzen durch |
|---|---|---|
| 14 | `[PROJECTNAME]` | Projektname aus der `composer.json` |
| 57, 70 | `[SSH_USER]` | SSH-Benutzer auf dem jeweiligen Server |
| 58 | `[IP_STAGE]` | IP des Staging-Servers |
| 71 | `[IP_LIVE]` | IP des Live-Servers |
| 62, 65, 66 | `[DOMAIN_STAGE]` | Staging-Domain – in `deploy_path`, `app_url` und `cachetool` |
| 75, 78, 79 | `[DOMAIN_LIVE]` | Live-Domain – in `deploy_path`, `app_url` und `cachetool` |

Zusätzlich zu prüfen:

- **`cachetool`-Socket:** Steht im Template auf `/var/run/php8.3-fpm-[DOMAIN].sock`. Prüfe die tatsächlich auf dem Server laufende PHP-Version und passe den Pfad an.
- **`set('bin/php', '/usr/bin/php')`** (Zeile 15): Bei Servern mit mehreren PHP-Versionen auf den konkreten Pfad ändern, z. B. `/usr/bin/php8.4`.
- **`deploy_path`:** Muss dem tatsächlichen Verzeichnis auf dem Server entsprechen, das du in [05](05-server-vorbereiten.md) anlegst.
- **Shopware Apps:** Nutzt das Projekt Shopware *Apps* (nicht Plugins), Zeile 92–93 einkommentieren:
  ```php
  'shopware6:apps:install_update',
  ```

> **Nicht ersetzen:** `{{release_path}}`, `{{bin/php}}`, `{{console}}`, `{{source_directory}}`, `{{previous_release}}` sind Deployer-Laufzeitvariablen, keine Platzhalter.

### Lokale Umgebung: beide Dateien befüllen

Docker und devenv sind keine Projekt-Entscheidung, sondern Geschmackssache des einzelnen Entwicklers. **Befülle beide Konfigurationen**, damit jeder im Team frei wählen kann.

#### `docker-compose.yml`

`[projekt_name]` an **zehn** Stellen ersetzen: Zeilen 11, 15, 24, 40, 51, 68, 89, 105, 114, 116.

Zeile 105 gehört zum auskommentierten Redis-Service – ersetzen lohnt trotzdem, falls Redis später aktiviert wird.

Zeile 11 ist der Compose-Projektname:

```yaml
name: [projekt_name]
```

Er präfixt Volumes und Netzwerke. Dadurch kollidieren mehrere lokal laufende Projekte nicht miteinander, unabhängig davon, wie das Verzeichnis auf der Platte heißt.

Zusätzlich prüfen: `PHP_VERSION` und `NODE_VERSION` (Zeile 35–36).

#### `devenv.nix`

`[PROJECT]` an drei Stellen ersetzen: Zeilen 62, 103, 104.

---

## 4. Schnellkontrolle

Prüfe, dass keine Platzhalter übrig sind:

```bash
grep -rn --exclude-dir=.git --exclude-dir=docs -E '\[(SHOPWARE_VERSION|PLUGIN_NAME|LINK_TO_REPOSITORY|PROJECTNAME|SSH_USER|IP_STAGE|IP_LIVE|DOMAIN_STAGE|DOMAIN_LIVE|DOMAIN|projekt_name|PROJECT|customer|tokenUserName|tokenToken|shopwareBearerToken)\]' .
grep -rn 'agiqon/project-name' composer.json
grep -rn 'STAGING SERVER IP\|PROD SERVER IP' .ci/
```

Alle drei Kommandos sollten ohne Treffer durchlaufen.

---

## 5. Was aus Deployment 1.x entfällt

Wenn du den Ablauf aus der alten Dokumentation im Kopf hast: Diese Schritte gibt es **nicht mehr** und du suchst die Dateien vergeblich.

| Schritt aus 1.x | Status in 2.0 |
|---|---|
| PHP-Version in `.ci/composer.json` anpassen | `.ci/` existiert nicht mehr – Tooling liegt in `vendor-bin/`, dort ist PHP 8.4 fest gesetzt und muss nicht angepasst werden |
| PHP-Version in `.deployment/composer.json` anpassen | Steht fest auf `"platform": { "php": "8.4" }` – nur anpassen, wenn das Projekt bewusst eine andere PHP-Version fährt |
| `inventory.yml` mit Staging-/Production-IPs, `deploy_path`, `app_url`, `cachetool` füllen | Alles inline in `.deployment/deploy.php:56-80` |
| Plugin-Array in `deploy.php` entfernen | Existiert nicht mehr – der `shopware-deployment-helper` übernimmt Plugin-Installation und -Update |
| `chmod 777 bin/*` | Erledigt `make deployment-install` (`chmod 755`) |
| `git update-index --chmod=+x` für 11 `bin/`-Dateien | Diese Dateien werden von Flex-Recipes erzeugt und sind gitignored – nichts zu tun |
| `.env.dist` nach dem Setup löschen | `.env.dist` bleibt als Vorlage im Repository, `.env` ist gitignored |
| `composer.json`: `shopware-packages`-Repository entfernen | Nicht mehr enthalten |

Vollständige Gegenüberstellung: [migration-1x-zu-2x.md](migration-1x-zu-2x.md).

---

## Checkliste

- [ ] Template geklont, `.git` entfernt, neues Remote gesetzt
- [ ] `.gitlab-ci.yml.dist`, `auth.json.dist`, `.env.dist` umbenannt
- [ ] `composer.json`: Projektname, Shopware-Version, Plugin-Einträge angepasst oder entfernt
- [ ] `composer.json`: `agiqoncore`-Repository auf SSH umgestellt (`git@gitlab.agiqon.de:...`)
- [ ] `.ci/build-js-base.yml`: `vendor/[customer]` gesetzt, nicht genutzte Vendor-Pfade entfernt
- [ ] `.ci/deploy-stage.yml` und `.ci/deploy-prod.yml`: Server-IPs eingetragen
- [ ] `.ci/composer-base.yml`: SSH-Block behalten (bzw. nur ohne globale Plugins entfernt)
- [ ] `.deployment/deploy.php`: alle Platzhalter ersetzt, cachetool-Socket und PHP-Pfad geprüft
- [ ] Lokale Umgebung: `docker-compose.yml` **und** `devenv.nix` angepasst
- [ ] Platzhalter-Kontrolle ohne Treffer

---

→ [04 – Lokale Umgebung](04-lokale-umgebung.md)
