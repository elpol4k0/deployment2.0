# Plugins in Deployment 2.0

> Gemeinsame Grundlagen für alle Plugin-Arten. Lies dieses Dokument zuerst – die drei Detailseiten bauen darauf auf.

| Art | Wann | Anleitung |
|---|---|---|
| **Projekteigene Plugins** | Individualentwicklung für genau diesen Kunden | [eigene-plugins.md](eigene-plugins.md) |
| **Globale AGIQON-Plugins** | Von uns gepflegte Plugins, die in mehreren Projekten laufen | [globale-plugins.md](globale-plugins.md) |
| **Store-Plugins** | Gekaufte Plugins aus dem Shopware Store | [store-plugins.md](store-plugins.md) |

---

## 1. Der `repositories`-Block

Alle drei Wege laufen über Composer. Die Quellen sind in `composer.json:34-68` definiert:

```json
"repositories": [
    { "type": "composer", "url": "https://packages.shopware.com" },
    { "type": "git",  "url": "https://gitlab.agiqon.de/general/shopware-6/plugins/agiqoncore.git" },
    { "type": "path", "url": "custom/plugins/*",            "options": { "symlink": true } },
    { "type": "path", "url": "custom/plugins/*/packages/*", "options": { "symlink": true } },
    { "type": "path", "url": "custom/static-plugins/*",     "options": { "symlink": true } },
    { "type": "git",  "url": "https://gitlab.agiqon.de/[LINK_TO_REPOSITORY]" }
]
```

| Eintrag | Wofür |
|---|---|
| `composer` / `packages.shopware.com` | Store-Plugins (Namespace `store.shopware.com/*`) |
| `git` / `agiqoncore.git` | Globales AGIQON-Plugin – **muss auf eine SSH-URL umgestellt werden**, siehe unten |
| `path` / `custom/plugins/*` | Lokal im Projekt liegende Plugins, per Symlink eingebunden |
| `path` / `custom/plugins/*/packages/*` | Sub-Pakete innerhalb eines Plugins (Monorepo-Struktur) |
| `path` / `custom/static-plugins/*` | Plugins, die nicht über den Plugin-Manager verwaltet werden |
| `git` / `[LINK_TO_REPOSITORY]` | Platzhalter für das projekteigene Plugin-Repo (bleibt HTTPS) |

Ergänzt wird das durch `composer.json:15`:

```json
"gitlab-domains": ["gitlab.agiqon.de"]
```

Damit weiß Composer, dass `gitlab.agiqon.de` eine GitLab-Instanz ist und die GitLab-API statt eines rohen Git-Clones nutzen kann.

> **Achtung:** Nicht genutzte Einträge müssen entfernt werden. Bleibt `https://gitlab.agiqon.de/[LINK_TO_REPOSITORY]` stehen, scheitert `composer install` an einer ungültigen Repository-URL.

---

## 2. Authentifizierung: zwei Wege, die sich nicht ersetzen

Welche URL-Form ein Plugin-Repo bekommt, hängt davon ab, wo es liegt:

| Repo-Art | URL-Form | Authentifizierung |
|---|---|---|
| **Projekteigenes** Plugin (Kunden-Gruppe) | `https://gitlab.agiqon.de/...` | `DEPLOY_TOKEN_USER` + `DEPLOY_TOKEN` |
| **Globales** AGIQON-Plugin (gruppenübergreifend) | `git@gitlab.agiqon.de:...` | `COMPOSER_DEPLOY_KEY` |
| **Store-Plugin** | `https://packages.shopware.com` | `SW_COMPOSER_TOKEN` (Bearer) |

Ein Deploy-Token gilt nur für das Repository bzw. die Gruppe, in der er erstellt wurde. Globale Plugins liegen außerhalb der Kunden-Gruppe und sind deshalb **ausschließlich über einen Deploy Key per SSH** erreichbar.

> **Achtung – im Template zu korrigieren:** Der vorbereitete Eintrag für `agiqoncore` (`composer.json:41`) steht auf HTTPS. Nutzt dein Projekt `agiqon/core` – der Regelfall –, muss er beim Aufsetzen auf `git@gitlab.agiqon.de:general/shopware-6/plugins/agiqoncore.git` geändert werden. Sonst scheitert `composer install` mit 401/403. Siehe [globale-plugins.md](globale-plugins.md) und [TEMPLATE-ISSUES.md](../TEMPLATE-ISSUES.md).

---

## 3. Branch- und Versions-Handling

Das ist der zentrale Mechanismus von Deployment 2.0.

### Das Problem

Eigene Plugins werden als `dev-main` eingebunden:

```json
"agiqon/mein-plugin": "dev-main"
```

Damit bekäme Staging denselben Stand wie Production – man könnte nichts testen, bevor es live geht.

### Die Lösung

Zwei Skripte hängen die Branch-Referenzen vor dem `composer install` um. Die Pipeline ruft sie automatisch auf (`.ci/composer-stage.yml` bzw. `.ci/composer-prod.yml`).

#### `.local/stage-composer.sh` – auf `develop` umschalten

Jedes Paket in `require` mit der Version `dev-main` wird auf `dev-develop` umgehängt:

```bash
composer require --no-scripts --ignore-platform-reqs --no-install "agiqon/mein-plugin:dev-develop"
```

#### `.local/prod-composer.sh` – `main` auffrischen

Hier bleibt die Version `dev-main`, das Paket wird aber **erneut requiret**. Der Grund steht im Skript-Header:

> „composer.lock pins a concrete commit per dev branch. Without re-requiring the packages, `composer install` would deploy that stale commit instead of the current head of the branch."

Ohne diesen Schritt würde ein Deployment den in der `composer.lock` festgenagelten alten Commit ausliefern, nicht den aktuellen Stand von `main`.

### Ausnahmen: abweichende Branchnamen

Nutzt ein Plugin andere Branchnamen, trägst du sie in der `composer.json` unter `extra` ein. Einträge dort haben **Vorrang** vor der automatischen Umschaltung.

```json
"extra": {
    "stage-overrides": {
        "agiqon/mein-plugin": "dev-staging"
    },
    "prod-overrides": {
        "agiqon/mein-plugin": "dev-main67"
    }
}
```

> **Hinweis:** Im Template ist nur `stage-overrides` (leer) vorangelegt (`composer.json:29-30`). `prod-overrides` legst du bei Bedarf selbst an – `.local/prod-composer.sh:30` liest den Schlüssel bereits aus.

### Lokal umschalten

```bash
make deployment-use-staging   # eigene Plugins auf dev-develop
make deployment-use-prod      # eigene Plugins auf dev-main
```

Beide Targets rufen das jeweilige Skript auf und führen anschließend `composer update --no-scripts` aus (`Makefile:73-81`).

> **Achtung:** Diese Targets **verändern deine `composer.json` und `composer.lock`**. Prüfe nach dem Umschalten mit `git diff`, was sich geändert hat, und committe bewusst. Ein versehentlich committetes `dev-develop` auf `main` deployt den Entwicklungsstand nach Production.

---

## 4. Plugin-Repos lösen keine Projekt-Pipeline aus

Im Template gibt es **keinen** `trigger:`-Job und keine Multi-Project-Pipeline. Die Kopplung ist rein pull-basiert:

- Push im Plugin-Repo → **nichts** passiert im Projekt
- Nächster Lauf der Projekt-Pipeline → `.local/*-composer.sh` zieht den aktuellen Branch-Head

**Konsequenz:** Nach einer Plugin-Änderung musst du im Projekt-Repo eine Pipeline auslösen – etwa durch einen Merge nach `develop` oder manuell über `CI/CD → Pipelines → Run pipeline`.

---

## 5. Ein Plugin aktualisieren

```bash
make deployment-update-plugin
# Enter plugin composer name: agiqon/mein-plugin
```

Das Target führt aus:

```bash
composer update --no-scripts --ignore-platform-reqs "agiqon/mein-plugin"
```

Anschließend Plugin installieren/aktualisieren und bauen:

```bash
bin/console plugin:refresh
bin/console plugin:update <PluginName>
make build-js
```

---

## 6. Plugins landen nicht im Projekt-Repo

`/custom/` ist in `.gitignore:23` ausgeschlossen. Plugins gehören in **eigene Repositories** und werden per Composer eingebunden. Das gilt auch für Individualentwicklung.

Ausnahme sind Plugins, die bewusst als `path`-Repository im Projekt liegen sollen – dann muss der `.gitignore`-Eintrag projektspezifisch angepasst werden. Das ist die Ausnahme, nicht die Regel.
