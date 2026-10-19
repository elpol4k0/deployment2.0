# 01 – Architektur: Wie Deployment 2.0 funktioniert

> Dieses Dokument erklärt das *Warum* hinter dem Template. Lies es einmal, bevor du das erste Projekt aufsetzt – die Schritt-für-Schritt-Anleitungen ab [02](02-gitlab-projekt.md) setzen die hier eingeführten Begriffe voraus.

---

## 1. Template vs. Projekt

Das Repository `deployment-2.0` ist **kein lauffähiger Shopware-Shop**. Es enthält nur die Dateien, die AGIQON selbst pflegt – rund 50 Stück. Die komplette Shopware-Grundstruktur (`bin/console`, `src/Kernel.php`, `config/bundles.php`, `public/index.php` …) entsteht erst beim ersten `composer install` über **Symfony-Flex-Recipes**.

Konfiguriert ist das in `composer.json:17-24`:

```json
"extra": {
    "symfony": {
        "allow-contrib": true,
        "endpoint": [
            "https://raw.githubusercontent.com/shopware/recipes/flex/main/index.json",
            "flex://defaults"
        ]
    }
}
```

Diese generierten Dateien sind bewusst **gitignored** (`.gitignore:4-34`) und werden bei jedem `composer install` neu erzeugt:

| Recipe | Erzeugt |
|---|---|
| `shopware/core` | `bin/console`, `bin/ci`, `config/jwt/`, `config/services.xml`, `public/index.php`, `src/Kernel.php`, `custom/`, `files/`, `.htaccess` |
| `shopware/administration` | Admin-Bundle, `bin/build-administration.sh`, `bin/watch-administration.sh` |
| `shopware/storefront` | Storefront-Bundle, `bin/build-storefront.sh`, `bin/watch-storefront.sh` |
| `shopware/elasticsearch` | Elasticsearch-Bundle registrieren |
| `frosh/code-quality-meta` | `vendor-bin/` für PHPStan, CS-Fixer, Rector |

**Konsequenz für dich:** Das Template bleibt versionsübergreifend nutzbar. Du setzt in der `composer.json` die Shopware-Version, und die passende Grundstruktur wird erzeugt. Fehlt nach dem Klonen `bin/console`, ist das kein Fehler – es existiert schlicht noch nicht.

> **Achtung:** Weil `bin/console` erst nach `composer install` existiert, lässt sich vorher kein Shopware-Kommando ausführen. Die Reihenfolge in [04 – Lokale Umgebung](04-lokale-umgebung.md) ist deshalb nicht verhandelbar.

---

## 2. Branch-Modell

Zwei Branches steuern alles:

| Branch | Umgebung | Composer | Pipeline-Jobs |
|---|---|---|---|
| `develop` | Staging | inkl. Dev-Dependencies | `stage-*` |
| `main` | Production | `--no-dev` | `prod-*` |

Belegt in `.gitlab-ci.yml.dist` (jede `rules:`-Bedingung prüft `$CI_COMMIT_BRANCH`) und in `.deployment/deploy.php:61` bzw. `:74`.

Feature-Branches lösen **kein** Deployment aus. Für sie ist nur der Job `test-build-js` vorgesehen – beachte dazu die Einschränkung in [Troubleshooting](troubleshooting.md).

---

## 3. Die CI/CD-Pipeline

Fünf Stages, definiert in `.gitlab-ci.yml`:

```
build-composer → test-php → build-js → test-js → deploy
```

### Wo die Pipeline definiert ist

`.gitlab-ci.yml` enthält nur noch `stages:` und eine `include:`-Liste. Die eigentlichen Definitionen liegen aufgeteilt in `.ci/`:

| Muster | Inhalt |
|---|---|
| `.ci/variables.yml` | Globale `variables:` und `cache:` |
| `.ci/<stage>-base.yml` | Hidden Job mit allem, was sich die Umgebungen teilen: Image, `before_script`, `artifacts` |
| `.ci/<stage>-<umgebung>.yml` | Die konkreten Jobs genau einer Umgebung |

Der Zuschnitt ist darauf ausgelegt, dass eine **zusätzliche Umgebung** ergänzt werden kann, ohne bestehende Definitionen anzufassen – siehe [Pipeline erweitern](#4-pipeline-erweitern).

> **Wichtig für eigene Änderungen:** Die Basis-Definitionen werden per `extends:` referenziert, nicht über YAML-Anchors. Anchors (`&name` / `<<: *name`) wirken **nur innerhalb derselben Datei** und funktionieren nicht über `include:`-Grenzen hinweg.

### Job-Matrix

| Stage | Job (develop) | Job (main) | Datei | Was passiert |
|---|---|---|---|---|
| build-composer | `stage-composer` | `prod-composer` | `composer-*.yml` | Branch-Referenzen der eigenen Plugins setzen, `composer install`, `composer bin all install`, Flex-Recipes anwenden |
| test-php | `stage-codestyle` | `prod-codestyle` | `test-php-*.yml` | PHP-CS-Fixer im Dry-Run |
| test-php | `stage-phpstan` | `prod-phpstan` | `test-php-*.yml` | PHPStan Level 8 |
| test-php | `stage-phpunit` | `prod-phpunit` | `test-php-*.yml` | PHPUnit |
| build-js | `stage-build-js` | `prod-build-js` | `build-js-*.yml` | `shopware-cli project admin-build` + `storefront-build --skip-theme-compile` |
| test-js | `stage-eslint` | `prod-eslint` | `test-js-*.yml` | ESLint über `custom/` |
| test-js | `stage-ludtwig` | `prod-ludtwig` | `test-js-*.yml` | Twig-Linting über `custom/` |
| deploy | `stage-deploy` | `deploy-production` | `deploy-*.yml` | Deployer auf den Zielserver |

Dazu kommt `test-build-js` (`.ci/build-js-feature.yml`) als einziger Job für Feature-Branches – er baut die Assets zur Kontrolle, deployt aber nichts.

Images: `agiqon/pipeline:PHP_8.4`, für die JS-Jobs `agiqon/pipeline:PHP_8.4-NODE_20`.

### Artefakte statt Neu-Installation

Der Composer-Job reicht sein Ergebnis per Artefakt an alle Folge-Jobs weiter (`.ci/composer-base.yml`): `vendor`, `vendor-bin/*/vendor`, `bin`, `config`, `public`, `src`, `custom`, `auth.json`, `composer.lock`. Deshalb läuft `composer install` genau **einmal** pro Pipeline.

> **Hinweis:** Weil `bin` als Artefakt weitergereicht wird, funktioniert `./bin/ci bundle:dump` im JS-Job (`.ci/build-js-base.yml`) – obwohl `bin/ci` nicht im Repository liegt.

### Qualitäts-Jobs blockieren nicht

**Alle** Jobs der Stages `test-php` und `test-js` haben `allow_failure: true` – auch auf `main`. Ein PHPStan- oder PHPUnit-Fehler verhindert das Deployment also **nicht**. Die Jobs sind zwar über `needs:` verkettet, aber ein Job mit `allow_failure` gilt für nachfolgende Jobs als erfolgreich.

Wenn du ein hartes Qualitäts-Gate willst, entferne `allow_failure: true` in den `<stage>-<umgebung>.yml`-Dateien gezielt. Siehe [TEMPLATE-ISSUES.md](TEMPLATE-ISSUES.md).

---

## 4. Pipeline erweitern

Genau dafür ist `.ci/` aufgeteilt. Kurzreferenz auch direkt im Ordner: `.ci/README.md`.

### Neue Umgebung hinzufügen

Was sich zwischen zwei Umgebungs-Varianten überhaupt unterscheidet – mehr ist es nicht:

| Was | `-stage` | `-prod` |
|---|---|---|
| Branch in `rules` | `develop` | `main` |
| Job-Namen | `stage-*` | `prod-*` / `deploy-production` |
| `needs` | zeigt auf die `stage-*`-Jobs | zeigt auf die `prod-*`-Jobs |
| Composer-Skript | `.local/stage-composer.sh` | `.local/prod-composer.sh` |
| Composer-Flags | – | `--no-dev` |
| Server-IP | `[STAGING SERVER IP]` | `[PROD SERVER IP]` |
| Deployer-Host | `dep deploy staging` | `dep deploy production` |

Beispiel: eine Preview-Umgebung auf dem Branch `preview`.

**1. Fünf Dateien anlegen**, jeweils als Kopie der `-stage`-Variante:

```bash
for s in composer test-php build-js test-js deploy; do
  cp .ci/$s-stage.yml .ci/$s-preview.yml
done
```

**2. In jeder Datei anpassen:** Job-Namen von `stage-*` auf `preview-*`, den Branch in `rules` auf `preview`, und die `needs` auf die neuen Job-Namen.

```yaml
# .ci/composer-preview.yml
preview-composer:
  extends: .composer
  rules:
    - if: '$CI_COMMIT_BRANCH == "preview"'
  script:
    - .local/stage-composer.sh
    - composer install --no-interaction --optimize-autoloader --no-scripts --ignore-platform-reqs && composer run apply-patches
    - composer bin all install --no-interaction --no-scripts
    - composer symfony:recipes:install --yes --no-interaction
    - chmod 755 bin/*
```

**3. In `deploy-preview.yml`** zusätzlich Server-IP und Deployer-Host setzen:

```yaml
    - ssh-keyscan -H <PREVIEW SERVER IP> >> ~/.ssh/known_hosts
    - php vendor/bin/dep deploy preview -vvv
```

**4. Host in `.deployment/deploy.php` ergänzen** – der Name muss zu `dep deploy <host>` passen:

```php
host('preview')
    ->setRemoteUser('<ssh-user>')
    ->setHostname('<preview-ip>')
    ->set('stage', 'preview')
    ->set('branch', 'preview')
    ->set('deploy_path', '/var/www/share/<preview-domain>')
    // ... analog zu host('staging')
```

**5. Includes in `.gitlab-ci.yml` ergänzen:**

```yaml
  - local: '.ci/composer-preview.yml'
  - local: '.ci/test-php-preview.yml'
  - local: '.ci/build-js-preview.yml'
  - local: '.ci/test-js-preview.yml'
  - local: '.ci/deploy-preview.yml'
```

**6. Branch schützen** und den Server nach [05](05-server-vorbereiten.md) vorbereiten.

Die `-base.yml`-Dateien bleiben dabei unangetastet.

### Neue Stage hinzufügen

Beispiel: eine Stage für E2E-Tests zwischen `test-js` und `deploy`.

1. Stage in `.gitlab-ci.yml` unter `stages:` an der richtigen Position eintragen – die Reihenfolge dort bestimmt den Ablauf
2. `.ci/e2e-base.yml` mit dem Hidden Job `.e2e` anlegen (Image, `before_script`, `artifacts`)
3. Je Umgebung eine `.ci/e2e-<umgebung>.yml` mit den konkreten Jobs
4. Alle neuen Dateien unter `include:` eintragen
5. **`needs:` der nachfolgenden Stage anpassen** – sonst hängt die neue Stage nicht in der Kette und läuft parallel statt davor

### Prüfen

Vor dem Commit in GitLab unter `CI/CD → Editor → Validate`, oder über „View merged YAML" die zusammengeführte Pipeline mit aufgelösten `extends:` ansehen.

> **Achtung beim Umbau von Basis-Definitionen:** `extends:` merged verschachtelte Maps rekursiv, der alte Merge-Key `<<:` hat flach überschrieben. Relevant wird das bei Jobs mit eigenem `variables:`-Block – etwa `.build-js`, das `DATABASE_URL` und `SHOPWARE_SKIP_BUNDLE_DUMP` setzt.

---

## 5. Wie das Deployment auf den Server kommt

Deployment 2.0 nutzt **Deployer 8** (`.deployment/composer.json`, gelockt auf `v8.0.5`) mit **rsync** – nicht mit `git pull` auf dem Server.

### Ablauf

1. Die Pipeline baut das komplette Projekt im Runner (Composer + JS-Assets).
2. Der Deploy-Job installiert Deployer (`cd .deployment && composer install`).
3. `php vendor/bin/dep deploy staging|production` synchronisiert das Runner-Verzeichnis per rsync in ein neues Release-Verzeichnis auf dem Server.
4. Nach erfolgreichem Durchlauf wird der Symlink `current` auf das neue Release umgehängt.

Was **nicht** mit übertragen wird, steht in `.deployignore` – unter anderem `.deployment/`, `.local/`, `auth.json`, `node_modules/`, `vendor-bin/`, `docker-compose.yml` und die shared-Verzeichnisse.

### Verzeichnisstruktur auf dem Server

```
/var/www/share/<domain>/
├── current -> releases/42      # Symlink, zeigt auf das aktive Release
├── releases/
│   ├── 38/ 39/ 40/ 41/ 42/     # keep_releases = 5
└── shared/                     # überlebt jedes Deployment
    ├── .env
    ├── install.lock
    ├── config/jwt/
    ├── files/
    ├── var/log/
    └── public/{media,sitemap,thumbnail,robots.txt,.htaccess,.user.ini}
```

Definiert in `.deployment/deploy.php:17-42`:

- **`shared_files`** – Dateien, die einmalig in `shared/` liegen und in jedes Release verlinkt werden: `.env`, `public/.htaccess`, `public/.user.ini`, `install.lock`, `public/robots.txt`
- **`shared_dirs`** – `config/jwt`, `files`, `var/log`, `public/media`, `public/sitemap`, `public/thumbnail`
- **`writable_dirs`** – zusätzlich `var/cache`, `public/theme`, `public/bundles`
- **`keep_releases: 5`**, `default_timeout: 600`, `ssh_multiplexing: false`

> **Merke:** Alles unter `shared/` legst du **einmal von Hand** an (siehe [05](05-server-vorbereiten.md)). Fehlt `shared/.env`, bricht das erste Deployment ab.

### Task-Reihenfolge

`.deployment/deploy.php:82-102`:

| Task | Bedeutung |
|---|---|
| `deploy:info` … `deploy:release` | Release-Verzeichnis anlegen, Lock setzen |
| `rsync` | Dateien vom Runner auf den Server |
| `deploy:shared` / `deploy:writable` | shared-Symlinks setzen, Schreibrechte vergeben |
| `shopware6:maintenance:enable` | Wartungsmodus für alle Sales Channels an |
| `sw:deployment:helper` | **Der eigentliche Shopware-Teil** – siehe unten |
| `sw:health_checks` | `bin/console system:check --context=pre_rollout` |
| `deploy:symlink` | `current` auf das neue Release umhängen |
| `shopware6:maintenance:disable` | Wartungsmodus aus |
| `shopware6:messenger:stop` | Worker des **vorherigen** Releases beenden |
| `cachetool:clear:opcache` | OPcache über den FPM-Socket leeren |
| `deploy:cleanup` | Alte Releases über `keep_releases` hinaus löschen |

Auskommentiert und projektspezifisch zu aktivieren: `shopware6:apps:install_update` (`deploy.php:92-93`) – nur nötig, wenn das Projekt Shopware **Apps** (nicht Plugins) nutzt.

### `shopware-deployment-helper`

Der zentrale Unterschied zu Deployment 1.x: Migrationen, Plugin-Installation und -Update, Theme-Compile und Cache-Warmup werden **nicht mehr einzeln** als Deployer-Tasks gefahren, sondern an ein Shopware-eigenes Tool delegiert:

```php
// .deployment/deploy-shopware6.php:24-26
task('sw:deployment:helper', static function (): void {
    run('cd {{release_path}} && vendor/bin/shopware-deployment-helper run', ['timeout' => null]);
});
```

Der Helper erkennt die Shopware-Version selbst (6.6 und 6.7) und wählt die passenden Console-Kommandos. Ein manuelles `set('shopware_version', ...)` ist **nicht** nötig.

---

## 6. Plugin-Versionen: das Herzstück von 2.0

Eigene Plugins liegen in eigenen Git-Repos und werden per Composer als `dev-main` eingebunden. Damit Staging den `develop`-Stand und Production den `main`-Stand bekommt, schaltet die Pipeline die Branch-Referenzen vor dem Install um:

- `.local/stage-composer.sh` – jedes `require`-Paket mit Version `dev-main` wird auf `dev-develop` umgehängt
- `.local/prod-composer.sh` – jedes `dev-main`-Paket wird erneut als `dev-main` requiret, damit die `composer.lock` nicht auf einem veralteten Commit stehen bleibt

Ausnahmen für abweichende Branchnamen stehen in `composer.json` unter `extra.stage-overrides` bzw. `extra.prod-overrides`.

Details, Beispiele und die lokalen Kommandos: [plugins/README.md](plugins/README.md).

---

## 7. Das Makefile ist die Entwickler-CLI

Statt einer Sammlung von `bin/*.sh`-Skripten gibt es ein `Makefile` mit rund 28 Targets. `make help` listet alle auf. Die wichtigsten:

| Target | Zweck |
|---|---|
| `make deployment-install` | Kompletter Erstaufsatz: Deployer-Deps, Composer, vendor-bin, Flex-Recipes, `system:setup`, `system:install`, JS-Build |
| `make deployment-update-composer` | Nur Abhängigkeiten aktualisieren |
| `make deployment-update-plugin` | Ein einzelnes Plugin aktualisieren (fragt nach dem Composer-Namen) |
| `make deployment-use-staging` / `-prod` | Lokal auf Staging- bzw. Prod-Branches der eigenen Plugins umschalten |
| `make build-js` | Storefront **und** Administration bauen (via `shopware-cli`, identisch zur CI) |
| `make watch-storefront` / `watch-admin` | Dev-Server |
| `make check-ci` | CS-Check + PHPStan + PHPUnit lokal |
| `make cache-clear` / `cache-warmup` | Shopware-Cache |

> **Achtung:** Es gibt zwei Build-Wege. `make build-*` nutzt `shopware-cli` und ist damit deckungsgleich mit der CI – **das ist der offizielle Weg**. Die Composer-Scripts `build:js:*` rufen direkt npm auf und können abweichende Ergebnisse liefern.

---

## 8. Code Quality

Die Tools liegen isoliert unter `vendor-bin/` (via `bamarni/composer-bin-plugin`), damit ihre Abhängigkeiten nicht mit Shopware kollidieren:

```
vendor-bin/phpstan/    PHPStan 2.x + Shopware-Extensions + eigene Regeln
vendor-bin/cs-fixer/   PHP-CS-Fixer 3.x
vendor-bin/rector/     Rector 2.x + frosh/shopware-rector
```

Installiert werden sie mit `composer bin all install` – in `make deployment-install` bereits enthalten.

Konfiguration:

- `phpstan.neon` – Level 8 über `custom/static-plugins`, `custom/plugins`, `vendor/agiqon`
- `.php-cs-fixer.dist.php` – `@Symfony` + `@Symfony:risky`, `declare_strict_types`, `strict_comparison`
- `rector.php` – Sets bis PHP 8.4 / Symfony 7.1 / Shopware 6.6
- `eslint.config.mjs`, `ludtwig-config.toml`

**AGIQON-eigene PHPStan-Regel:** `vendor-bin/phpstan/rules/SalesChannelContextVariableNameRule.php` erzwingt, dass jede Variable vom Typ `SalesChannelContext` auch `$salesChannelContext` heißt.

---

## Weiter geht es

→ [02 – GitLab-Projekt vorbereiten](02-gitlab-projekt.md)
