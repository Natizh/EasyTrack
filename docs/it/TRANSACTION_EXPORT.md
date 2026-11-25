# Esportazione dei movimenti

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/TRANSACTION_EXPORT.md) / Italiano

**Settings → Export transactions** salva CSV o XLSX tramite File. Attività offre anche **Export filtered transactions**. Sono file distinti dal backup JSON formato 15: non includono notifiche grezze, tentativi del parser, candidati ricorrenti, JSON delle regole o righe sorgente complete dei fogli. L’esportazione non effettua richieste di rete.

Ogni movimento reale produce una riga. Un rimborso superiore alla spesa resta un solo incasso per l’importo intero, conteggiato una volta nelle Entrate. La spesa conserva lordo e costo personale limitato a zero. L’eccedenza è visibile nel dettaglio rimborsi e ricostruibile come incasso meno quota rimborsata; intestazioni e identità non cambiano. Un PAC atteso non produce righe finché non esiste un movimento PAC registrato o collegato.

## Scelte disponibili

Le [decisioni della issue #1](https://github.com/Natizh/EasyTrack/issues/1) prevedono colonne Basic leggibili, campi storici in Detailed e ID tecnici separati facoltativi. CSV interoperabile è il preset iniziale; esiste anche Excel italiano. Tipo e importo positivo restano espliciti accanto all’importo EUR con segno. I filtri di Attività e quelli dell’esportazione si **intersecano**: se incompatibili, il file contiene solo le intestazioni. L’esportazione dalle Impostazioni parte senza filtri di Attività.

## Selezione e valori

Una connessione SQLite di sola lettura apre il database schema 13 esistente e legge movimenti, conti, categorie, viaggi e provenienza da un’unica istantanea coerente. Rifiuta movimenti illeggibili; non avvia l’inizializzatore di scrittura/migrazione né aggiorna i log. Esclude record eliminati e Demo. Ordina per data/ora e UUID stabile. CSV e XLSX usano le stesse righe immutabili.

Sono disponibili tutto lo storico, mese/anno corrente o precedente e date locali personalizzate **inclusive**. Il fuso del dispositivo viene acquisito per l’esportazione; nei cambi d’ora legale si confrontano date di calendario e non finestre fisse di 24 ore. Conti e categorie usano ID stabili, anche archiviati o rinominati; le vecchie etichette restano separate senza collegamenti dedotti. Senza categoria è una scelta esplicita. Conti, categorie, tipi, viaggi e valute ammettono selezioni multiple. La ricerca copre descrizione, nota, conto/categoria, pagante, viaggio e tipo.

| Gruppo | Colonne |
| --- | --- |
| Basic | Data/ora, descrizione, tipo, conto/categoria visualizzati, importo positivo corrente e valuta, EUR corrente se noto, spesa personale EUR, recuperabile EUR, EUR direzionale con segno e nota. |
| Detailed | Sottocategoria, viaggio, pagante, incidenza sui conti, cambio storico e importo/valuta/EUR/data originali dalla provenienza. |
| Tecniche facoltative | ID stabili e foglio/riga sorgente. |

Vuoto significa assente; `0.00` è zero memorizzato. Non si deducono cambi o conti. Un movimento modificato da THB a EUR mantiene distinti importo corrente e valori THB importati.

Il valore EUR direzionale è negativo per spesa, PAC, anticipo e deposito; positivo per entrata, rimborso e restituzione deposito. La spesa personale usa il valore personale memorizzato con segno: un rimborso collegato riduce la spesa originale e ha aggiustamento personale zero sulla propria riga. Non coincide con il valore direzionale.

I riepiloghi Spese includono soltanto `expense`; Entrate include `income` e `reimbursement` reali una volta alle rispettive date; PAC ha un totale separato. Anticipi e depositi restano distinti. Senza controvalore EUR le celle sono vuote e i totali trattano il contributo mancante come zero, senza inventare conversioni. L’accumulo intero controlla gli overflow. Vedi la [politica contabile](FINANCIAL_ACCOUNTING.md) per l’attribuzione temporale.

## Formati e limiti

CSV segue [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) con record CRLF. Il preset interoperabile usa UTF-8 senza BOM, virgola e punto decimale; Excel italiano usa punto e virgola, virgola decimale e BOM UTF-8. Le date sono ISO 8601 con offset. Ogni testo è tra virgolette e le virgolette interne sono raddoppiate. Se il primo carattere significativo è `=`, `+`, `-` o `@`, viene aggiunta una tabulazione dentro il campo per ridurre l’interpretazione come formula, secondo [OWASP](https://owasp.org/www-community/attacks/CSV_Injection). Rimuovere quel prefisso e riaprire il file può reintrodurre il rischio.

XLSX è un file [ECMA-376 Office Open XML](https://www.ecma-international.org/publications-and-standards/standards/ecma-376/) in ZIP senza compressione. Usa testo inline, celle numeriche per importi e date locali Excel, stili valuta/data, larghezze leggibili, intestazione `Movimenti` bloccata e filtro automatico. Il testo inline evita formule da descrizioni non attendibili. Il foglio facoltativo `Riepilogo` contiene conteggio e totali personale/Spese/Entrate/PAC, con gruppi per categoria, conto e mese riconciliati agli stessi totali. Non introduce dipendenze runtime; lo ZIP non compresso mantiene il writer piccolo e deterministico.

Le celle numeriche Excel hanno precisione di 15 cifre significative: l’export XLSX rifiuta importi oltre quel limite anziché perdere centesimi. CSV resta esatto per gli importi in centesimi `Int64` validi. Le date Excel non conservano il fuso: XLSX salva l’ora locale scelta come seriale; CSV mantiene l’offset. Filtri e gruppi mensili usano il medesimo fuso.

## Verifiche

`sh scripts/test_transaction_export.sh` genera file fittizi sotto `DerivedData` ignorata e avvia test Swift e controlli indipendenti. Copre sette tipi, quote personali, recuperabili, PAC, rimborsi, EUR mancanti, valori storici/modificati, ID archiviati, ora legale e date inclusive, intersezioni dei filtri, file vuoti, Unicode, virgolette, prefissi formula, esclusione Demo/eliminati, grandi storici, sola lettura e coerenza CSV/XLSX.

`scripts/validate_transaction_export.py` legge indipendentemente i file con `csv`, `zipfile` e XML di Python e, se disponibile, `openpyxl`. Sono strumenti di sviluppo, non dipendenze dell’app. I test File usano dati fittizi e verificano salvataggio, riepilogo, filtri, persistenza e integrità in sola lettura. iPhone fisico, provider esterni e VoiceOver manuale restano nella [issue #8](https://github.com/Natizh/EasyTrack/issues/8).
