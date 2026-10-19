# Deployment 2.0 – Dokumentation

Entwickler-Dokumentation für das AGIQON-Deployment-Template für Shopware 6.

> **Hinweis:** Die Confluence-Seiten zum Thema Deployment beschreiben **Version 1.x**. Deployment 2.0 unterscheidet sich strukturell erheblich – siehe [migration-1x-zu-2x.md](migration-1x-zu-2x.md). Für neue Projekte gilt ausschließlich diese Dokumentation.

---

## Wo fange ich an?

| Ich will … | Lies |
|---|---|
| verstehen, wie das Deployment überhaupt funktioniert | [01 – Architektur](01-architektur.md) |
| ein **neues Projekt** aufsetzen | [02](02-gitlab-projekt.md) → [03](03-projekt-aufsetzen.md) → [04](04-lokale-umgebung.md) → [05](05-server-vorbereiten.md) → [06](06-erstes-deployment.md), in dieser Reihenfolge |
| in ein **bestehendes Projekt** einsteigen | [onboarding.md](onboarding.md) |
| ein **Plugin hinzufügen** | [plugins/README.md](plugins/README.md) |
| ein Projekt von **1.x auf 2.0** umstellen | [migration-1x-zu-2x.md](migration-1x-zu-2x.md) |
| wissen, warum die **Pipeline rot** ist | [troubleshooting.md](troubleshooting.md) |

---

## Alle Dokumente

### Neues Projekt aufsetzen

Die Schritte bauen aufeinander auf und sollten in dieser Reihenfolge abgearbeitet werden.

| # | Dokument | Inhalt |
|---|---|---|
| 01 | [Architektur](01-architektur.md) | Flex-Recipes, Branch-Modell, Pipeline, Deployer, `shared/`, Makefile |
| 02 | [GitLab-Projekt](02-gitlab-projekt.md) | Gruppe, Repository, Branches, CI/CD-Variablen, Deploy-Token, SSH-Keys |
| 03 | [Projekt aufsetzen](03-projekt-aufsetzen.md) | Template klonen, alle Platzhalter ersetzen |
| 04 | [Lokale Umgebung](04-lokale-umgebung.md) | Docker oder devenv, `make deployment-install` |
| 05 | [Server vorbereiten](05-server-vorbereiten.md) | Verzeichnisse, `shared/.env`, DocumentRoot, Supervisor/Cron |
| 06 | [Erstes Deployment](06-erstes-deployment.md) | Push, Pipeline, Admin-User, Rollback |

> **Warum GitLab zuerst?** In 1.x kam GitLab am Ende. In 2.0 braucht schon der erste lokale `composer install` die Zugangsdaten, weil die `composer.json` auf `gitlab.agiqon.de` und `packages.shopware.com` zugreift.

### Plugins

| Dokument | Inhalt |
|---|---|
| [plugins/README.md](plugins/README.md) | **Zuerst lesen.** Repository-Typen, `dev-main` ↔ `dev-develop`, `stage-overrides` / `prod-overrides` |
| [plugins/eigene-plugins.md](plugins/eigene-plugins.md) | Projektspezifische Individualentwicklung |
| [plugins/globale-plugins.md](plugins/globale-plugins.md) | Übergreifende AGIQON-Plugins, Deploy Keys |
| [plugins/store-plugins.md](plugins/store-plugins.md) | Gekaufte Plugins aus dem Shopware Store |

### Querschnitt

| Dokument | Inhalt |
|---|---|
| [onboarding.md](onboarding.md) | In ein laufendes Projekt einsteigen, Branch-Workflow, Alltag |
| [migration-1x-zu-2x.md](migration-1x-zu-2x.md) | Umstieg von Deployment 1.x, Delta-Tabelle, Cutover |
| [troubleshooting.md](troubleshooting.md) | Fehlerbilder nach Symptom |
| [TEMPLATE-ISSUES.md](TEMPLATE-ISSUES.md) | Bekannte Fehler im Template selbst, als Issue-Vorlage |

---

## Das Wichtigste in Kürze

**Branches steuern alles.**
`develop` → Staging, `main` → Production. Feature-Branches deployen nicht.

**Das Template ist kein Shop.**
`bin/console`, `src/Kernel.php` und die halbe Verzeichnisstruktur entstehen erst bei `composer install` über Symfony-Flex-Recipes. Sie sind gitignored.

**`make` ist die CLI.**
`make deployment-install` ersetzt den kompletten manuellen Setup-Ablauf aus 1.x. `make help` zeigt alle Targets.

**Plugin-Versionen schalten automatisch um.**
`.local/stage-composer.sh` und `.local/prod-composer.sh` hängen eigene Plugins zwischen `dev-develop` und `dev-main` um. Ausnahmen über `extra.stage-overrides` / `extra.prod-overrides`.

**Zwei Auth-Wege für Plugin-Repos.**
Projekteigene Repos: HTTPS + `DEPLOY_TOKEN`. Globale AGIQON-Plugins: SSH + `COMPOSER_DEPLOY_KEY`. Der Token ersetzt den Key nicht – globale Plugins sind ohne Deploy Key nicht erreichbar.

**Docker oder devenv ist Geschmackssache.**
Beide Konfigurationen liegen immer im Projekt. Jeder Entwickler wählt selbst; im selben Projekt können Kollegen unterschiedliche Stacks fahren.

**Die Pipeline blockiert nicht bei Qualitätsfehlern.**
Alle Test-Jobs haben `allow_failure: true`. `make check-ci` lokal vor dem Push ist deshalb Pflicht.

**Ein Push im Plugin-Repo deployt nichts.**
Es gibt keinen Pipeline-Trigger zwischen Plugin- und Projekt-Repo. Die Projekt-Pipeline muss separat laufen.

**Die Pipeline liegt aufgeteilt in `.ci/`.**
`.gitlab-ci.yml` enthält nur `stages:` und `include:`. Pro Stage gibt es eine `-base.yml` und je Umgebung eine eigene Datei – so lässt sich eine weitere Umgebung ergänzen, ohne Bestehendes anzufassen.

---

## Diese Dokumentation pflegen

Die Doku liegt im Template und wandert mit jedem Projekt mit. Wird am Template etwas geändert, gehört die passende Doku-Stelle mit angepasst – insbesondere:

| Geändert in | Betrifft |
|---|---|
| `.ci/*.yml`, `.gitlab-ci.yml.dist` | [01](01-architektur.md), [06](06-erstes-deployment.md), [troubleshooting.md](troubleshooting.md), `.ci/README.md` |
| `composer.json` (Platzhalter, Repositories) | [03](03-projekt-aufsetzen.md), [plugins/README.md](plugins/README.md) |
| `.deployment/deploy.php` | [01](01-architektur.md), [03](03-projekt-aufsetzen.md), [05](05-server-vorbereiten.md) |
| `Makefile` | [01](01-architektur.md), [04](04-lokale-umgebung.md) |
| `docker-compose.yml` / `devenv.nix` | [04](04-lokale-umgebung.md) |

Wird ein Punkt aus [TEMPLATE-ISSUES.md](TEMPLATE-ISSUES.md) behoben, den Eintrag dort streichen und den zugehörigen Warnhinweis in der Doku entfernen.
