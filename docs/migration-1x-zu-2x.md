# Migration von Deployment 1.x auf 2.0

> Bestehendes Projekt auf das neue Template umstellen.

**Gewählter Weg: neu aufsetzen und `custom/` übernehmen.** Das Template hat sich strukturell so stark geändert, dass ein In-place-Umbau mehr Fehlerquellen erzeugt als ein sauberer Neuaufsatz. Die Git-Historie des alten Repos bleibt im archivierten Repository erhalten.

---

## 1. Was sich geändert hat

| Deployment 1.x | Deployment 2.0 |
|---|---|
| `.ci/` mit eigener `composer.json` und `package-lock.json` (Test-Tools) | `vendor-bin/{phpstan,cs-fixer,rector}` via `bamarni/composer-bin-plugin` – **`.ci/` gibt es in 2.0 wieder, aber mit anderem Inhalt**, siehe Hinweis unten |
| `.gitlab-ci.yml` als eine Datei mit 259 Zeilen | `.gitlab-ci.yml` nur noch `stages:` + `include:`, Definitionen aufgeteilt in `.ci/` |
| `.deployment/inventory.yml` | Hosts inline in `.deployment/deploy.php:56-80` |
| `bin/build-js.sh`, `bin/console`, `bin/ci`, `bin/watch-*.sh` im Repo | von Symfony-Flex-Recipes erzeugt, gitignored |
| `chmod 777 bin/*` und `git update-index --chmod=+x` für 11 Dateien | `make deployment-install` erledigt die Rechte |
| `system:setup` und `system:install` von Hand | im selben Make-Target enthalten |
| Einzelne Deployer-Tasks für Migration, Theme-Compile, Plugin-Update | `vendor/bin/shopware-deployment-helper run` |
| Nur Docker | Docker **und** devenv/Nix |
| ECS für Code-Style | PHP-CS-Fixer, zusätzlich Rector und ludtwig |
| PHP 8.1/8.3 | PHP 8.4 |
| Plugin-Branches manuell per Composer-Script in der `.gitlab-ci.yml` | `.local/stage-composer.sh` / `prod-composer.sh` mit `extra.stage-overrides` / `prod-overrides` |
| `sshOptions: StrictHostKeyChecking: no` in der `inventory.yml` | `ssh-keyscan` in der Pipeline |

**Was ersatzlos entfällt und beim Umzug nicht mitgenommen wird:**

- der **Inhalt** des alten `.ci/` (`composer.json`, `composer.lock`, `package-lock.json`)
- `.deployment/inventory.yml`
- `.deployment/deploy-helper.php`
- alle eingecheckten `bin/*.sh`-Skripte
- die alte `.gitlab-ci.yml`
- `auth.json` im alten Format (Struktur ist gleich geblieben, die Werte übernimmst du)

> **Achtung – gleicher Ordnername, anderer Zweck:** In 1.x enthielt `.ci/` die Test-Tools. Diese Rolle hat in 2.0 `vendor-bin/` übernommen. Der Ordner `.ci/` **existiert in 2.0 wieder** – darin liegen jetzt die aufgeteilten Pipeline-Definitionen (`composer-base.yml`, `build-js-prod.yml`, …). Kopiere beim Migrieren also **nichts** aus dem alten `.ci/` in den neuen: Der alte Inhalt wird verworfen, der neue kommt aus dem Template. Siehe [01 – Pipeline erweitern](01-architektur.md#4-pipeline-erweitern).

---

## 2. Vorbereitung

- [ ] Wartungsfenster mit dem Kunden abstimmen – der Cutover braucht eine kurze Downtime
- [ ] Vollständiges Backup: Datenbank-Dump **und** `shared/`-Verzeichnis des Live-Systems
- [ ] Liste aller genutzten Plugins erstellen (`bin/console plugin:list` auf dem Live-System)
- [ ] Prüfen, welche Plugins mit PHP 8.4 und der Ziel-Shopware-Version kompatibel sind
- [ ] Inhalt der aktuellen `.env` sichern – insbesondere `APP_SECRET` und `INSTANCE_ID`

> **Achtung:** `APP_SECRET` und `INSTANCE_ID` **müssen** aus dem Altsystem übernommen werden. Werden sie neu erzeugt, verlieren alle Sessions ihre Gültigkeit und bestehende Integrationen (z. B. API-Zugänge, die daran hängen) brechen.

---

## 3. Neues Projekt aufsetzen

Die Schritte [02](02-gitlab-projekt.md) bis [04](04-lokale-umgebung.md) durcharbeiten, mit diesen Abweichungen:

### Repository

Neues Repository anlegen, z. B. `project` in derselben Kunden-Gruppe (das alte vorher umbenennen, etwa nach `project-legacy`).

### CI/CD-Variablen

Bestehende Gruppenvariablen können weiterverwendet werden. Prüfe aber:

- `SSH_PRIVATE_KEY` – kann bleiben, wenn der Public Key auf dem Server noch liegt
- `DEPLOY_TOKEN` / `DEPLOY_TOKEN_USER` – Scopes prüfen: `read_repository` **und** `read_package_registry`
- `APP_SECRET` – **den alten Wert eintragen**, nicht neu erzeugen
- `COMPOSER_DEPLOY_KEY` – nur bei SSH-basierten Plugin-Repos

### `composer.json`

- Shopware-Version aus dem Altprojekt übernehmen (oder bewusst anheben)
- Plugin-Requires aus der alten `composer.json` übertragen
- Store-Plugins: Paketnamen und Versionen übernehmen
- Eigene Plugins auf `dev-main` umstellen, damit das Branch-Handling greift

### `.env`

Nach `make deployment-install` die erzeugte `.env` anpassen und `APP_SECRET` sowie `INSTANCE_ID` durch die **alten Werte** ersetzen.

---

## 4. Plugins übernehmen

| Plugin-Art im Altprojekt | Vorgehen |
|---|---|
| Eigenes Plugin in eigenem GitLab-Repo | Repository-Eintrag und Require in die neue `composer.json` übernehmen. Prüfen, dass das Plugin die Branches `main` und `develop` hat. |
| Eigenes Plugin unter `custom/plugins/` eingecheckt | In ein eigenes Repository überführen (siehe [plugins/eigene-plugins.md](plugins/eigene-plugins.md)) – `/custom/` ist in 2.0 gitignored. |
| Globales AGIQON-Plugin | Repository-Eintrag und Require übernehmen, Version prüfen. |
| Store-Plugin | Require übernehmen, Bearer-Token prüfen. |

Bei jedem Plugin prüfen:

- Ist es mit PHP 8.4 kompatibel?
- Läuft es mit der Ziel-Shopware-Version?
- Enthält die `composer.json` des Plugins `"type": "shopware-platform-plugin"` und die `extra.shopware-plugin-class`?

Anschließend lokal installieren und `make check-ci` laufen lassen – PHPStan Level 8 und die Rector-Sets sind strenger als in 1.x. Erwarte hier Nacharbeit.

---

## 5. Datenbank übernehmen

```bash
# auf dem Altsystem
mysqldump -u <user> -p <datenbank> > migration.sql

# lokal einspielen (nach make deployment-install)
mysql -u root -proot shopware < migration.sql
bin/console cache:clear
```

Danach lokal testen: Shop, Admin, Checkout, die kundenspezifischen Funktionen.

---

## 6. Server vorbereiten

**Neues Verzeichnis anlegen, nicht das alte überschreiben.** So bleibt das Altsystem bis zum Cutover lauffähig und ist der Fallback.

Beispiel:

```
/var/www/share/<domain>/          # alt, bleibt bestehen
/var/www/share/<domain>-v2/       # neu
```

Die Schritte aus [05 – Server vorbereiten](05-server-vorbereiten.md) im neuen Verzeichnis durchführen. In `.deployment/deploy.php` den `deploy_path` auf das neue Verzeichnis setzen.

Aus dem alten `shared/` übernehmen:

- `public/media/`, `public/sitemap/`, `public/thumbnail/` (per rsync)
- `files/`
- `config/jwt/` – **oder** neu erzeugen lassen; bei Übernahme bleiben bestehende API-Tokens gültig
- `.env` als Vorlage, aber mit angepasstem `DATABASE_URL`

---

## 7. Cutover

1. Wartungsmodus auf dem Altsystem aktivieren
2. Finalen Datenbank-Dump ziehen und in die Zieldatenbank einspielen
3. Medien final per rsync abgleichen
4. Pipeline auf `main` laufen lassen → deployt ins neue Verzeichnis
5. DocumentRoot umhängen:
   ```bash
   rm -rf htdocs
   ln -s /var/www/share/<domain>-v2/current/public/ htdocs
   ```
6. Supervisor-/Cron-Konfiguration auf die neuen Pfade anpassen und neu starten
7. Smoke-Test: Startseite, Kategorie, Produktdetail, Warenkorb, Checkout, Admin-Login
8. Wartungsmodus aus

**Rollback-Plan:** DocumentRoot zurück auf das alte Verzeichnis hängen und den Datenbank-Dump von Schritt 2 zurückspielen. Solange das alte Verzeichnis unangetastet bleibt, ist das in wenigen Minuten erledigt.

---

## 8. Nacharbeit

- [ ] Altes Repository archivieren (`Settings → General → Advanced → Archive project`)
- [ ] Alte Supervisor-Programme bzw. Cronjobs entfernen
- [ ] Altes Deploy-Verzeichnis nach einer Karenzzeit von 1–2 Wochen löschen
- [ ] Monitoring/Uptime-Checks auf die neuen Pfade prüfen
- [ ] Team informieren: neuer Clone-Pfad, `make`-Targets statt `bin/*.sh`

---

## Aufwandsschätzung

Die Migration ist kein Ein-Stunden-Job. Realistisch einzuplanen sind:

| Block | Aufwand |
|---|---|
| Neues Projekt aufsetzen (02–04) | 2–4 h |
| Plugins übernehmen und PHP-8.4-kompatibel machen | stark plugin-abhängig, oft der größte Block |
| Code-Quality-Nacharbeit (PHPStan Level 8) | abhängig vom Altcode |
| Server vorbereiten | 1–2 h pro Umgebung |
| Cutover inkl. Test | 2–3 h, im Wartungsfenster |

> **Annahme:** Diese Schätzung geht von einem Projekt mit wenigen eigenen Plugins aus. Bei umfangreicher Individualentwicklung dominiert die Plugin-Anpassung den Gesamtaufwand. Vor der Terminzusage eine Bestandsaufnahme der Plugins machen.
