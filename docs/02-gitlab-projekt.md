# 02 – GitLab-Projekt vorbereiten

> Erster praktischer Schritt beim Aufsetzen eines neuen Projekts.
> Vorher: [01 – Architektur](01-architektur.md) · Danach: [03 – Projekt aufsetzen](03-projekt-aufsetzen.md)

**Warum zuerst GitLab?** In Deployment 1.x kam GitLab erst nach dem lokalen Setup. Das funktioniert in 2.0 nicht mehr: Die `composer.json` referenziert Repositories auf `gitlab.agiqon.de` und `packages.shopware.com` (`composer.json:34-68`). Ohne gültige Tokens scheitert schon der erste lokale `composer install`.

---

## 1. Gruppe und Repository anlegen

1. Unter `Groups → Project` eine **Untergruppe für den Kunden** anlegen.
2. In dieser Untergruppe ein Repository namens **`project`** erstellen.

Die Untergruppe ist wichtig, weil die CI/CD-Variablen auf Gruppenebene gesetzt werden – so sind sie später auch aus den Plugin-Repos des Kunden erreichbar.

---

## 2. Branches anlegen und schützen

Das Repository braucht zwei Branches:

| Branch | Rolle |
|---|---|
| `develop` | **Default-Branch**, deployt nach Staging |
| `main` | deployt nach Production |

- Default-Branch setzen: `Settings → Repository → Branch defaults` → `develop`
- Beide Branches schützen: `Settings → Repository → Protected branches`

---

## 3. CI/CD-Variablen anlegen

`Settings → CI/CD → Variables` **auf Gruppenebene**.

| Variable | Zweck | Typ | Fundstelle |
|---|---|---|---|
| `DEPLOY_TOKEN_USER` | Benutzername des GitLab-Deploy-Tokens | Variable, Masked | `.ci/composer-base.yml` |
| `DEPLOY_TOKEN` | Composer-Auth für **projekteigene** Plugin-Repos (HTTPS) | Variable, Masked | `.ci/composer-base.yml` |
| `SW_COMPOSER_TOKEN` | Bearer-Token für `packages.shopware.com` | Variable, Masked | `.ci/composer-base.yml` |
| `SSH_PRIVATE_KEY` | Private Key, mit dem die Pipeline auf Staging/Production deployt | File oder Variable | `.ci/deploy-base.yml` |
| `APP_SECRET` | Shopware-App-Secret | Variable, Masked | `.env` |
| `COMPOSER_DEPLOY_KEY` | Deploy Key für **globale** AGIQON-Plugins (SSH) | File oder Variable | `.ci/composer-base.yml` |

> **Hinweis:** Die Variable `SSH_KNOWN_HOSTS` wird **nicht** benötigt. Die Pipeline ermittelt die Host-Keys zur Laufzeit mit `ssh-keyscan` (`.ci/deploy-stage.yml` und `.ci/deploy-prod.yml`). Ältere Dokumentation nennt sie noch – das ist veraltet.

### Zwei Auth-Wege, die sich nicht ersetzen

Plugin-Repos auf `gitlab.agiqon.de` werden je nach Art unterschiedlich authentifiziert. Beide Mechanismen laufen parallel:

| Repo-Art | URL-Form | Variable |
|---|---|---|
| **Projekteigenes** Plugin (Kunden-Gruppe) | `https://gitlab.agiqon.de/...` | `DEPLOY_TOKEN_USER` + `DEPLOY_TOKEN` |
| **Globales** AGIQON-Plugin | `git@gitlab.agiqon.de:...` | `COMPOSER_DEPLOY_KEY` |

Ein Deploy-Token gilt nur für das Repository bzw. die Gruppe, in der er erstellt wurde – gruppenübergreifende Plugin-Repos erreicht er nicht. Deshalb braucht es für globale Plugins zwingend den Deploy Key.

### `DEPLOY_TOKEN` / `DEPLOY_TOKEN_USER`

Anlegen unter `Settings → Repository → Deploy tokens`.

- **Name:** `<Projektname> Deploy Token`
- **Username:** `<Projektname>`
- **Scopes:** `read_repository` **und** `read_package_registry`

Beide Werte brauchst du gleich nochmal für die lokale `auth.json` (Schritt 6).

### `SSH_PRIVATE_KEY`

Schlüsselpaar erzeugen:

```bash
ssh-keygen -t ed25519 -C "<PROJEKTNAME>"
```

- **Private Key** → CI/CD-Variable `SSH_PRIVATE_KEY`
- **Public Key** → wird später auf dem Server hinterlegt, siehe [05 – Server vorbereiten](05-server-vorbereiten.md)
- Beide Keys im SharePoint unter *Kunden → SSH Keys* ablegen

### `SW_COMPOSER_TOKEN`

Zunächst mit einem Platzhalter belegen (z. B. `placeholder`). Der echte Shopware-Bearer-Token wird beim Einbinden des Shopware Stores nachgetragen – siehe [plugins/store-plugins.md](plugins/store-plugins.md).

### `APP_SECRET`

Dieser Wert existiert noch nicht. Er entsteht beim lokalen `bin/console system:setup` in Schritt [04](04-lokale-umgebung.md) und wird **danach** hier nachgetragen.

### `COMPOSER_DEPLOY_KEY`

Nötig, sobald das Projekt übergreifende AGIQON-Plugins nutzt – das ist der Regelfall, weil bereits `agiqon/core` dazugehört. Nur ein Projekt ganz ohne globale Plugins kommt ohne diese Variable aus.

```bash
ssh-keygen -t ed25519 -C "<PROJEKTNAME>-deploy-key"
```

- Private Key → CI/CD-Variable `COMPOSER_DEPLOY_KEY`, zusätzlich in 1Password als SSH-Key ablegen
- Public Key → im GitLab-Admin-Bereich unter **Deploy Keys** anlegen (Ablaufzeit 1 Jahr)
- Anschließend muss der Key **in jedem genutzten globalen Plugin-Repo** aktiviert werden: `<PLUGIN-REPO> → Settings → Repository → Deploy keys`

> **Achtung:** Der Deploy Key ersetzt den Deploy-Token **nicht**. Beide werden parallel gebraucht – der Token für projekteigene Repos, der Key für globale.

Details: [plugins/globale-plugins.md](plugins/globale-plugins.md).

---

## 4. Job-Token-Berechtigungen

Damit Pipelines aus Plugin-Repositories auf das Projekt zugreifen dürfen, muss die Plugin-Gruppe freigegeben werden:

`Settings → CI/CD → Job token permissions` → Plugin-Gruppe hinzufügen.

---

## 5. Shopware-Bearer-Token

Der Token für `packages.shopware.com` stammt aus dem Shopware-Account des Kunden bzw. aus dem AGIQON-Account. Er wird an zwei Stellen gebraucht:

- CI/CD-Variable `SW_COMPOSER_TOKEN`
- lokale `auth.json`

Solange das Projekt keine Store-Plugins nutzt, genügt ein Platzhalter.

---

## 6. `auth.json` lokal anlegen

Die `auth.json` ist **gitignored** (`.gitignore:1`) und wird nie eingecheckt. Sie entsteht aus der Vorlage:

```bash
cp auth.json.dist auth.json
```

Danach die Platzhalter ersetzen:

```json
{
    "gitlab-token": {
        "gitlab.agiqon.de": {
            "username": "<DEPLOY_TOKEN_USER>",
            "token": "<DEPLOY_TOKEN>"
        }
    },
    "bearer": {
        "packages.shopware.com": "<SW_COMPOSER_TOKEN>"
    }
}
```

> **Achtung:** Ohne diese Datei schlägt der erste lokale `composer install` mit einem 401/403 gegen `gitlab.agiqon.de` fehl. In der Pipeline wird sie zur Laufzeit aus den CI-Variablen erzeugt (`.ci/composer-base.yml`) – dort musst du nichts tun.

---

## Checkliste

- [ ] Untergruppe für den Kunden angelegt
- [ ] Repository `project` angelegt
- [ ] Branches `main` und `develop` angelegt und geschützt, `develop` als Default
- [ ] Deploy-Token mit `read_repository` + `read_package_registry` erstellt
- [ ] SSH-Schlüsselpaar für das Deployment erzeugt, Private Key als `SSH_PRIVATE_KEY` hinterlegt, beide Keys im SharePoint abgelegt
- [ ] CI/CD-Variablen `DEPLOY_TOKEN_USER`, `DEPLOY_TOKEN`, `SW_COMPOSER_TOKEN`, `SSH_PRIVATE_KEY` gesetzt
- [ ] Job-Token-Berechtigung für die Plugin-Gruppe erteilt
- [ ] `auth.json` lokal erstellt und befüllt
- [ ] `COMPOSER_DEPLOY_KEY` erzeugt, in 1Password abgelegt, im Admin-Bereich als Deploy Key angelegt und in jedem genutzten globalen Plugin-Repo aktiviert *(entfällt nur ohne globale Plugins)*
- [ ] Persönlicher SSH-Key bei `gitlab.agiqon.de` hinterlegt – für den lokalen Zugriff auf globale Plugins
- [ ] Offen: `APP_SECRET` wird nach Schritt 04 nachgetragen

---

→ [03 – Projekt aufsetzen](03-projekt-aufsetzen.md)
