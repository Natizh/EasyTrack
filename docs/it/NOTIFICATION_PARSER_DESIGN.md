# Parser locale delle notifiche

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/NOTIFICATION_PARSER_DESIGN.md) / Italiano

Questo riferimento descrive anche l’evoluzione del parser. L’app attuale usa schema SQLite 13 e backup JSON formato 15; vedi [backup e ripristino](BACKUP_RESTORE.md). Per iniziare usa la [guida Comandi Rapidi](SHORTCUTS_SETUP.md).

## Acquisizione e prima configurazione

Un’automazione personale di Comandi Rapidi può passare sorgente, titolo, sottotitolo, messaggio e data facoltativa a **Capture Payment Notification**. L’App Intent salva evento grezzo e tentativo diagnostico prima del parsing. Senza un formato utilizzabile la cattura resta sulla pagina sorgente con **Set up notification format / Add notification format**. L’app non crea movimenti indovinando importo, descrizione o conto.

Il configuratore parte da un campione e presenta sette schede: input, sorgente/conto, direzione/tipo, importo, esercente/descrizione, protezione duplicati e creazione movimento.

App sorgente e conto EasyTrack sono distinti. Una corrispondenza esatta tra nome sorgente e conto viene proposta; altrimenti si sceglie un conto o se ne crea uno. La mappatura è salvata sulla sorgente e condivisa dai suoi formati. Cambiarla influenza soltanto i movimenti futuri. Ogni formato ha nome, direzione e tipo; importo e controparte sono estratti per evento. L’esercente del campione non diventa una condizione fissa.

Le schede mostrano valori aggiornati: campo titolo/sottotitolo/messaggio/testo combinato, parole stabili, delimitatori dell’importo, descrizione, direzione/tipo e finestra duplicati. **Test automation** mostra la proposta esatta con conto, data e stato senza categoria. Si attiva con **Create first transaction** o **Activate without adding sample**. Il replay del primo campione non crea una seconda riga. Debug include campioni fittizi Northstar Pay e Harbor Wallet; Release non mostra quei controlli.

## Estrazione deterministica

Gli importi EUR ammettono `€` o `EUR` prima/dopo il numero, punto o virgola decimale, raggruppamenti delle migliaia chiari e segno esplicito. Ambiguità e valori malformati falliscono. La descrizione può essere prima/dopo l’importo, l’intera riga scelta o testo tra delimitatori. Le condizioni supportano contiene, inizia e termina con. Le regex avanzate rifiutano gruppi, alternanze, riferimenti all’indietro, ripetizioni numerate, pattern lunghi e più di un operatore di ripetizione; analizzano al massimo 512 caratteri. Le regole sono dati, mai codice eseguibile.

Sono valutate tutte le regole attive della sorgente: serve **una sola corrispondenza completa**. Due o più generano diagnostica persistente di ambiguità e nessun movimento. La priorità ordina l’editor, ma non risolve l’ambiguità. I JSON precedenti restano leggibili perché la condizione sul segno è opzionale. Il configuratore prova la bozza anche contro le altre regole attive prima dell’attivazione.

Si usa la data della notifica se fornita; altrimenti l’ora di cattura, indicata nell’anteprima. L’interfaccia crea attualmente movimenti EUR. Ogni regola ha UUID stabile e storico versionato. Modifica, attivazione, riordino o eliminazione logica creano una versione; i movimenti precedenti mantengono il riferimento alla versione usata. Eliminare una regola non elimina i movimenti.

Le regole non assegnano categorie. I movimenti acquisiti hanno categoria SQL null finché scelta da Home o dettaglio. Un’eventuale categorizzazione per esercente è una funzione distinta.

## Duplicati ed errori

Una chiave SHA-256 normalizza sorgente e spazi/maiuscole del contenuto. Con data fornita, la include nella chiave e riconosce replay esatti. Senza data la verifica esatta è limitata a dieci minuti, perché lo stesso testo può descrivere un acquisto successivo. Una seconda chiave combina centesimi EUR, descrizione normalizzata e conto. La finestra simmetrica predefinita è **10 minuti**, con opzioni 5 o 30. Un importo diverso non collide; un evento uguale fuori finestra è consentito. Queste identità sono separate da quelle degli import storici.

Lo schema 3 introdusse `parser_sources`, `parser_rules`, `parser_rule_versions`, `notification_attempts`, `exact_dedup` e `semantic_dedup`. Il 4 aggiunse `local_accounts`, collegamento sorgente-conto e categoria nullable, completando le mappature precedenti senza riscrivere JSON, versioni o movimenti. Gli eventi precedenti restano diagnostici.

Il tentativo grezzo viene confermato per primo. Movimento, provenienza, stato, record duplicati e operazione del registro vengono confermati insieme in un’unica transazione SQLite. Se la seconda fase fallisce, queste scritture tornano indietro e resta una diagnostica fallita riprovabile con campione. Catture non riconosciute e duplicate restano sulla sorgente; non esiste una coda generale di revisione.

## Riconciliazione ricorrenti introdotta nello schema 6

Dopo i controlli duplicati e **prima** di creare un movimento, il parser cerca scadenze ricorrenti usando conto gestito, tipo compatibile, finestra di giorni locali e nome/importo plausibile. Una sola corrispondenza nello stesso giorno, centesimi esatti, beneficiario approvato e nessuna modifica in conflitto può essere confermata automaticamente. Una scadenza attesa si collega al movimento reale; una vecchia riga già conteggiata invariata conserva UUID e acquisisce il collegamento all’evento.

Importo/data diversi, beneficiario non approvato, più scadenze o movimenti concorrenti producono candidati persistenti con motivazione. Se una riga già conteggiata può essere lo stesso pagamento, la notifica resta **Review recurring match** senza seconda registrazione. Se sono coinvolte soltanto scadenze attese, il pagamento reale può essere conteggiato una volta mentre l’abbinamento aspetta conferma.

La pagina sorgente apre la revisione. L’utente conferma, rifiuta o sceglie pagamento separato. Le coppie rifiutate restano memorizzate per non riproporle. Confermare corregge la stima precedente con importo/data reali conservando UUID, nota e categoria. Evento, duplicati, candidato, audit e modifiche finanziarie sono atomici. Nessuna schermata di revisione viene aperta dall’App Intent in background. Vedi [riconciliazione ricorrenti](RECURRING_RECONCILIATION.md).

Il contenuto delle notifiche non è inviato a server o servizi AI. I backup formato 15 includono eventi, tentativi, regole/versioni, duplicati e decisioni di riconciliazione: sono file finanziari privati. Il ripristino valida righe e collegamenti prima della conferma. La verifica locale di una cartella File non sincronizza il database.

## Limiti delle verifiche

I test automatici coprono parsing, migrazioni, rollback, duplicati e percorsi fittizi cattura-formato-movimento, compresi riconciliazione e retry. Non dimostrano formati bancari reali, campi del trigger sul dispositivo, esecuzione bloccata, installazione SideStore o conservazione dei dati negli aggiornamenti fisici. Le verifiche su dispositivo sono raccolte nella [issue #8](https://github.com/Natizh/EasyTrack/issues/8). La compatibilità dipende dal testo effettivamente fornito da Comandi Rapidi e dalla possibilità di definire una regola stabile.
