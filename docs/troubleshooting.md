# Troubleshooting

> Nach Symptom sortiert. Jeder Eintrag nennt Ursache und Lösung.

---

## Pipeline

### Auf Feature-Branches läuft gar keine Pipeline

**Symptom:** Push auf `feature/xyz` erzeugt keine Pipeline, oder GitLab meldet `job needs 'stage-composer' but it was not found`.

> **Altlast:** Im aktuellen Template behoben. Betrifft nur Projekte, die vor dem `.ci/`-Umbau aufgesetzt wurden.

**Ursache:** Der Job `test-build-js` läuft laut `rules` nur auf Branches, die *nicht* `develop` oder `main` sind, verlangt aber `needs: [ stage-composer, stage-codestyle, stage-phpstan ]`. Diese drei Jobs existieren nur auf `develop`. GitLab lehnt die Pipeline-Erstellung deshalb ab.

**Lösung:** `needs` optional machen (in `.ci/build-js-feature.yml`, in älteren Projekten direkt in `.gitlab-ci.yml`):

```yaml
needs:
  - job: stage-composer
    optional: true
  - job: stage-codestyle
    optional: true
  - job: stage-phpstan
    optional: true
```

---

### `chown: cannot access 'vendor/...'`

**Symptom:** Der `build-js`-Job bricht im `before_script` ab.

**Ursache:** Die `chown`-Zeile in `.ci/build-js-base.yml` listet einen Pfad auf, den es im Projekt nicht gibt. `chown` bricht bei nicht existierenden Pfaden ab und reißt den ganzen Job mit.

Typische Fälle:

- `vendor/store.shopware.com` ohne Store-Plugins im Projekt
- `vendor/agiqon` ohne globale AGIQON-Plugins
- `vendor/[customer]` – Platzhalter nicht ersetzt
- `vendor/store.shopware.de` – Tippfehler in Projekten, die vor der Korrektur aufgesetzt wurden

**Lösung:** Nur die tatsächlich vorhandenen Vendor-Pfade auflisten:

```yaml
- sudo chown docker:docker bin auth.json vendor/agiqon vendor/store.shopware.com -R
```

---

### Composer scheitert mit 401 oder 403 gegen `gitlab.agiqon.de`

**Zuerst prüfen: Um welches Repo geht es?**

Handelt es sich um ein **globales AGIQON-Plugin** (z. B. `agiqon/core`), ist 401/403 praktisch immer ein Symptom dafür, dass die Repository-URL fälschlich auf `https://` steht. Globale Plugins sind ausschließlich per Deploy Key über SSH erreichbar – kein Deploy-Token der Welt hilft hier.

**Lösung:** URL in `composer.json` umstellen:

```json
{ "type": "git", "url": "git@gitlab.agiqon.de:general/shopware-6/plugins/<plugin>.git" }
```

Das betrifft insbesondere den vorbereiteten `agiqoncore`-Eintrag aus dem Template (`composer.json:41`). Siehe [plugins/globale-plugins.md](plugins/globale-plugins.md).

**Bei einem projekteigenen Plugin-Repo** (HTTPS ist dort korrekt):

| Prüfen | Wie |
|---|---|
| Ist `DEPLOY_TOKEN` gesetzt und nicht abgelaufen? | `Settings → CI/CD → Variables` und `Settings → Repository → Deploy tokens` |
| Hat der Token beide Scopes? | `read_repository` **und** `read_package_registry` |
| Gilt der Token für das Ziel-Repo? | Deploy-Tokens wirken nur im Repository bzw. in der Gruppe, in der sie erstellt wurden |
| Lokal: existiert `auth.json`? | `cat auth.json` – die Datei ist gitignored und muss pro Arbeitsplatz angelegt werden |

Liegt das Repo außerhalb der Kunden-Gruppe, gilt dasselbe wie für globale Plugins: auf SSH mit Deploy Key umstellen.

---

### Composer kann ein globales Plugin nicht klonen (`Permission denied (publickey)`)

**Ursache:** Das Repository ist per SSH-URL eingebunden, aber der Deploy Key ist in genau diesem Plugin-Repo nicht aktiviert. Andere Plugins funktionieren – der Fehler wirkt deshalb wie ein Problem des einzelnen Plugins.

**Lösung:** `<PLUGIN-REPO> → Settings → Repository → Deploy keys` → den Key aktivieren. Danach erscheint er unter *Enabled deploy keys*.

Zweite mögliche Ursache: Der Deploy Key ist abgelaufen (Standard-Laufzeit 1 Jahr). Dann schlagen alle betroffenen Projekte gleichzeitig fehl.

---

### `Could not find package store.shopware.com/...`

**Ursache:** Bearer-Token fehlt, ist falsch, oder die Lizenz ist im Shopware Account nicht der Domain zugeordnet.

**Lösung:**

- Lokal: `auth.json` → `bearer.packages.shopware.com`
- CI: Variable `SW_COMPOSER_TOKEN` – prüfen, ob dort noch der Platzhalter aus dem Aufsetzen steht
- Im Shopware Account: Lizenzzuordnung prüfen

---

### PHPStan- oder PHPUnit-Fehler blockieren das Deployment nicht

**Kein Fehler, sondern Absicht im Template:** Alle Jobs der Stages `test-php` und `test-js` haben `allow_failure: true`. Nachfolgende Jobs behandeln sie als erfolgreich.

**Wenn du ein hartes Gate willst:** `allow_failure: true` bei den betreffenden Jobs entfernen. Bedenke, dass danach jeder CS-Verstoß das Deployment stoppt.

---

### Deploy-Job wird übersprungen

**Ursache:** `.ci/deploy-stage.yml` und `.ci/deploy-prod.yml` verlangen `$CI_SERVER_HOST == "gitlab.agiqon.de"`. Auf gespiegelten oder anderen GitLab-Instanzen läuft der Job bewusst nicht.

---

## Deployment

### `Permission denied (publickey)` beim Deploy-Job

**Ursache:** Der Public Key zum `SSH_PRIVATE_KEY` liegt nicht in `~/.ssh/authorized_keys` des `[SSH_USER]` auf dem Zielserver.

**Prüfen:**

```bash
ssh -i <privatekey> <ssh_user>@<server-ip>
```

---

### Deployment bricht bei `deploy:shared` ab

**Ursache:** `shared/.env` fehlt oder ist leer. Deployer kann die Datei nicht verlinken.

**Lösung:** [05 – Server vorbereiten](05-server-vorbereiten.md), Abschnitt `shared/` befüllen. Benötigt werden mindestens `shared/.env` und `shared/install.lock`.

---

### Deployment bricht bei `sw:health_checks` ab

Der Task führt `bin/console system:check --context=pre_rollout` aus. Typische Ursachen:

| Meldung | Ursache |
|---|---|
| Datenbankverbindung fehlgeschlagen | `DATABASE_URL` in `shared/.env` falsch |
| Fehlende PHP-Extension | Server-PHP passt nicht zu den Anforderungen von Shopware/Plugins |
| Schreibrechte fehlen | `writable_dirs` konnten nicht gesetzt werden – Benutzerrechte prüfen |

Log ansehen: Der Deploy-Job läuft mit `-vvv`, die vollständige Ausgabe steht im Job-Log.

---

### Deployment bricht bei `cachetool:clear:opcache` ab

**Ursache:** Der FPM-Socket-Pfad in `.deployment/deploy.php` stimmt nicht. Im Template steht `/var/run/php8.3-fpm-<domain>.sock`, während das übrige Template auf PHP 8.4 ausgelegt ist.

**Lösung:** Auf dem Server prüfen und den Pfad anpassen:

```bash
ls /var/run/php*-fpm*.sock
```

---

### Shop zeigt „Shopware Root Directory – You should not be able to see this page"

**Ursache:** Der DocumentRoot zeigt auf das Projektverzeichnis statt auf `current/public`.

**Lösung:** Siehe [05 – Server vorbereiten](05-server-vorbereiten.md), Abschnitt DocumentRoot.

---

### Änderungen im Plugin-Repo kommen nicht auf dem Server an

**Kein Fehler:** Es gibt im Template keinen `trigger:`-Job. Ein Push im Plugin-Repo löst keine Projekt-Pipeline aus.

**Lösung:** Im Projekt-Repo eine Pipeline auslösen (Commit oder `CI/CD → Pipelines → Run pipeline`). Die Skripte unter `.local/` ziehen dann den aktuellen Branch-Head.

---

### Auf Production läuft der Entwicklungsstand eines Plugins

**Ursache:** `make deployment-use-staging` wurde lokal ausgeführt und die dadurch geänderte `composer.json` (mit `dev-develop`) wurde nach `main` committet.

**Lösung:**

```bash
make deployment-use-prod
git diff composer.json composer.lock
git commit -am "fix: restore production plugin branches"
```

**Vorbeugen:** Nach jedem `make deployment-use-*` ein `git diff` prüfen.

---

## Lokale Umgebung

### `bin/console: No such file or directory`

**Ursache:** `bin/console` wird von Symfony-Flex-Recipes erzeugt und ist gitignored. Nach einem frischen Clone existiert die Datei noch nicht.

**Lösung:**

```bash
composer install --no-scripts
composer symfony:recipes:install --yes --no-interaction
chmod 755 bin/*
```

Oder direkt `make deployment-install`.

---

### `make deployment-install` bricht ab

| Abbruchstelle | Ursache |
|---|---|
| beim ersten `composer install` | `auth.json` fehlt oder Tokens falsch |
| beim Auflösen der Pakete | Platzhalter `[SHOPWARE_VERSION]`, `[PLUGIN_NAME]` oder `[LINK_TO_REPOSITORY]` nicht ersetzt |
| `Your requirements could not be resolved` | lokale PHP-Version ist nicht 8.4 |
| bei `system:install` | Datenbank nicht erreichbar – `DATABASE_URL` und laufender DB-Container prüfen |
| bei `make build-js` | `shopware-cli` nicht installiert |

---

### Docker-Stack startet nicht, Port bereits belegt

**Ursache:** `docker-compose.yml:19` mappt Port `22:22`. Auf jedem System mit laufendem SSH-Daemon kollidiert das.

**Lösung:** Mapping ändern:

```yaml
- "2222:22"
```

---

### `phpstan.neon` taucht nicht in `git status` auf

**Ursache:** `.gitignore:103` ignoriert `phpstan.neon` (im Block `frosh/code-quality-meta`), obwohl die Datei getrackt ist. Beim Klonen funktioniert alles, aber lokale Änderungen werden nicht angezeigt.

**Lösung:** Änderungen erzwungen hinzufügen –

```bash
git add -f phpstan.neon
```

– oder den `.gitignore`-Eintrag projektspezifisch entfernen.

---

### `make ai-init` / `make ai-sync` schlägt fehl

**Ursache:** Das `.ai`-Submodul ist nicht initialisiert.

**Lösung:**

```bash
git submodule update --init --recursive .ai
```

---

### `composer hook:pre-commit` findet die Datei nicht

**Ursache:** Die Composer-Scripts `hook:pre-commit` und `hook:pre-push` verweisen auf `bin/pre-commit` und `bin/pre-push`. Diese Dateien existieren im Template nicht.

**Lösung:** Die Scripts sind derzeit funktionslos. Git-Hooks bis auf Weiteres selbst anlegen oder `make check-ci` manuell vor dem Push ausführen.

---

### Lokal andere Node-Version als in der CI

**Ursache:** Die CI nutzt das Image `agiqon/pipeline:PHP_8.4-NODE_20`, `docker-compose.yml` und `devenv.nix` setzen dagegen Node 24. `package.json` verlangt lediglich `>=20`.

**Auswirkung:** Build-Ergebnisse können zwischen lokal und CI abweichen.

**Lösung:** Im Zweifel den Build so prüfen, wie ihn die CI ausführt (`make build-js` nutzt dieselbe `shopware-cli`-Kette). Die grundsätzliche Auflösung ist in [TEMPLATE-ISSUES.md](TEMPLATE-ISSUES.md) vermerkt.

---

## Wenn nichts davon passt

1. Job-Log in GitLab vollständig lesen – der Deploy-Job läuft mit `-vvv`
2. Shopware-Log auf dem Server: `<deploy_path>/shared/var/log/`
3. Aktives Release prüfen: `ls -la <deploy_path>/current`
4. Lokal reproduzieren: `make check-ci`, `make build-js`
5. Gegen das Template abgleichen: Was wurde in `.gitlab-ci.yml` oder `deploy.php` projektspezifisch geändert?
