# Globale AGIQON-Plugins einbinden

> Von AGIQON gepflegte Plugins, die in mehreren Kundenprojekten laufen.
> Grundlagen zuerst lesen: [plugins/README.md](README.md)

Globale Plugins liegen auf `gitlab.agiqon.de`, typischerweise unter `general/shopware-6/plugins/`.

**Sie werden ausschließlich per Deploy Key über SSH geladen.** Ein Projekt-Deploy-Token reicht nicht: Er gilt nur für das Repository bzw. die Gruppe, in der er erstellt wurde, und damit nicht für gruppenübergreifende Plugin-Repos.

---

## Die Auth-Regel

| Repo-Art | URL-Form | Authentifizierung |
|---|---|---|
| **Projekteigenes** Plugin (Kunden-Gruppe) | `https://gitlab.agiqon.de/...` | `DEPLOY_TOKEN_USER` + `DEPLOY_TOKEN` |
| **Globales** AGIQON-Plugin | `git@gitlab.agiqon.de:...` | `COMPOSER_DEPLOY_KEY` |

Beide Mechanismen laufen parallel und schließen sich nicht aus. Projekteigene Plugins: siehe [eigene-plugins.md](eigene-plugins.md).

> **Achtung:** Trägst du ein globales Plugin mit einer `https://`-URL ein, scheitert `composer install` mit 401 oder 403 – auch dann, wenn der Deploy-Token korrekt gesetzt ist. Die URL ist dann schlicht der falsche Weg, nicht der Token das Problem.

---

## Einrichtung

### 1. Schlüsselpaar erzeugen

```bash
ssh-keygen -t ed25519 -C "<PROJEKTNAME>-deploy-key"
```

- **Private Key** → CI/CD-Variable `COMPOSER_DEPLOY_KEY` in der Projektgruppe
- Key zusätzlich in **1Password** als SSH-Key ablegen

### 2. Public Key in GitLab hinterlegen

Im **GitLab-Admin-Bereich** unter `Deploy Keys` anlegen. Ablaufzeit: **1 Jahr**.

### 3. Key in jedem Plugin-Repo aktivieren

Für **jedes** globale Plugin-Repository, das im Projekt genutzt wird:

`<PLUGIN-REPO> → Settings → Repository → Deploy keys`

Nach der Aktivierung erscheint der Key dort unter **Enabled deploy keys**.

> **Achtung:** Wird dieser Schritt für ein einzelnes Repo vergessen, scheitert genau dieses Plugin im `composer install` mit `Permission denied (publickey)` – die anderen funktionieren. Der Fehler wirkt dadurch zunächst wie ein Problem des Plugins selbst.

### 4. Repository als SSH-URL eintragen

In der `composer.json` des Projekts:

```json
{
    "type": "git",
    "url": "git@gitlab.agiqon.de:general/shopware-6/plugins/<plugin>.git"
}
```

> **Achtung – im Template zu korrigieren:** Der vorbereitete Eintrag für `agiqoncore` steht auf HTTPS (`composer.json:41`):
>
> ```json
> { "type": "git", "url": "https://gitlab.agiqon.de/general/shopware-6/plugins/agiqoncore.git" }
> ```
>
> Nutzt dein Projekt `agiqon/core` – und das ist der Regelfall –, muss der Eintrag beim Aufsetzen auf SSH umgestellt werden:
>
> ```json
> { "type": "git", "url": "git@gitlab.agiqon.de:general/shopware-6/plugins/agiqoncore.git" }
> ```
>
> Siehe [TEMPLATE-ISSUES.md](../TEMPLATE-ISSUES.md).

### 5. Paket requiren

```json
"require": {
    "agiqon/core": "6.6.0",
    "agiqon/<plugin>": "6.6.0"
}
```

Globale Plugins werden in der Regel über **Tags versioniert**, nicht über `dev-main`. Damit sind sie vom automatischen Branch-Switching der `.local/*-composer.sh`-Skripte nicht betroffen – das ist gewollt: Ein zentrales Plugin soll in allen Projekten denselben, getesteten Stand haben.

> **Hinweis:** Wird ein globales Plugin ausnahmsweise doch als `dev-main` eingebunden, greift das automatische Umschalten auf `dev-develop` in der Staging-Pipeline. Prüfe in dem Fall, ob das Plugin überhaupt einen `develop`-Branch hat – sonst schlägt `composer install` fehl. Abhilfe: Eintrag unter `extra.stage-overrides`, siehe [plugins/README.md](README.md).

### 6. SSH-Block in der Pipeline behalten

`.ci/composer-base.yml` lädt den Deploy Key in den SSH-Agent:

```yaml
### THIS PART ONLY IF GLOBAL PLUGIN REPOS ARE USED, OTHERWISE THIS CAN BE REMOVED ###
- eval $(ssh-agent -s)
- echo "$COMPOSER_DEPLOY_KEY" | tr -d '\r' | ssh-add -
- mkdir -p ~/.ssh
- chmod 700 ~/.ssh
- ssh-keyscan -H gitlab.agiqon.de >> ~/.ssh/known_hosts
- chmod 644 ~/.ssh/known_hosts
### THIS PART ONLY IF GLOBAL PLUGIN REPOS ARE USED, OTHERWISE THIS CAN BE REMOVED ###
```

**Dieser Block muss stehen bleiben**, sobald das Projekt globale Plugins nutzt. Entfernen darfst du ihn nur, wenn das Projekt **gar keine** globalen Plugins einbindet – dann brauchst du auch `COMPOSER_DEPLOY_KEY` nicht.

Die Zeile darunter (`composer config gitlab-token...`) bleibt in jedem Fall stehen – sie wird für die projekteigenen Plugin-Repos gebraucht.

### 7. Lokaler Zugriff

Für den lokalen `composer install` muss **dein persönlicher SSH-Key** bei `gitlab.agiqon.de` hinterlegt sein (`Preferences → SSH Keys`) und Leserechte auf den Plugin-Repos haben. Der Deploy Key ist ausschließlich für die Pipeline gedacht und wird lokal nicht verwendet.

Prüfen:

```bash
ssh -T git@gitlab.agiqon.de
```

---

## Installieren

```bash
composer update --no-scripts agiqon/<plugin>
bin/console plugin:refresh
bin/console plugin:install --activate <PluginName>
make build-js
```

---

## Key-Ablauf im Blick behalten

Deploy Keys werden mit einer Ablaufzeit von einem Jahr angelegt. Läuft der Key ab, schlägt der `composer`-Job **aller** Projekte, die ihn nutzen, gleichzeitig fehl.

**Empfehlung:** Ablaufdatum bei der Erstellung im Team-Kalender oder Ticketsystem vormerken.

---

## Checkliste

- [ ] Schlüsselpaar erzeugt, Private Key als `COMPOSER_DEPLOY_KEY` in der Projektgruppe hinterlegt
- [ ] Key in 1Password abgelegt
- [ ] Public Key im GitLab-Admin-Bereich unter *Deploy Keys* angelegt (Ablaufzeit 1 Jahr)
- [ ] Key in **jedem** genutzten globalen Plugin-Repo aktiviert (*Enabled deploy keys*)
- [ ] Repository-Einträge in `composer.json` als `git@gitlab.agiqon.de:...` – auch der vorbereitete `agiqoncore`-Eintrag
- [ ] Paket in `require` mit fester Version eingetragen
- [ ] SSH-Block in `.ci/composer-base.yml` behalten
- [ ] `vendor/agiqon` in der `chown`-Zeile `.ci/build-js-base.yml` enthalten
- [ ] Persönlicher SSH-Key für den lokalen Zugriff hinterlegt (`ssh -T git@gitlab.agiqon.de`)
- [ ] Plugin installiert, aktiviert, `make build-js` gelaufen
- [ ] Ablaufdatum des Deploy Keys vorgemerkt
