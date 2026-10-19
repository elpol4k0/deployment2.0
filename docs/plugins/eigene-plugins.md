# Projekteigene Plugins einbinden

> Individualentwicklung für genau dieses Projekt.
> Grundlagen zuerst lesen: [plugins/README.md](README.md)

Es gibt zwei Varianten. **Variante A (eigenes Git-Repo) ist der Standard** – sie funktioniert in der Pipeline und unterstützt das Branch-Handling. Variante B ist für schnelles lokales Arbeiten gedacht.

---

## Variante A – eigenes Git-Repository (Standard)

### 1. Plugin-Repository anlegen

In der Kunden-Untergruppe auf `gitlab.agiqon.de` ein Repository für das Plugin anlegen, mit den Branches `main` und `develop`.

Die `composer.json` des Plugins braucht:

```json
{
    "name": "agiqon/mein-plugin",
    "type": "shopware-platform-plugin",
    "extra": {
        "shopware-plugin-class": "Agiqon\\MeinPlugin\\MeinPlugin",
        "label": { "de-DE": "Mein Plugin", "en-GB": "My Plugin" }
    }
}
```

### 2. Repository im Projekt registrieren

In `composer.json` des Projekts den vorbereiteten `git`-Eintrag (Zeile 64–67) befüllen:

```json
{
    "type": "git",
    "url": "https://gitlab.agiqon.de/<kunde>/<plugin-repo>.git"
}
```

Werden mehrere eigene Plugins genutzt, ergänzt du pro Plugin einen weiteren Eintrag.

### 3. Paket requiren

```json
"require": {
    "agiqon/mein-plugin": "dev-main"
}
```

**Genau `dev-main`** – nur diese Schreibweise wird von `.local/stage-composer.sh` und `.local/prod-composer.sh` erkannt und automatisch zwischen `dev-develop` (Staging) und `dev-main` (Production) umgeschaltet. Siehe [plugins/README.md](README.md).

Weicht der Branchname ab, trage eine Ausnahme unter `extra.stage-overrides` / `extra.prod-overrides` ein.

### 4. Installieren

```bash
composer update --no-scripts agiqon/mein-plugin
bin/console plugin:refresh
bin/console plugin:install --activate MeinPlugin
make build-js
```

### 5. Zugriff sicherstellen

Projekteigene Plugin-Repos werden per **HTTPS + Deploy-Token** eingebunden – das ist der vorgesehene Weg und unterscheidet sie von den globalen Plugins, die zwingend einen Deploy Key brauchen.

Composer authentifiziert sich gegen `gitlab.agiqon.de` über den Deploy-Token:

- lokal: `auth.json`
- in der CI: `composer config gitlab-token.gitlab.agiqon.de $DEPLOY_TOKEN_USER $DEPLOY_TOKEN` (`.ci/composer-base.yml`)

Voraussetzung: Das Plugin-Repo liegt in derselben Kunden-Gruppe wie das Projekt – dann deckt der vorhandene Deploy-Token es ab. Liegt es außerhalb, gilt dasselbe wie für globale Plugins: SSH-URL und Deploy Key, siehe [globale-plugins.md](globale-plugins.md).

---

## Variante B – Plugin lokal im Projekt (`path`-Repository)

Für schnelles Arbeiten ohne Umweg über Git. Das Template hat die passenden `path`-Repositories bereits eingetragen (`composer.json:43-63`):

| Verzeichnis | Zweck |
|---|---|
| `custom/plugins/*` | Reguläre Plugins |
| `custom/plugins/*/packages/*` | Sub-Pakete innerhalb eines Plugins |
| `custom/static-plugins/*` | Plugins, die nicht über den Plugin-Manager verwaltet werden |

Alle drei mit `"options": { "symlink": true }` – Composer verlinkt statt zu kopieren, Änderungen wirken sofort.

### Vorgehen

```bash
bin/console plugin:create MeinPlugin      # oder Verzeichnis manuell anlegen
composer require agiqon/mein-plugin:@dev
bin/console plugin:refresh
bin/console plugin:install --activate MeinPlugin
```

> **Achtung:** `/custom/` ist in `.gitignore:23` ausgeschlossen. Ein Plugin, das nur unter `custom/plugins/` liegt, wird **nicht** eingecheckt, landet nicht in der Pipeline und damit nicht auf dem Server. Variante B ist ausschließlich für die lokale Entwicklung geeignet – vor dem ersten Deployment muss das Plugin nach Variante A in ein eigenes Repository überführt werden.

---

## Entwicklungsalltag

| Aufgabe | Kommando |
|---|---|
| Plugin aktualisieren | `make deployment-update-plugin` |
| Auf Staging-Branches umschalten | `make deployment-use-staging` |
| Auf Prod-Branches umschalten | `make deployment-use-prod` |
| Assets bauen | `make build-js` |
| Qualität prüfen | `make check-ci` |

Die Qualitäts-Tools decken `custom/plugins`, `custom/static-plugins` und `vendor/agiqon` ab:

- PHPStan Level 8 (`phpstan.neon`)
- PHP-CS-Fixer `@Symfony` + `@Symfony:risky`
- ESLint über `custom/`
- ludtwig über `custom/`

> **AGIQON-Konvention:** Eine eigene PHPStan-Regel erzwingt, dass jede Variable vom Typ `SalesChannelContext` auch `$salesChannelContext` heißt (`vendor-bin/phpstan/rules/SalesChannelContextVariableNameRule.php`).

---

## Nach einer Plugin-Änderung deployen

Ein Push im Plugin-Repo löst **keine** Projekt-Pipeline aus. Damit die Änderung auf Staging landet:

1. Plugin-Änderung nach `develop` mergen
2. Im Projekt-Repo eine Pipeline auf `develop` auslösen – durch einen Commit oder über `CI/CD → Pipelines → Run pipeline`

Die Pipeline zieht dann über `.local/stage-composer.sh` automatisch den aktuellen `develop`-Head des Plugins.
