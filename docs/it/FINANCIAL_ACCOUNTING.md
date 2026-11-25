# Politica contabile

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/FINANCIAL_ACCOUNTING.md) / Italiano

EasyTrack registra ogni movimento reale in unità minime intere della valuta. Tipo, importo, conto, data, sorgente e collegamenti ai rimborsi restano nel registro. Un rimborso atteso è un credito: non crea un’entrata.

| Valore | Definizione |
| --- | --- |
| Entrate / Income | Movimenti confermati `income` e `reimbursement` con controvalore EUR noto, alla data del singolo incasso. Un rimborso collegato compare una volta per l’intero importo, compresa l’eccedenza. |
| Spese lorde / Gross Expenses | Movimenti effettivi `expense` con valore EUR noto, alla data della spesa. Le spese rimborsabili o rimborsate restano visibili al lordo. |
| Spese nette / Net Expenses | Costo personale delle spese dopo i rimborsi ricevuti. Una previsione non riduce il costo. Gli incassi collegati lo riducono al massimo fino a zero. |
| Netto / Net | Entrate meno Spese lorde. I rimborsi inclusi nelle Entrate non vengono sottratti una seconda volta. |
| Rimborsi attesi / Pending Reimbursements | Parte ancora dovuta di un rimborso previsto esplicitamente, dopo incassi collegati e importi abbandonati. Non è denaro incassato né entrata. |

PAC, anticipi per altri, depositi e restituzioni di depositi mantengono tipi distinti. Non diventano implicitamente Entrate o Spese lorde. Un anticipo può avere un credito residuo e un costo personale se una parte viene abbandonata. Due movimenti separati non vengono interpretati automaticamente come trasferimento.

## Esempi

| Movimenti | Entrate | Spese lorde | Spese nette | Netto | Attesi |
| --- | ---: | ---: | ---: | ---: | ---: |
| Entrata €1.000; spesa €600 | €1.000 | €600 | €600 | €400 | €0 |
| Spesa €100; previsti €100, nessun incasso | €0 | €100 | €100 | −€100 | €100 |
| Stessa spesa; ricevuti e collegati €40 | €40 | €100 | €60 | −€60 | €60 |
| Stessa spesa; ricevuti e collegati i restanti €60 | €100 | €100 | €0 | €0 | €0 |
| Entrata ordinaria €1.000; spese €300, di cui €100 interamente rimborsati | €1.100 | €300 | €200 | €800 | €0 |
| Spesa €17; rimborso ricevuto €18 | €18 | €17 | €0 | €1 | €0 |

## Date e categorie

Entrate, Spese lorde e Netto usano la data effettiva di ciascun movimento. Una spesa di €100 a dicembre con rimborso di €40 a gennaio produce Netto dicembre −€100 e gennaio +€40. L’incasso di gennaio non viene spostato nelle Entrate di dicembre.

Nei report di costo personale, un rimborso **collegato** riduce le Spese nette alla data della spesa originale: nell’esempio dicembre passa a €60. Categoria, esercente, spesa giornaliera e budget seguono questa attribuzione retrospettiva. Collegare o scollegare un rimborso può quindi cambiare un report storico. Un rimborso non collegato mantiene un aggiustamento negativo della spesa personale alla data dell’incasso; il collegamento lo trasferisce alla spesa originale. Abbandonare un credito elimina il residuo atteso senza creare un’altra spesa: il costo non rimborsato era già conteggiato.

Un rimborso previsto può superare la spesa. Gli incassi collegati conservano importo completo, data, conto e identità. La **quota rimborsata** è il minimo tra spesa lorda e incassi collegati; la differenza è **guadagno aggiuntivo** negli stessi movimenti. Per €17 spesi e €18 ricevuti, €17 azzerano il costo e €1 è eccedenza: Entrate €18 una volta, Spese lorde €17, Netto +€1. Con più incassi la ripartizione segue l’ordine dei collegamenti, senza creare movimenti sintetici. Modifica, eliminazione o scollegamento ricalcolano la ripartizione dai collegamenti rimasti. Importi attesi ma non ricevuti restano fuori dalle Entrate.

I controlli Home Entrate, Spese, Spese nette, Netto e PAC aprono Attività con periodo e soli movimenti usati dall’indicatore. La media giornaliera apre il numeratore Spese nette e spiega il divisore dei giorni trascorsi. Attività mostra contributo EUR con segno e totale selezionato; per spese rimborsate distingue lordo, rimborso ricevuto e costo personale. Rimangono ricerca, dettagli ed esportazione.

Le selezioni dei grafici seguono gli stessi contributi per categoria, giorno, mese, esercente e viaggio. Il tocco su un mese chiede quale serie analizzare tra Entrate, Spese e PAC. Il widget facoltativo dei rimborsi attesi mostra tutti i piani ancora aperti; il totale per periodo nelle analisi li attribuisce alla data della spesa o dell’anticipo originale.

## Compatibilità dei dati

SQLite resta allo schema 13. Aprendo un registro precedente l’app ricalcola soltanto il costo personale derivato delle spese con piano di rimborso, senza cambiare importi reali, date, conti, tipi, collegamenti, revisioni o storico operazioni. I nuovi backup sono formato 15. I formato 14 validi vengono verificati con checksum e convertiti prima del ripristino; i precedenti supportati seguono prima le proprie conversioni. Sostituisci e Unisci mantengono validazione su database temporaneo e regole di conflitto. Le righe CSV/XLSX conservano l’identità dei movimenti e includono nelle Entrate i rimborsi effettivi.

La gestione dell’eccedenza non cambia tabelle SQLite o struttura JSON. L’importo del collegamento coincide con l’intero incasso. Quota rimborsata ed eccedenza derivano da spesa verificata e totale incassato. Il formato 15 accetta previsioni/incassi sopra il lordo e controlla limite a zero del costo, residuo e identità. I formato 14 mantengono la validazione originaria più restrittiva prima della conversione. CSV/XLSX mantengono una riga per incasso e le colonne esistenti: Entrate includono l’intero incasso, costo personale usa il valore limitato a zero.

I movimenti esteri senza valore EUR restano visibilmente non convertiti e non ricevono totali inventati. Collegare un rimborso estero richiede un valore EUR esplicito verificato. Le somme intere rifiutano gli overflow.
