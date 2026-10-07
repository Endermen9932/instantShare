# Web-App auf GitHub Pages veröffentlichen

Die Web-App ist dieselbe App wie auf Android, Linux und Windows – nur im Browser.
Sie braucht **keinen Server**: Kamera, QR-Erkennung (zxing als WebAssembly) und das
Zusammensetzen der Dateien laufen komplett im Browser. GitHub Pages liefert nur die
statischen Dateien aus.

Der Workflow `.github/workflows/build-and-release.yml` baut die Web-App bei jedem Push
und legt das Ergebnis im Branch **`gh-pages`** ab. Du musst GitHub Pages nur einmal
einschalten.

## Voraussetzung: öffentliches Repository (oder GitHub Pro)

GitHub Pages gibt es im kostenlosen Tarif nur für **öffentliche** Repositories.
Dieses Repository ist privat. Du hast zwei Möglichkeiten:

- **Repository öffentlich machen:** *Settings → General →* ganz unten *Danger Zone →
  Change repository visibility → Change to public*.
- **Privat lassen:** geht nur mit GitHub Pro, Team oder Enterprise. Die Seite selbst ist
  dann trotzdem öffentlich erreichbar (nur der Quellcode bleibt privat).

## Schritt für Schritt

1. **Workflow einmal laufen lassen.** Das passiert automatisch beim Push. Kontrolle unter
   *Actions → Build & Release*: Der Job **web** muss grün sein. Danach existiert der
   Branch `gh-pages` (unter *Code →* Branch-Auswahl sichtbar).
2. **Schreibrechte für Actions prüfen.** *Settings → Actions → General → Workflow
   permissions*: **Read and write permissions** auswählen und speichern. (Der Workflow
   fordert die Rechte zwar selbst an, aber eine restriktive Einstellung kann das
   blockieren.)
3. **Pages einschalten.** *Settings → Pages → Build and deployment*:
   - *Source:* **Deploy from a branch**
   - *Branch:* **gh-pages**, Ordner **/ (root)** → **Save**
4. **Warten.** Nach 1–2 Minuten erscheint oben auf der Pages-Seite
   „Your site is live at …“. Die Adresse lautet:

   **https://endermen9932.github.io/instantShare/**

   Groß-/Kleinschreibung beachten: Der Pfad muss genau dem Repository-Namen
   (`instantShare`) entsprechen.
5. **Testen.** Seite auf dem Handy öffnen → *Empfangen → Kamera starten* → Zugriff erlauben.
   Mit `…/instantShare/?empfangen` öffnet sich die Seite direkt im Empfangen-Tab; genau
   diesen Link zeigt die App unter *Senden →* QR-Symbol oben rechts als QR-Code an.
6. **Optional: als App installieren.** Im Browser-Menü *Zum Startbildschirm hinzufügen*
   (Android/Chrome) bzw. *Teilen → Zum Home-Bildschirm* (iPhone/Safari).

## Aktualisieren

Jeder Push auf `main` oder einen `claude/*`-Branch baut die Web-App neu und ersetzt den
Inhalt von `gh-pages`. Pages übernimmt das automatisch nach ca. einer Minute. Ein
Browser-Neuladen (ggf. zweimal) holt die neue Version.

## Wenn etwas nicht klappt

| Problem | Lösung |
|---|---|
| 404 unter der Adresse | Pages-Quelle prüfen (Branch `gh-pages`, `/ (root)`); 2 Minuten warten; Groß-/Kleinschreibung im Pfad prüfen. |
| Weiße Seite, Konsole zeigt 404 für `main.dart.js` | Repository umbenannt? Der Workflow baut mit `--base-href /<Repo-Name>/` – einfach neu laufen lassen. |
| Job **web** scheitert bei „Deploy to GitHub Pages“ mit 403 | Schritt 2 (Read and write permissions). |
| Kamera startet nicht | Nur über HTTPS erlaubt (GitHub Pages ist HTTPS). Im Browser die Kameraberechtigung für die Seite erlauben. In In-App-Browsern (z. B. Instagram) klappt es oft nicht – im normalen Browser öffnen. |
| „Pages“ fehlt in den Settings / ist ausgegraut | Repository ist privat ohne Pro-Tarif – siehe Voraussetzung oben. |

## Eigene Domain oder eigener Server

Im Release liegt zusätzlich `InstantShare-<version>-web.zip`. Der Inhalt läuft auf jedem
statischen Webserver mit HTTPS. Wird die App nicht unter `/instantShare/` ausgeliefert,
muss sie mit passendem Pfad gebaut werden, z. B. für die Domain-Wurzel:

```bash
flutter build web --release --base-href /
```
