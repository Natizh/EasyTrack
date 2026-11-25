# Mappatura storica del seed, schema sorgente v1

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/IMPORT_MAPPING.md) / Italiano

Questo riferimento descrive una vecchia sorgente schema v1, non la procedura iniziale attuale. Per un esempio XLSX funzionante usa [importazione Excel](EXCEL_IMPORT.md). Il convertitore genera v3; EasyTrack accetta v1, v2 e v3. La sorgente esterna resta fuori dal repository e ogni seed è validato prima di cambiare il registro.

## Movimenti

| Campo sorgente `movements` | Rappresentazione locale | Regola |
| --- | --- | --- |
| `id`, `import_fingerprint` | `imported_movements.source_id`, `source_fingerprint`; UUID locale stabile | Identità separata dalle notifiche. Stessa identità e impronta: nessuna modifica. Impronta cambiata: conflitto, mai sovrascrittura silenziosa. |
| `source_sheet`, `source_row`, `source_technical_id` | Provenienza del movimento | Conservati senza modifiche per risalire al foglio. |
| `occurred_at` | `occurred_at` e originale `source_occurred_at` | Legge `yyyy-MM-dd'T'HH:mm:ss` come ora locale Europe/Rome; conserva il testo esatto perché privo di fuso. |
| `kind` | `transactions.kind` e `source_kind` | Mappatura esatta dei sette tipi sotto; nuovi valori rifiutano l’import con numero di riga. |
| `amount_minor`, `currency` | Importo originale e valuta ISO | Unità minime intere. Questa sorgente ammetteva EUR, CNY e THB a due decimali. |
| `eur_minor`, `exchange_rate_eur` | EUR storico e testo decimale del cambio | Conservati entrambi, mai ricalcolati aprendo o modificando un movimento. |
| `personal_expense_eur_minor`, `recoverable_eur_minor` | Campi EUR interi separati | Conserva quota personale con segno, anche rimborsi negativi, e recuperabile. Il contratto storico Home usava il valore personale sorgente. |
| `description`, `category`, `subcategory`, `note` | Campi modificabili | Sottocategoria vuota resta assente; descrizione come titolo. |
| `account`, `trip_id`, `paid_by`, `affects_my_accounts` | Metadati e collegamenti | Conserva l’etichetta conto; collega un viaggio soltanto se esiste. Nessun conto dedotto da etichette assenti in `accounts`. |
| `home_type`, `origin`, `entered_at`, `cached_personal_value` | Provenienza | Conservata senza mostrarla nell’elenco principale. |
| `needs_review`, `review_reason` | Metadati importazione | Conservati senza coda o schermata di revisione automatica e senza ricategorizzazione. |

| `kind` sorgente | Tipo locale | Trattamento storico |
| --- | --- | --- |
| `Spesa` | expense | Uscita; quota personale sorgente. |
| `Entrata` | income | Entrata di cassa, non spesa. |
| `Investimento PAC` | PAC investment | Uscita per investimento, non spesa. |
| `Anticipo per altri` | advance for others | Uscita recuperabile; non personale salvo indicazione sorgente. |
| `Rimborso` | reimbursement | Incasso; aggiustamento personale con segno dalla sorgente. |
| `Deposito` | deposit | Uscita recuperabile, non spesa personale. |
| `Rimborso deposito` | deposit refund | Incasso, distinto da entrata ordinaria e spesa. |

Un tipo nuovo o malformato annulla l’intera importazione; non viene trasformato automaticamente in spesa. Per totali e rimborsi attuali prevale la [politica contabile](FINANCIAL_ACCOUNTING.md).

## Tabelle collegate

| Tabella sorgente | Tabella locale | Regola |
| --- | --- | --- |
| `accounts` | `historical_accounts` | Conserva nome, tipo, valuta, data/valore iniziali, attivo, nota, foglio/riga e JSON originale. Un’etichetta movimento non corrispondente resta indipendente. |
| `trips` | `historical_trips` | Conserva ID e campi; `trip_id` deve esistere quando valorizzato. |
| `recurring_rules` | `historical_recurring_rules` | Conserva tipo abbonamento/investimento, importo/valuta, calendario, dettagli PAC, conto e provenienza. Sono definizioni, senza generare movimenti o scadenze storiche. La vecchia `expected_occurrences` riservava identità e `matched_transaction_id` univoco, senza effetti sui totali. |
| `exchange_rates` | `historical_exchange_rates` | Conserva riga, data, valuta, testo del cambio, stato/origine/chiave e JSON. EUR e cambi dei movimenti non cambiano. |
| `source_rows` | `historical_source_rows` | JSON originale delle celle per foglio/riga. |
| `migration_warnings` | `historical_import_warnings` | Codice e dettaglio come metadati. |
| `migration_meta` | Solo validazione | Richiede `schema_version = 1`; il testo nei metadati non è un’istruzione eseguibile. |

## Validazione e ambiguità

Questo seed storico verifica tabelle/colonne, versione, integrità SQLite, identità, tipi esatti, EUR/CNY/THB, date dei movimenti e cambi, importi originali e ricorrenti positivi, recuperabile non negativo, viaggi, copertura righe, tipi ricorrenti e JSON valido. I contratti v2/v3 aggiungono valute e rimborsi; vedi guida attuale e `SeedMapper.swift`.

Le chiavi primarie rendono univoca l’identità sorgente. L’importatore prepara un’istantanea SQLite coordinata temporanea, valida prima dell’anteprima e importa tutte le tabelle rimuovendo i Demo in una sola transazione. Un errore annulla tutto; lo snapshot viene rimosso al termine o annullamento. Reimport invariato: nessuna modifica. Righe cambiate: decisione esplicita, senza sovrascrivere modifiche locali.

## Conti gestiti e ricorrenze introdotti nello schema locale 6

Nell’aggiornamento dallo schema 5 ogni nome conto dello storico viene aggiunto ai conti gestiti se assente, conservando tabella originale ed etichette dei movimenti. Non si deduce `transactions.account_id` per etichette senza corrispondenza. L’utente sceglie il conto modificando il movimento. Rinomina e archiviazione conservano ID e provenienza.

Le definizioni ricorrenti importate restano in `historical_recurring_rules` senza generare movimenti. L’utente può creare esplicitamente un modello locale EUR scegliendo conto e data iniziale. `historical_source_id` mantiene il collegamento alla definizione; le scadenze locali hanno ID deterministici. Definizioni originali e provenienza restano intatte. Le scadenze dovute sono attese senza effetto contabile.

Prima del commit, eventuali sovrapposizioni con pagamenti ricorrenti **già conteggiati** sono mostrate insieme con descrizioni, date, importi, conti, tipo e motivo. Le etichette legacy non sono considerate ID gestiti. Ogni coppia richiede Same payment o Separate payment; un movimento non può saldare due occorrenze. L’anteprima mostra variazioni complessive a quota personale, Spese, Entrate, PAC, conteggi e righe provvisorie.

Same payment conserva UUID importato, provenienza, valori originali, cambio e quota personale; associa il conto confermato ed elimina logicamente la vecchia stima nella stessa transazione. Separate payment conserva entrambi. Il seed invariato resta senza effetto, errori/annullamenti annullano tutto. Le sole attese non bloccano l’import. Vedi [riconciliazione](RECURRING_RECONCILIATION.md).

**Editor attuale:** mostra e salva un importo EUR in centesimi interi. Valuta/importo originali, EUR storico, cambio, quota personale, riga e JSON restano nella provenienza e nei backup. Modificare un movimento estero imposta il valore corrente in EUR mantenendo l’originale importato. Non esiste una sezione editor “Historical values”. Quote personali importate separate vengono conservate, con nota quando incidono sulla spesa.
