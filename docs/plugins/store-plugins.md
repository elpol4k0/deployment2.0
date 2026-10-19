# Store-Plugins einbinden

> Gekaufte Plugins aus dem Shopware Store.
> Grundlagen zuerst lesen: [plugins/README.md](README.md)

Store-Plugins werden **nicht** per ZIP-Upload installiert, sondern über Composer aus dem Shopware-Paket-Repository gezogen. Nur so landen sie reproduzierbar im Deployment.

---

## 1. Repository

Bereits im Template enthalten (`composer.json:35-38`):

```json
{
    "type": "composer",
    "url": "https://packages.shopware.com"
}
```

Hier ist nichts anzupassen.

---

## 2. Bearer-Token besorgen

Der Zugriff läuft über einen Bearer-Token aus dem Shopware-Account.

1. Im Shopware Account anmelden
2. Die Lizenz dem Shop / der Domain zuordnen
3. Composer-Token erzeugen

Der Token wird an zwei Stellen hinterlegt:

**Lokal** in `auth.json`:

```json
{
    "bearer": {
        "packages.shopware.com": "<TOKEN>"
    }
}
```

**In der CI** als Variable `SW_COMPOSER_TOKEN`. Die Pipeline setzt ihn zur Laufzeit (`.ci/composer-base.yml`):

```bash
composer config bearer.packages.shopware.com $SW_COMPOSER_TOKEN
```

> **Hinweis:** In [02 – GitLab-Projekt](../02-gitlab-projekt.md) wurde `SW_COMPOSER_TOKEN` zunächst mit einem Platzhalter belegt. Spätestens beim ersten Store-Plugin muss der echte Token eingetragen werden.

---

## 3. Plugin requiren

Store-Plugins liegen im Namespace `store.shopware.com/`:

```json
"require": {
    "store.shopware.com/<pluginname>": "^1.0"
}
```

Den exakten Paketnamen findest du auf der Store-Seite des Plugins im Abschnitt zur Composer-Installation.

Im Template steht ein Platzhalter (`composer.json:86`):

```json
"store.shopware.com/[PLUGIN_NAME]": "^1.0"
```

> **Achtung:** Nutzt das Projekt keine Store-Plugins, muss diese Zeile **entfernt** werden. Sonst scheitert `composer install` an einem nicht auflösbaren Paket.

---

## 4. Installieren

```bash
composer update --no-scripts store.shopware.com/<pluginname>
bin/console plugin:refresh
bin/console plugin:install --activate <PluginName>
make build-js
```

Der Plugin-Name für `plugin:install` ist der technische Name (PascalCase), nicht der Composer-Name. `bin/console plugin:list` zeigt ihn an.

---

## 5. Vendor-Pfad in der CI

Der `build-js`-Job setzt vor dem Bauen die Dateirechte (`.ci/build-js-base.yml`):

```yaml
- sudo chown docker:docker bin auth.json vendor/agiqon vendor/store.shopware.de vendor/[customer] -R
```

> **Achtung – Fehler im Template:** Dort steht `vendor/store.shopware.de`. Der Ordner, den Composer anlegt, heißt `vendor/store.shopware.com` (passend zum Repository-Host und zum Paket-Namespace). Da `chown` bei einem nicht existierenden Pfad abbricht, schlägt der Job fehl.

Korrigierte Zeile für ein Projekt mit Store-Plugins:

```yaml
- sudo chown docker:docker bin auth.json vendor/agiqon vendor/store.shopware.com vendor/<kunde> -R
```

Entferne dabei die Vendor-Pfade, die dein Projekt nicht nutzt – `chown` bricht bei jedem fehlenden Pfad ab.

---

## 6. Updates

```bash
make deployment-update-plugin
# Enter plugin composer name: store.shopware.com/<pluginname>

bin/console plugin:refresh
bin/console plugin:update <PluginName>
make build-js
```

Auf dem Server übernimmt der `shopware-deployment-helper` das Plugin-Update automatisch beim Deployment (`deploy-shopware6.php:24-26`) – du musst dort nichts von Hand ausführen.

---

## Typische Fehler

| Symptom | Ursache |
|---|---|
| `Could not find package store.shopware.com/...` | Bearer-Token fehlt oder ist falsch; Lizenz nicht der Domain zugeordnet |
| Plugin lokal da, in der Pipeline nicht | `SW_COMPOSER_TOKEN` in GitLab nicht gesetzt oder noch auf Platzhalter |
| `chown: cannot access 'vendor/store.shopware.de'` | Tippfehler in `.ci/build-js-base.yml`, siehe oben |
| Plugin nach Deployment inaktiv | `plugin:install --activate` lokal gelaufen, aber der Aktivierungsstatus steckt in der Datenbank – auf dem Zielsystem separat aktivieren |

---

## Checkliste

- [ ] Lizenz im Shopware Account der Domain zugeordnet
- [ ] Bearer-Token in `auth.json` eingetragen
- [ ] `SW_COMPOSER_TOKEN` in GitLab gesetzt (kein Platzhalter mehr)
- [ ] Paket in `require` eingetragen, Platzhalter-Zeile entfernt
- [ ] `vendor/store.shopware.com` korrekt in `.ci/build-js-base.yml`
- [ ] Plugin installiert, aktiviert, `make build-js` gelaufen
