# Importare uno storico Excel

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/EXCEL_IMPORT.md) / Italiano

L’app importa un **database SQLite di importazione (seed)**, non direttamente un `.xlsx`. Il percorso è: foglio XLSX, convertitore Python, seed SQLite, anteprima EasyTrack e conferma.

Il convertitore viene eseguito sul computer, usa soltanto la libreria standard Python 3 e non modifica il foglio. Conserva privatamente foglio reale, mappatura, seed e rapporto di controllo fuori dal repository.

## Provare l’esempio funzionante

Scarica [EasyTrack-example-import.xlsx](../examples/EasyTrack-example-import.xlsx) e la [mappatura corrispondente](../examples/simple-import-mapping.json). Il foglio `Movements` contiene tre righe fittizie: spesa, entrata e investimento PAC. Non sono valori predefiniti dell’app.

| Colonna | Obbligatoria? | Contenuto |
| --- | --- | --- |
| `Source ID` | Sì | Identificatore univoco permanente, invariato tra esportazioni e reimportazioni. |
| `Date` | Sì | Data Excel o `YYYY-MM-DD`; sono accettati anche data/ora ISO e testo `DD/MM/YYYY`. |
| `Type` | Sì | `Expense`, `Income` o `PAC investment` nella mappatura semplice. |
| `Description` | Sì | Esercente o descrizione non vuota. |
| `Amount (EUR)` | Sì | Importo **positivo in euro**, per esempio `24.90`, non centesimi. Il tipo determina la direzione. |
| `Category` | No | Etichetta modificabile nell’app. |

L’esempio imposta EUR e fuso `Europe/Rome`: `24.90` diventa **2.490 centesimi interi** nel seed. Non inserire `2490` per indicare €24,90. Correggere una riga mantenendo l’ID richiede una decisione esplicita nell’anteprima, senza sovrascrivere silenziosamente le modifiche locali.

Dalla radice del repository:

```sh
python3 Tools/HistoricalImportConverter/convert_xlsx.py   --input docs/examples/EasyTrack-example-import.xlsx   --mapping docs/examples/simple-import-mapping.json   --output /path/you/control/example-seed.sqlite
```

Sostituisci `/path/you/control/` con una cartella privata esistente. Il comando scrive `example-seed.sqlite` ed `example-seed-import-audit.txt`. Non sovrascrive l’output senza `--replace-output`. Controlla conteggi e rapporto: risolvi `UNREPRESENTABLE_ROW`, ID duplicati e altri avvisi prima di importare. L’esempio produce **3 movimenti e 0 avvisi**.

Trasferisci il seed in una posizione visibile nel selettore **File** dell’iPhone. In EasyTrack apri **Settings → Historical import → Choose SQLite seed**. Controlla conteggi, righe cambiate, duplicati, conti mancanti e sovrapposizioni con pagamenti ricorrenti. Risolvi le decisioni richieste e premi **Import 3 movements**. Fino alla conferma il registro non cambia. Reimportare lo stesso seed invariato non aggiunge righe; le righe assenti da un seed successivo non vengono eliminate automaticamente.

L’esempio a foglio unico non contiene un elenco conti e i movimenti non hanno un conto assegnato. Puoi assegnarlo nell’app dopo l’importazione. Per uno storico reale aggiungi foglio `Accounts` e relativa mappatura se i collegamenti ai conti sono necessari.

## Adattare un foglio reale

Copia la [mappatura completa](../../Tools/HistoricalImportConverter/mapping.example.json) in un file privato e modifica nomi dei fogli, intestazioni e campi opzionali. Ogni foglio configurato deve esistere. `Accounts`, `Trips` e `Recurring` sono esempi facoltativi, non necessari nell’esempio semplice. Un campo `required` richiede intestazione e valore in ogni riga. Le colonne extra non mappate rimangono nella provenienza della riga, senza diventare campi dell’app.

Sono riconosciuti sette tipi: spesa, entrata, investimento PAC, anticipo per altri, rimborso, deposito e restituzione deposito. La tabella `values` collega le etichette del foglio ai tipi precisi dell’app: modifica le etichette a sinistra, conservando i valori di destinazione. Non convertire un tipo sconosciuto in spesa per superare la validazione.

Le mappature avanzate supportano EUR, USD, GBP, CNY, JPY, CHF, CAD, AUD, THB e KWD. Le date possono essere seriali Excel con sistema dichiarato `1900` o `1904`, testo ISO data/data-ora o `DD/MM/YYYY` con ora opzionale. Le date senza fuso usano `source_timezone`; quelle con offset sono convertite nell’ora locale `Europe/Rome` dell’app.

Anche le colonne monetarie mappate come `minor` ricevono **unità normali della valuta** dal foglio. Il convertitore applica la precisione: JPY zero decimali, KWD tre, le altre due. Per includere movimenti esteri nei totali EUR fornisci un controvalore attendibile; l’app non inventa cambi storici.

Il convertitore genera **schema seed v3**; EasyTrack accetta **v1, v2 e v3**. Le [note storiche](IMPORT_MAPPING.md) descrivono una sorgente v1 specifica. Il [riferimento convertitore](../../Tools/HistoricalImportConverter/README.it.md) approfondisce mappature private, rapporto di controllo, date e provenienza.
