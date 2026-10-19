# `.ci/` – Pipeline-Definitionen

Die GitLab-Pipeline ist hier aufgeteilt, damit sich Stages und Umgebungen unabhängig voneinander verwalten lassen. Einstiegspunkt ist `.gitlab-ci.yml` im Projekt-Root – dort stehen nur noch `stages:` und die `include:`-Liste.

Ausführliche Erklärung inklusive Beispiel für eine dritte Umgebung: [docs/01-architektur.md](../docs/01-architektur.md).

---

## Namenskonvention

| Muster | Inhalt |
|---|---|
| `<stage>-base.yml` | Hidden Job mit allem, was sich alle Umgebungen teilen (Image, `before_script`, `artifacts`) |
| `<stage>-<umgebung>.yml` | Die konkreten Jobs genau einer Umgebung |
| `variables.yml` | Globale `variables:` und `cache:` |

Aktuelle Umgebungen: `stage` (Branch `develop`), `prod` (Branch `main`), dazu `feature` als Sonderfall für Feature-Branches.

```
variables.yml

composer-base.yml       →  composer-stage.yml     composer-prod.yml
test-php-base.yml       →  test-php-stage.yml     test-php-prod.yml
build-js-base.yml       →  build-js-stage.yml     build-js-prod.yml   build-js-feature.yml
test-js-base.yml        →  test-js-stage.yml      test-js-prod.yml
deploy-base.yml         →  deploy-stage.yml       deploy-prod.yml
```

---

## `extends:` statt YAML-Anchors

**Wichtig:** YAML-Anchors (`&name` / `<<: *name`) funktionieren **nicht** über `include:`-Grenzen hinweg – sie gelten nur innerhalb derselben Datei. Die Basis-Definitionen sind deshalb Hidden Jobs (Name beginnt mit einem Punkt) und werden per `extends:` referenziert:

```yaml
# composer-base.yml
.composer:
  stage: build-composer
  image: "agiqon/pipeline:PHP_8.4"

# composer-stage.yml
stage-composer:
  extends: .composer
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'
```

Hidden Jobs aus einer inkludierten Datei sind in allen anderen inkludierten Dateien sichtbar – GitLab führt erst alle Includes zusammen und löst danach `extends:` auf.

Beachte den Unterschied im Merge-Verhalten: `extends:` merged verschachtelte Maps (z. B. `variables:`) rekursiv, der alte Merge-Key `<<:` hat flach überschrieben.

---

## Neue Umgebung hinzufügen

Am Beispiel einer Preview-Umgebung auf dem Branch `preview`:

1. Je Stage eine Datei anlegen, als Kopie der `-stage`-Variante:
   `composer-preview.yml`, `test-php-preview.yml`, `build-js-preview.yml`, `test-js-preview.yml`, `deploy-preview.yml`
2. In jeder Datei anpassen: Job-Namen (`preview-composer`, …), `rules`-Branch, `needs`
3. In `deploy-preview.yml` zusätzlich Server-IP und den Deployer-Host setzen
4. Passenden `host('preview')` in `.deployment/deploy.php` ergänzen
5. Die fünf Dateien in `.gitlab-ci.yml` unter `include:` eintragen

Die `-base.yml`-Dateien bleiben dabei unangetastet.

---

## Neue Stage hinzufügen

1. Stage-Namen in `.gitlab-ci.yml` unter `stages:` an der richtigen Position eintragen
2. `<stage>-base.yml` mit dem Hidden Job anlegen
3. Je Umgebung eine `<stage>-<umgebung>.yml` anlegen
4. Alle neuen Dateien unter `include:` eintragen
5. `needs:` der nachfolgenden Stage anpassen, damit die neue Stage in der Kette hängt

---

## Platzhalter in diesem Ordner

Diese Dateien werden **direkt bearbeitet** – anders als `.gitlab-ci.yml.dist` gibt es hier kein `.dist`-Suffix.

| Datei | Platzhalter |
|---|---|
| `build-js-base.yml` | `vendor/[customer]` |
| `deploy-stage.yml` | `[STAGING SERVER IP]` |
| `deploy-prod.yml` | `[PROD SERVER IP]` |

> **Achtung:** In `build-js-base.yml` bricht `chown` ab, sobald einer der aufgelisteten Vendor-Pfade nicht existiert – und damit der ganze Job. Entferne die Pfade, die dein Projekt nicht nutzt.

---

## Prüfen

Vor dem Commit in GitLab unter `CI/CD → Editor → Validate` bzw. über „View merged YAML" gegenprüfen. Dort siehst du die zusammengeführte Pipeline inklusive aufgelöster `extends:`.
