# Sviluppo e contributi

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/DEVELOPMENT.md) / Italiano

Segui la [guida Xcode](XCODE_INSTALL.md) per aprire e compilare il progetto. EasyTrack usa SwiftUI, Charts, App Intents, Vision, Speech e SQLite tramite i framework Apple, senza pacchetti esterni per il runtime dell’app. Gli importi sono interi nelle unità minime della valuta.

## Mappa dei sorgenti

| Percorso | Responsabilità |
| --- | --- |
| `EasyTrack/App/` | Avvio e ciclo di vita dell’app. |
| `EasyTrack/UI/` | Schermate, editor e navigazione. |
| `EasyTrack/Shared/` | Modelli, contabilità, parser e logica condivisa. |
| `EasyTrack/Persistence/` | SQLite, migrazioni, backup e riconciliazione. |
| `EasyTrack/Intake/` | App Intent di Comandi Rapidi per acquisire notifiche. |
| `EasyTrack/Import/`, `EasyTrack/Export/` | Validazione/importazione seed ed esportazione movimenti. |
| `EasyTrack/Resources/` | Risorse e cataloghi delle traduzioni. |
| `Tests/`, `EasyTrackUITests/` | Test del core e percorsi sul simulatore con dati fittizi. |
| `Tools/HistoricalImportConverter/` | Convertitore XLSX–SQLite con sola libreria standard Python. |
| `scripts/` | Creazione pacchetti, controlli, test UI e generazione schermate. |
| `docs/en/`, `docs/it/` | Guide corrispondenti in inglese e italiano. |
| `docs/assets/`, `docs/examples/` | Schermate condivise ed esempi fittizi di importazione. |

## Verifiche

Esegui dalla radice del repository. I test Swift/Xcode richiedono gli strumenti Apple appropriati; il convertitore richiede soltanto Python 3.

```sh
swift test --jobs 2
python3 -m unittest Tools/HistoricalImportConverter/test_converter.py
python3 scripts/audit_localization.py
```

Per generazione CSV/XLSX e validazione indipendente:

```sh
sh scripts/test_transaction_export.sh
```

Usa un **UUID di simulatore esistente**, ottenuto con `xcrun simctl list devices available`. Sostituisci il segnaposto prima di eseguire:

```sh
python3 scripts/test_accounting_ui.py --device <existing-iPhone-simulator-UUID>
python3 scripts/test_pr35_ui.py --device <existing-iPhone-simulator-UUID>
```

Il primo verifica la navigazione dagli indicatori Home; il secondo copre notifiche e rimborsi. Entrambi usano identità separate e registri fittizi, rifiutano un’app di test già presente e rimuovono solo la propria installazione. Disabilita i test paralleli per esecuzioni UI dirette da Xcode, evitando cloni dei simulatori. Per schermate reali riproducibili vedi [immagini del progetto](SHOWCASE_ASSETS.md).

Esegui i controlli pertinenti e indica quelli effettivamente svolti. I test sul simulatore non dimostrano notifiche bancarie reali, esecuzione a schermo bloccato, comportamento dei provider File o uso manuale di VoiceOver. Le verifiche su dispositivo sono nella [issue #8](https://github.com/Natizh/EasyTrack/issues/8).

## Proporre una modifica

Consulta le [issue esistenti](https://github.com/Natizh/EasyTrack/issues), descrivi il comportamento concreto e usa esempi fittizi. Mantieni le modifiche mirate, conserva identità e provenienza dei movimenti e spiega verifiche e limiti nella pull request. Non includere registri, notifiche, fogli, backup, file di firma o credenziali personali.

## Convenzioni della documentazione

- Mantieni equivalenti `README.md` e `README.it.md`, con collegamento reciproco.
- Usa gli stessi nomi in `docs/en/` e `docs/it/`, con selettore della lingua e link all’indice locale in ogni pagina.
- Aggiorna entrambe le lingue quando cambia il comportamento. Non tradurre identificatori, comandi, intestazioni CSV e nomi dei file d’esempio.
- Condividi immagini ed esempi fittizi; usa link relativi funzionanti anche nell’anteprima dei branch.
- Conserva le pagine di rimando `docs/*.md` per i link esterni esistenti. Inserisci i nuovi contenuti nelle cartelle linguistiche.
- Distingui schema SQLite attuale, formato backup JSON e schema seed. Identifica esplicitamente i dettagli storici delle migrazioni.
- Non aggiungere badge di licenza, download di release o verifiche completate senza riscontro nel repository.
