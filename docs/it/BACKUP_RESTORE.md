# Backup locale e ripristino

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/BACKUP_RESTORE.md) / Italiano

EasyTrack conserva il registro in un database SQLite privato. **Settings → Export local data as JSON** salva un’istantanea separata tramite File. **Settings → Choose JSON backup to restore** valida il file scelto e mostra un’anteprima prima di modificare i dati. I backup possono contenere note, notifiche grezze, righe importate e diagnostica: conservali privatamente.

## Salvare un backup prima di aggiornare

1. Apri l’installazione che contiene i dati e scegli l’esportazione JSON nelle Impostazioni.
2. Salva in una posizione di File esterna alla cartella EasyTrack, eventualmente su iCloud Drive.
3. Verifica che il file sia presente e leggibile. Un CSV/XLSX dei movimenti non sostituisce un backup completo.
4. Aggiorna senza disinstallare e controlla registro e conti. Conserva le copie precedenti finché la verifica non è completa.

## Formato attuale e compatibilità

Il database usa **schema SQLite 13**. I nuovi backup sono **JSON formato 15** e includono tutte le 33 tabelle persistenti, nomi delle colonne e valori, ID di esportazione stabile, data, formato sorgente in caso di conversione e checksum SHA-256 del contenuto. Gli importi restano interi nelle unità minime della valuta. Il cambio di formato non cambia le tabelle del database.

Sono supportati i formati **5–12 e 14**, attraverso conversioni versionate. Il 13 non è mai stato pubblicato come formato backup ed è rifiutato. Formato originale e checksum sono verificati prima della conversione. Il formato 14 sottraeva subito il rimborso previsto dalla spesa personale: la conversione ricalcola soltanto il costo derivato usando spesa originale e incassi realmente collegati, preparando in memoria un archivio formato 15. Conserva importi, date, conti, tipi, collegamenti, identità sorgente e storico operazioni. Lo stesso ricalcolo avviene all’apertura di un database schema 13 esistente, senza riscrivere revisioni e operazioni per la sola correzione derivata.

Il formato 15 accetta un rimborso previsto superiore alla spesa o un incasso collegato superiore al piano. Il collegamento conserva tutto l’incasso; la validazione controlla che il costo personale della spesa non scenda sotto zero e che l’eccedenza resti un guadagno all’interno dello stesso movimento di Entrata. Non servono nuove tabelle o campi. Il formato 14 mantiene prima le proprie regole storiche, poi viene convertito.

I backup precedenti non possono ricostruire decisioni o campi che non contenevano. I formati 2–4 sono rifiutati perché incompleti; un formato più recente richiede un’app più recente. Vedi la [politica contabile](FINANCIAL_ACCOUNTING.md) per Entrate, Spese nette e Netto.

## Anteprima, Sostituisci e Unisci

Il selettore File concede accesso limitato alla lettura. Il limite è 100 MB. Su un database temporaneo EasyTrack controlla versione, checksum originale, struttura di tabelle/colonne, marcatore di inizializzazione, tipi, conteggi leggibili, collegamenti, chiavi esterne e integrità SQLite. L’anteprima mostra conteggi in arrivo e presenti ed eventuali conflitti di Unisci; non cambia il registro.

| Scelta | Comportamento |
| --- | --- |
| **Replace / Sostituisci** | Dopo conferma separata, installa il backup convertito in un’unica transazione SQLite. Verifica uguaglianza esatta delle tabelle, integrità e chiavi esterne prima del commit e dopo la riapertura. |
| **Merge / Unisci** | Inserisce chiavi primarie assenti e accetta righe esistenti identiche byte per byte. Una riga diversa con la stessa identità o un conflitto di unicità secondaria rifiuta l’intera operazione. Non sovrascrive modifiche locali. |

Se il database cambia dopo l’anteprima, la conferma è rifiutata e serve una nuova verifica. Ripetere Sostituisci o Unisci non duplica i movimenti. Un formato 14 con rimborsi previsti può mostrare un costo personale derivato diverso dopo la conversione; gli incassi mantengono le date effettive. Verifica il risultato prima di eliminare le copie precedenti.

## Verifiche e limiti

I test sintetici coprono aggiornamenti dei vecchi formati, andata/ritorno formato 15, Sostituisci, conflitti Unisci, idempotenza, chiavi esterne, righe malformate, anteprime cambiate, rollback, rimborsi collegati e riapertura. Non usano dati finanziari reali.

I backup sono JSON **non cifrati**; l’app non li sincronizza e non li elimina. La posizione dipende dal provider scelto in File. Provider iPhone, aggiornamenti SideStore sul posto, notifiche reali e VoiceOver restano verifiche su dispositivo nella [issue #8](https://github.com/Natizh/EasyTrack/issues/8).

L’implementazione usa [accesso coordinato ai file Apple](https://developer.apple.com/documentation/foundation/nsfilecoordinator), [transazioni SQLite](https://www.sqlite.org/lang_transaction.html), [controlli delle chiavi esterne](https://www.sqlite.org/pragma.html#pragma_foreign_key_check) e [integrità](https://www.sqlite.org/pragma.html#pragma_integrity_check).
