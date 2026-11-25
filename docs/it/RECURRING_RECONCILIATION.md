# Riconciliazione dei pagamenti ricorrenti

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/RECURRING_RECONCILIATION.md) / Italiano

Questo documento include il progetto originario dello schema 6 e i test del backup formato 7. L’app attuale usa **schema SQLite 13 e backup JSON 15**; vedi [backup e ripristino](BACKUP_RESTORE.md) e [politica contabile](FINANCIAL_ACCOUNTING.md).

Scadenze e movimenti reali restano separati finché un pagamento viene registrato o collegato. Una scadenza crea un’occorrenza `expected` e avanza il cursore della regola in un’unica transazione SQLite. **Non crea movimenti e non cambia i totali**. La scansione propone anche movimenti di Attività compatibili per conto gestito, tipo e finestra locale, senza duplicarli. Una scadenza arretrata resta attesa finché l’utente interviene; non diventa mancata automaticamente. Le date future restano proiezioni di calendario finché scadono o arriva una notifica anticipata plausibile.

Vale anche per i PAC: un **Expected PAC** futuro, dovuto o arretrato resta una previsione nell’interfaccia ricorrenti, fuori da Spese lorde, Spese nette, Entrate, PAC investito e Netto. Registrarlo manualmente crea un movimento `.pacInvestment`; collegare un PAC verificato non ne aggiunge un altro. Le notifiche `.pacInvestment` contribuiscono al PAC effettivo dopo controlli del parser e duplicati. La segnalazione utente sulla Build 9 collocava Expected PAC in Total Expenses; separazione attuale e tipi non riproducono quella classificazione. I test sintetici coprono atteso, mancato, saltato, manuale, importato-collegato e notificato. Nessun movimento storico viene riclassificato implicitamente.

## Identità locale e migrazione

Lo schema 6 conserva l’ID `UUID regola | YYYY-MM-DD locale della scadenza`. La migrazione 5→6 conserva UUID dei movimenti, cancellazioni logiche, operazioni, eventi parser, ID importati e righe originali. Un’occorrenza `materialized` dello schema 5 con movimento attivo diventa `legacy_counted` con lo stesso movimento. Se già eliminato logicamente, diventa `expected` non conteggiata, mantenendo il vecchio UUID come provenienza provvisoria e una ragione di revisione. `skipped` resta invariato. La migrazione usa `BEGIN IMMEDIATE` e controlli di integrità e chiavi esterne prima del commit.

`recurring_occurrences_local` ammette `expected`, `legacy_counted`, `recorded_manual`, `confirmed`, `skipped`, `missed`, `cancelled`. Solo i tre stati conteggiati hanno un `transaction_id` effettivo; i totali leggono comunque soltanto movimenti attivi. Un indice univoco parziale permette alla vecchia riga eliminata di mantenere il riferimento mentre una reale attiva assume l’occorrenza.

`recurring_candidates` conserva coppie evento/movimento in attesa, rifiutate o confermate e le motivazioni. `recurring_payee_aliases` contiene alias normalizzati approvati dall’utente per regola. `recurring_reconciliation_audit` registra cambi di stato/identità senza copiare notifiche grezze. La finestra di revisione è 0–14 giorni locali, predefinita 3.

## Abbinamenti e notifiche

Il parser salva prima cattura e tentativo, controlla duplicati esatti e semantici, poi valuta le scadenze prima dell’inserimento. L’abbinamento automatico richiede stesso ID di conto gestito, tipo compatibile, candidato unico, centesimi EUR esatti, stesso **giorno locale**, alias approvato e nessuna modifica in conflitto o movimento concorrente. Non abbina automaticamente tra conti/tipi diversi, dal solo importo, da somiglianze approssimative dell’esercente o da etichette storiche non verificate.

Nella finestra predefinita ±3 giorni, importo/data diversi, beneficiario non approvato, vecchio movimento modificato o più occorrenze generano candidati con motivo. L’ordine considera beneficiario approvato, distanza locale, centesimi esatti, differenza importi e ID stabile. Più opzioni plausibili restano ambigue; importi variabili e date anticipate/posticipate richiedono conferma.

Un pagamento reale può essere conteggiato una volta mentre una scadenza attesa aspetta revisione. Se una vecchia riga manuale/legacy già conteggiata può essere lo stesso pagamento, la notifica è sospesa **senza creare un altro movimento**. La pagina sorgente apre la revisione; l’App Intent non apre pannelli in background. La revisione usa la **versione della regola salvata nel tentativo**.

Confermare una corrispondenza sospesa collega l’evento al vecchio UUID e, dopo conferma esplicita, corregge importo EUR e data conservando nota, categoria e provenienza. Revisioni cambiate di candidato, occorrenza, regola o movimento rifiutano la conferma e richiedono una nuova revisione. Rifiuto o pagamento separato vengono memorizzati; una notifica sospesa può poi creare il proprio movimento. Tentativi, duplicati, candidati e modifiche finanziarie sono atomici; un errore conserva la cattura riprovabile.

Solo regole spesa abbinano spese, entrata con entrata e PAC con PAC. Rimborsi, anticipi, depositi e restituzioni non vengono riconciliati automaticamente. Un collegamento non aggiunge valore finanziario. Valuta/importi originali, cambio storico, recuperabile e quota personale importati non sono sostituiti da stime della regola.

L’utente può registrare un’attesa, collegare un movimento idoneo, scollegare senza ripristinare una vecchia stima, saltare una data o segnare esplicitamente mancato un pagamento arretrato atteso o legacy/manuale conteggiato. Quest’ultimo viene eliminato logicamente solo dopo conferma che spiega l’effetto sui totali. Azioni e cambi sorgente sono verificabili nello storico. Modifiche future al calendario annullano attese future irrisolte, mantenendo storico pagato e ID.

## Importazione storica e backup

Il seed SQLite viene preparato e validato prima dell’importazione. Se movimenti importati possono sovrapporsi a occorrenze legacy/manuali già conteggiate, l’anteprima presenta **un’unica revisione collettiva**. Ogni coppia richiede Same payment o Separate payment; più scelte Same verso una stessa destinazione sono rifiutate. Sono mostrati conti, importi/date/descrizioni, tipo, motivazione ed effetto complessivo sui totali.

Same payment conserva UUID e provenienza del movimento importato eliminando logicamente la stima precedente nella stessa transazione; Separate payment conserva entrambi. Le sole attese non bloccano. Annullamento, decisioni incomplete, sorgente cambiata o errore SQL lasciano invariato il registro.

**Nota storica:** il backup formato 7 conteneva tutte le 25 tabelle dello schema 6, con alias, candidati e audit. La validazione su database temporaneo controllava collegamenti, chiavi esterne, integrità e riapertura. I formato 5/6 venivano convertiti indicando che le decisioni assenti non erano ricostruibili. I formati attuali e le regole Sostituisci/Unisci sono in [backup e ripristino](BACKUP_RESTORE.md). CSV/XLSX restano una vista di sola lettura sui movimenti attivi, senza righe aggiuntive per attese o collegamenti.

## Limiti delle verifiche

I test Swift con dati fittizi coprono recupero scadenze, fine mese, notifiche esatte/proposte/anticipate, replay, candidati multipli, rifiuti, azioni manuali, righe legacy eliminate, migrazione 5→6, decisioni collettive e rollback, compatibilità 5/6, round trip formato 7, totali PAC/Entrate/quote personali ed export.

I test UI mirati su simulatore iOS 27 coprono attese e registrazioni con riavvio, modalità scura e testo grande, ripristino formato 7 tramite File, revisione import con due conflitti e annullamento/conferma, conferma/scollegamento dalla sorgente, azioni manuali e corrispondenza esatta conservata al riavvio. Campi bancari reali, schermo bloccato, aggiornamenti SideStore, File iCloud e VoiceOver manuale restano verifiche su dispositivo nella [issue #8](https://github.com/Natizh/EasyTrack/issues/8).
