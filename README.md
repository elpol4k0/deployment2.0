# AGIQON Deployment 2.0

Deployment-Template für Shopware-6-Kundenprojekte.

* **Version:** 2.0.0
* **Dokumentation:** [`docs/`](docs/README.md)

---

## Voraussetzungen

| | Version |
|---|---|
| PHP | 8.4 (`composer.json` verlangt `^8.4`) |
| Node.js | 20 (CI-Image) bzw. 24 (lokale Umgebungen) – siehe [TEMPLATE-ISSUES](docs/TEMPLATE-ISSUES.md) |
| Shopware | 6.6.x oder 6.7.x |
| shopware-cli | aktuelle Version ([Docs](https://sw-cli.fos.gg/)) |

Lokale Umgebung wahlweise **Docker** (`docker-compose.yml`) oder **devenv/Nix** (`devenv.nix`). Beide sind im Projekt hinterlegt – jeder Entwickler nutzt, was er bevorzugt.

---

## Quickstart

```bash
git clone <template-repo> <projektname> && cd <projektname>
rm -rf .git && git init --initial-branch=develop

cp auth.json.dist auth.json      # GitLab- und Shopware-Tokens eintragen
mv .gitlab-ci.yml.dist .gitlab-ci.yml

# Platzhalter ersetzen – auch in .ci/, siehe docs/03-projekt-aufsetzen.md

docker compose up -d             # oder: devenv up
make deployment-install
```

Das vollständige Vorgehen inklusive GitLab- und Server-Vorbereitung steht in der Dokumentation. **Reihenfolge beachten:** GitLab-Projekt und Tokens kommen vor dem ersten `composer install`.

Die Pipeline ist auf `.ci/` aufgeteilt – `.gitlab-ci.yml` enthält nur `stages:` und `include:`. Konventionen und wie man eine weitere Umgebung ergänzt: [`.ci/README.md`](.ci/README.md).

---

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [docs/README.md](docs/README.md) | Einstieg und Inhaltsverzeichnis |
| [01 – Architektur](docs/01-architektur.md) | Wie das Deployment funktioniert |
| [02 – GitLab-Projekt](docs/02-gitlab-projekt.md) | Repository, Branches, CI/CD-Variablen, Token |
| [03 – Projekt aufsetzen](docs/03-projekt-aufsetzen.md) | Platzhalter-Checkliste |
| [04 – Lokale Umgebung](docs/04-lokale-umgebung.md) | Docker oder devenv, `make deployment-install` |
| [05 – Server vorbereiten](docs/05-server-vorbereiten.md) | `shared/`, DocumentRoot, Supervisor |
| [06 – Erstes Deployment](docs/06-erstes-deployment.md) | Pipeline, Rollback |
| [Plugins](docs/plugins/README.md) | Eigene, globale und Store-Plugins |
| [Onboarding](docs/onboarding.md) | In ein bestehendes Projekt einsteigen |
| [Migration 1.x → 2.0](docs/migration-1x-zu-2x.md) | Umstieg vom alten Template |
| [Troubleshooting](docs/troubleshooting.md) | Fehlerbilder nach Symptom |

---

## Die wichtigsten Kommandos

```bash
make help                     # alle Targets
make deployment-install       # Erstaufsatz: Composer, Flex-Recipes, Shopware, Assets
make build-js                 # Storefront + Administration bauen
make watch-storefront         # Dev-Server Storefront
make watch-admin              # Dev-Server Administration
make check-ci                 # CS-Check + PHPStan + PHPUnit
make deployment-use-staging   # eigene Plugins auf dev-develop
make deployment-use-prod      # eigene Plugins auf dev-main
```

---

© 2026 AGIQON GmbH. All rights reserved. | [AGIQON Website](https://www.agiqon-shopware.de)
