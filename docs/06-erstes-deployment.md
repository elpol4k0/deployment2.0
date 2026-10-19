# 06 – Erstes Deployment

> Projekt nach GitLab pushen, Pipeline laufen lassen, Shop scharf schalten.
> Vorher: [05 – Server vorbereiten](05-server-vorbereiten.md)

---

## 1. Projekt pushen

```bash
git add .
git commit -m "Initial commit"
git push -u origin develop
```

Der Push löst sofort eine Pipeline aus. Ist der Server noch nicht fertig vorbereitet, **halte sie an** (`CI/CD → Pipelines → Cancel`) und starte sie erst, wenn [05](05-server-vorbereiten.md) abgeschlossen ist.

Anschließend `main` anlegen:

```bash
git checkout -b main
git push -u origin main
git checkout develop
```

> **Kontrolle vor dem Push:** `composer.lock` muss eingecheckt sein. Ohne Lock-File löst Composer in jeder Pipeline neu auf, und die Artefakt-Liste (`.ci/composer-base.yml`) läuft ins Leere.

---

## 2. Pipeline durchlaufen lassen

Die Pipeline auf `develop` deployt nach Staging, die auf `main` nach Production.

| Job | Datei | Was er tut | Typische Fehlerquelle |
|---|---|---|---|
| `stage-composer` | `.ci/composer-stage.yml` | `.local/stage-composer.sh`, `composer install`, `composer bin all install`, Flex-Recipes | 401/403 gegen `gitlab.agiqon.de` → Deploy-Token bzw. HTTPS-URL bei einem globalen Plugin; nicht auflösbares Paket → Platzhalter in `composer.json` |
| `stage-codestyle` | `.ci/test-php-stage.yml` | PHP-CS-Fixer Dry-Run | nur Hinweis, `allow_failure: true` |
| `stage-phpstan` | `.ci/test-php-stage.yml` | PHPStan Level 8 | nur Hinweis, `allow_failure: true` |
| `stage-phpunit` | `.ci/test-php-stage.yml` | PHPUnit | nur Hinweis, `allow_failure: true` |
| `stage-build-js` | `.ci/build-js-stage.yml` | `chown` der Vendor-Ordner, `bin/ci bundle:dump`, `shopware-cli project admin-build` + `storefront-build` | `chown: cannot access 'vendor/...'` → nicht genutzter Vendor-Pfad in `.ci/build-js-base.yml`, siehe [03](03-projekt-aufsetzen.md) |
| `stage-eslint` / `stage-ludtwig` | `.ci/test-js-stage.yml` | Linting über `custom/` | nur Hinweis, `allow_failure: true` |
| `stage-deploy` | `.ci/deploy-stage.yml` | Deployer auf den Server | `Permission denied (publickey)` → Public Key fehlt; `shared/.env` fehlt; falscher `deploy_path` |

Auf `main` läuft dieselbe Kette mit den `prod-*`-Jobs aus den `-prod.yml`-Dateien.

> **Beachte:** Die Jobs der Stages `test-php` und `test-js` haben alle `allow_failure: true`. Sie verhindern das Deployment **nicht**. Sieh dir ihre Ergebnisse trotzdem an – sie sind das einzige Qualitäts-Signal der Pipeline.

Der Deploy-Job läuft nur, wenn `$CI_SERVER_HOST == "gitlab.agiqon.de"` (`.ci/deploy-stage.yml` und `.ci/deploy-prod.yml`). Auf Spiegel-Instanzen wird nichts deployt.

---

## 3. Deployment kontrollieren

Nach erfolgreichem Lauf auf dem Server:

```bash
ls -la /var/www/share/<domain>/
# current -> releases/1
ls /var/www/share/<domain>/releases/
```

Der Shop sollte unter der konfigurierten `app_url` erreichbar sein.

---

## 4. Admin-User anpassen

Die Grundinstallation legt den Benutzer `admin` mit dem Passwort `shopware` an. Das **muss** geändert werden:

- Passwort ändern (Pflicht)
- Vor- und Nachname anpassen (empfohlen)

---

## 5. Abschlusskontrolle

- [ ] Shop über die Live-/Staging-URL erreichbar
- [ ] Admin unter `/admin` erreichbar, Passwort geändert
- [ ] Passwortschutz aktiv, `/api` erreichbar
- [ ] Wartungsmodus aus (der Deployer schaltet ihn am Ende selbst ab – prüfen)
- [ ] Mails werden versendet (`MAILER_DSN` in `shared/.env`)
- [ ] Message Queue arbeitet: `bin/console messenger:stats` bzw. Supervisor-Status
- [ ] Scheduled Tasks laufen: Admin → Einstellungen → System → Aufgaben

---

## Rollback

Deployer hält die letzten fünf Releases vor (`keep_releases: 5`). Ein Rollback ist ein Umhängen des Symlinks:

```bash
cd /var/www/share/<domain>
ls releases/                      # verfügbare Releases
ln -sfn releases/<vorheriges> current
```

Anschließend OPcache leeren bzw. PHP-FPM neu laden.

> **Achtung:** Ein Rollback der Dateien rollt **keine Datenbank-Migrationen zurück**. Hat der `shopware-deployment-helper` Migrationen ausgeführt, ist das alte Release unter Umständen nicht mehr lauffähig. Bei Schema-Änderungen gehört ein Datenbank-Dump vor das Deployment.

Alternativ lässt sich Deployer auch direkt nutzen:

```bash
cd .deployment
php vendor/bin/dep rollback production
```

---

## Der weitere Ablauf im Alltag

```
Feature-Branch → Merge Request → develop → Staging
                                   ↓
                     Merge Request develop → main → Production
```

Wie du im laufenden Betrieb arbeitest: [onboarding.md](onboarding.md).
Wie du Plugins hinzufügst: [plugins/README.md](plugins/README.md).
