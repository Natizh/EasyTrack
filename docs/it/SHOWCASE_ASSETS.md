# Rigenerare le immagini del progetto

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/SHOWCASE_ASSETS.md) / Italiano

Le immagini in [`assets/showcase`](../assets/showcase/) compongono **catture reali dei test UI EasyTrack**. Conti, esercenti, movimenti, notifiche e righe importate provengono da dati fittizi. Non vengono usati database, fogli, backup o notifiche personali.

## Requisiti

- macOS con Xcode, simulatore iPhone **già installato** e runtime iOS compatibile.
- Python 3 da riga di comando.
- ImageMagick 7 (`magick`) per cornici originali e composizione PNG; è uno strumento di documentazione, non una dipendenza dell’app.
- Spazio sufficiente per una build e test UI. Lo script segnala spazio libero prima/dopo i passaggi pesanti e riutilizza `.build/XcodeDerivedData`.

Trova un UUID con `xcrun simctl list devices available`. Non creare un simulatore aggiuntivo soltanto per le immagini. Dalla radice:

```sh
python3 scripts/capture_showcase.py --device <existing-iPhone-simulator-UUID>
```

`--replace` rigenera soltanto gli otto PNG dopo la revisione dell’output precedente; per impostazione predefinita non sovrascrive.

Il processo usa una copia temporanea del progetto con bundle ID `local.easytrack.finance.showcase` e verifica che l’app non esista già sul simulatore. Non modifica ID, firma o progetto normali. Un test Swift crea un registro isolato verificato con sei mesi fittizi, due conti, categorie, budget, ricorrenza, PAC, due formati notifiche e l’esempio Excel funzionante. Quattro test UI aprono l’app e allegano sei catture reali. Lo script fissa l’orario della barra di stato, estrae gli allegati, compone cornici coerenti, rimuove l’app temporanea e ripristina modalità chiara/scura e stato di avvio precedenti.

| File | Scopo |
| --- | --- |
| `hero.png` | Apertura README con tre telefoni e Home al centro. |
| `phone-home.png`, `phone-activity.png`, `phone-analytics.png` | Panoramica, storico e analisi. |
| `phone-quick-entry.png`, `phone-automation.png`, `phone-accounts.png` | Inserimento, formati e conto predefinito. |
| `social-preview.png` | Anteprima social GitHub 1280 × 640, pronta per il caricamento. |

Il renderer può usare catture già esportate:

```sh
python3 scripts/render_showcase.py   --screens /path/to/six-real-captures   --output docs/assets/showcase --replace
```

La cartella deve contenere `home.png`, `activity.png`, `analytics.png`, `quick-entry.png`, `automation.png`, `accounts.png`. Il renderer verifica dimensioni e non disegna un’interfaccia sostitutiva.

## Presentazione su GitHub

Un amministratore può caricare [`social-preview.png`](../assets/showcase/social-preview.png) da **Repository → Settings → Social preview → Edit → Upload an image**, se il controllo è disponibile. L’asset è sotto 1 MB. Consulta la [guida GitHub](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview) per requisiti e limiti di condivisione, specialmente nei repository privati.

Descrizione suggerita:

> Native personal finance for iPhone. SwiftUI, SQLite, local backups and user-configured Shortcuts automations.

Topic suggeriti: `ios`, `swift`, `swiftui`, `expense-tracker`, `personal-finance`, `sqlite`, `local-first`, `apple-shortcuts`. I [topic sono pubblici](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics), anche nei repository privati. Lascia vuota la homepage finché non esiste una vera pagina prodotto. La manutenzione delle immagini non richiede modificare la visibilità del repository.
