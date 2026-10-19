# Bekannte Probleme im Template

> Stand: 2026-09-29, geprüft nach dem `.ci/`-Umbau.
>
> Diese Liste dokumentiert Widersprüche und Fehler im Template selbst – **nicht** in abgeleiteten Projekten. Jeder Eintrag ist als GitLab-Issue verwendbar: Fundstelle, Auswirkung, Lösungsvorschlag.
>
> Die Dokumentation unter `docs/` beschreibt bewusst den **Ist-Zustand** und weist an den betroffenen Stellen auf diese Punkte hin. Wird ein Punkt behoben, muss die entsprechende Doku-Stelle mit angepasst werden.

---

## Blocker – brechen die Pipeline

### #1 `agiqoncore`-Repository als HTTPS statt SSH

**Fundstelle:** `composer.json:39-42`

```json
{
    "type": "git",
    "url": "https://gitlab.agiqon.de/general/shopware-6/plugins/agiqoncore.git"
}
```

**Auswirkung:** Globale AGIQON-Plugins werden ausschließlich über einen Deploy Key per SSH geladen. Ein Projekt-Deploy-Token gilt nur für das Repository bzw. die Gruppe, in der er erstellt wurde, und erreicht `general/shopware-6/plugins/` nicht. Der vorbereitete HTTPS-Eintrag scheitert damit reproduzierbar mit 401/403 – und zwar für `agiqon/core` (`composer.json:83`), also in praktisch jedem Projekt.

Der Fehler ist besonders irreführend, weil der Deploy-Token korrekt gesetzt ist und für die projekteigenen Repos funktioniert. Die Fehlersuche läuft dadurch typischerweise in die falsche Richtung.

**Lösung:** Im Template auf SSH umstellen:

```json
{
    "type": "git",
    "url": "git@gitlab.agiqon.de:general/shopware-6/plugins/agiqoncore.git"
}
```

Zusätzlich empfehlenswert: einen Kommentar im `repositories`-Block ergänzen, der die Regel festhält – projekteigene Repos per HTTPS, globale Repos per SSH.

---

## Inkonsistenzen – führen zu Fehlern in abgeleiteten Projekten

### #2 PHP-Version im cachetool-Socket

**Fundstelle:** `.deployment/deploy.php:66` und `:79`

```php
->set('cachetool', '/var/run/php8.3-fpm-[DOMAIN_STAGE].sock')
```

**Auswirkung:** Das gesamte Template ist auf PHP 8.4 ausgelegt (`composer.json:70`, `.deployment/composer.json`, alle `vendor-bin/*/composer.json`, CI-Image `agiqon/pipeline:PHP_8.4`, `devenv.nix:20`, `docker-compose.yml:33`). Der Socket-Pfad blieb auf 8.3 stehen. Der Task `cachetool:clear:opcache` schlägt am Ende jedes Deployments fehl.

**Lösung:** Auf `php8.4-fpm-...` anheben. Da der Pfad ohnehin serverabhängig ist, zusätzlich einen Kommentar im Template ergänzen, dass er pro Projekt geprüft werden muss.

---

### #3 Node-Version: 20 in der CI, 24 lokal

**Fundstellen:**

| Ort | Version |
|---|---|
| `.ci/build-js-base.yml`, `.ci/test-js-base.yml` | Image `agiqon/pipeline:PHP_8.4-NODE_20` |
| `docker-compose.yml:34` | `NODE_VERSION=24` |
| `devenv.nix:16` | `pkgs.nodejs_24` |
| `package.json:3` | `"node": ">=20"` |

**Auswirkung:** Der CI-Build läuft auf einer anderen Node-Version als die lokale Entwicklung. Build-Ergebnisse können abweichen, Fehler treten erst in der Pipeline auf.

**Lösung:** Eine Version festlegen. Empfehlung: das CI-Image auf Node 24 heben und `package.json` auf `>=24` setzen, damit die Divergenz auffällt.

---

### #4 Alle Quality-Jobs mit `allow_failure: true`

**Fundstellen:** `.ci/test-php-stage.yml`, `.ci/test-php-prod.yml`, `.ci/test-js-stage.yml`, `.ci/test-js-prod.yml` – insgesamt 10 Jobs

**Auswirkung:** PHPStan, PHP-CS-Fixer, PHPUnit, ESLint und ludtwig blockieren das Deployment nicht – auch nicht auf `main`. Die Pipeline hat damit faktisch kein Qualitäts-Gate. Die alte `README.md:146` behauptet das Gegenteil („blockt build-js").

**Lösung:** Bewusst entscheiden und dokumentieren. Vorschlag: `allow_failure` auf `main` entfernen (Production-Deployments werden geblockt), auf `develop` beibehalten (Staging bleibt schnell erreichbar).

---

### #5 `extra.prod-overrides` ist nicht angelegt

**Fundstellen:** `composer.json:29-30` definiert nur ein leeres `"stage-overrides": {}`, `.local/prod-composer.sh:30` liest jedoch `extra.prod-overrides`.

**Auswirkung:** Funktioniert (Null-Coalesce im Skript), ist aber inkonsistent. Entwickler, die nur in die `composer.json` schauen, finden den Mechanismus nicht.

**Lösung:** Leeren Block ergänzen:

```json
"extra": {
    "stage-overrides": {},
    "prod-overrides": {}
}
```

---

### #6 `phpstan.neon` ist gitignored, obwohl getrackt

**Fundstelle:** `.gitignore:103` (im Block `###> frosh/code-quality-meta ###`)

**Auswirkung:** Die Datei ist getrackt (`git ls-files phpstan.neon` liefert einen Treffer), aber lokale Änderungen erscheinen nicht in `git status`. Anpassungen an der PHPStan-Konfiguration gehen dadurch stillschweigend verloren.

**Lösung:** Den Eintrag aus `.gitignore` entfernen. Der Block stammt aus einem Flex-Recipe – beim Entfernen darauf achten, dass er nicht beim nächsten `symfony:recipes:install` zurückkehrt.

---

## Kleinere Fehler

### #7 Tote Git-Hook-Scripts, zusätzlich vertauscht

**Fundstelle:** `composer.json:210-213`

```json
"hook:pre-commit": ["bin/pre-commit"],
"hook:pre-commit:install": ["ln -sf $PWD/bin/pre-commit .git/hooks/pre-commit"],
"hook:pre-push": ["bin/pre-commit"],
"hook:pre-push:install": ["ln -sf $PWD/bin/pre-push .git/hooks/pre-push"],
```

**Auswirkung:** Zwei Probleme. Erstens existieren weder `bin/pre-commit` noch `bin/pre-push` im Repository (`bin/` enthält nur `deleted_files_vendor.sh`, `entrypoint.sh`, `exec-with-env`, `package.sh`) und sie stehen auch nicht auf der Liste der Flex-generierten Dateien. Zweitens ruft `hook:pre-push` fälschlich `bin/pre-commit` auf.

**Lösung:** Entweder die beiden Skripte ergänzen (sinnvoll: `pre-commit` → `make cs-check`, `pre-push` → `make check-ci`) oder die vier Scripts samt `scripts-descriptions` entfernen.

---

### #8 Docker-Port 22 kollidiert mit Host-SSH

**Fundstelle:** `docker-compose.yml:19`

```yaml
- "22:22"   # SSH
```

**Auswirkung:** Auf jedem System mit laufendem SSH-Daemon startet der Container nicht. Vor Commit `d74ad91` war das Mapping `2222:22`.

**Lösung:** Zurück auf `"2222:22"`.

---

### #9 Docker- und devenv-Stack divergieren

**Fundstellen:** `docker-compose.yml` vs. `devenv.nix`

| | Docker | devenv |
|---|---|---|
| Datenbank | MariaDB 11.8 | MySQL 8.4 |
| Mail-Catcher | Mailpit | MailHog |

**Auswirkung:** Die Wahl des Stacks ist Entwickler-Präferenz, nicht Projekt-Entscheidung – im selben Projekt arbeiten Kollegen also gleichzeitig gegen MariaDB und gegen MySQL. Bei SQL-Modes und Migrationen verhalten sich die beiden Engines unterschiedlich. Ein Fehler, der nur an einem Arbeitsplatz auftritt, ist dadurch schwer einzugrenzen, und ein Migrations-Bug fällt unter Umständen erst auf Staging auf.

Das macht diesen Punkt dringlicher als eine reine Kosmetik-Frage: Er betrifft nicht zwei Alternativen, zwischen denen ein Projekt wählt, sondern zwei Umgebungen, die parallel im Einsatz sind.

**Lösung:** Auf eine Datenbank-Engine vereinheitlichen – vorzugsweise die, die auch auf den Produktionsservern läuft. Gleiches gilt für den Mail-Catcher, dort ist die Auswirkung aber gering.

---

### #10 `.ai`-Submodul ist nicht initialisiert

**Fundstelle:** `.gitmodules` verweist auf `git@gitlab.agiqon.de:general/AgiqonAIDevTools.git`, das Verzeichnis `.ai/` ist leer.

**Auswirkung:** Alle `make ai-*`-Targets (`Makefile:162-195`) schlagen fehl, bis `git submodule update --init --recursive .ai` ausgeführt wurde.

**Lösung:** Im Template dokumentieren oder `make deployment-install` um die Submodul-Initialisierung ergänzen.

---

### #11 Kosmetischer Paste-Rest in `devenv.nix`

**Fundstelle:** `devenv.nix:98`

```nix
# services.rabbitmq.managementPlugin.enable = true;OptionManagementService.php
```

**Lösung:** Zeilenrest entfernen.

---

## Bereits in der Doku korrigierter Drift

Die folgenden Punkte standen in der alten `README.md` und sind in `docs/` richtiggestellt. Sie erfordern keine Code-Änderung, aber die Root-`README.md` wurde entsprechend angepasst:

| Alte Aussage | Tatsächlich |
|---|---|
| „PHP 8.3+" (`README.md:10`) | `composer.json:70` verlangt `^8.4` |
| `set('shopware_version', '6.7')` in `deploy.php` nötig (`README.md:48-52`) | Version wird vom `shopware-deployment-helper` auto-erkannt (`deploy.php:48`) |
| Job `shopware-cli-validate` in Stage `test-js` (`README.md:148`) | existiert nicht |
| CI-Variable `SSH_KNOWN_HOSTS` nötig (`README.md:151`) | wird nirgends gelesen; die CI nutzt `ssh-keyscan` (`:244`, `:255`) |
| test-php „blockt build-js" (`README.md:146`) | alle Jobs haben `allow_failure: true` |

Zusätzlich beschreibt `config/README.md` Dateien (`bundles.php`, `services.xml`, `etc/`), die im Template nicht enthalten sind, weil sie erst von den Flex-Recipes erzeugt werden. Die Datei sollte entsprechend überarbeitet werden.

---

## Sicherheitshinweis

Der Host-Key-Abgleich erfolgt per `ssh-keyscan` zur Laufzeit (`.ci/composer-base.yml`, `.ci/deploy-stage.yml`, `.ci/deploy-prod.yml`). Das ist Trust-On-First-Use ohne Fingerprint-Verifikation und im Runner-Netz theoretisch MITM-anfällig.

Gegenüber der Vorgängerlösung ist es dennoch eine Verbesserung: Die alte `.deployment/inventory.yml` setzte

```yaml
sshOptions:
  UserKnownHostsFile: '/dev/null'
  StrictHostKeyChecking: 'no'
```

und deaktivierte die Prüfung damit vollständig.

**Mögliche Härtung:** Fingerprints der Zielserver als CI-Variable hinterlegen und statt `ssh-keyscan` direkt in `known_hosts` schreiben.
