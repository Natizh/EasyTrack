# Documentazione

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/README.md) / Italiano

Parti da [SideStore](SIDESTORE_INSTALL.md) per usare EasyTrack su iPhone, oppure da [Xcode](XCODE_INSTALL.md) per compilarlo. L’app parte in italiano; puoi passare all’inglese da **Impostazioni → Lingua**.

## Installazione e utilizzo

| Guida | Cosa trovi |
| --- | --- |
| [Installazione SideStore](SIDESTORE_INSTALL.md) | Disponibilità IPA, configurazione iniziale, rinnovo, aggiornamenti e problemi comuni. |
| [Installazione Xcode](XCODE_INSTALL.md) | Requisiti, simulatore, dispositivo e creazione dell’IPA non firmato. |
| [Configurazione Comandi Rapidi](SHORTCUTS_SETUP.md) | Sorgente/conto, campi dinamici delle notifiche e attivazione dei formati. |
| [Backup e ripristino](BACKUP_RESTORE.md) | Salvataggio del registro, anteprima e scelta tra Sostituisci e Unisci. |
| [Importazione Excel](EXCEL_IMPORT.md) | Foglio fittizio funzionante, mappatura delle colonne e anteprima. |
| [Esportazione movimenti](TRANSACTION_EXPORT.md) | Opzioni CSV/XLSX, filtri, colonne e limiti. |
| [Lingua dell’app](LOCALIZATION.md) | Preferenza della lingua, formati e comportamento dei backup. |

## Comprendere il comportamento

| Riferimento | Argomento |
| --- | --- |
| [Politica contabile](FINANCIAL_ACCOUNTING.md) | Entrate, Spese lorde/nette, rimborsi ricevuti, eccedenze e date. |
| [Parser notifiche](NOTIFICATION_PARSER_DESIGN.md) | Estrazione locale, versioni dei formati, duplicati ed errori. |
| [Riconciliazione ricorrenti](RECURRING_RECONCILIATION.md) | Scadenze attese, pagamenti reali, abbinamenti, conflitti e migrazioni. |
| [Mappatura importazione precedente](IMPORT_MAPPING.md) | Contratto storico seed v1; per iniziare usa la guida Excel. |

## Sviluppo e manutenzione

| Guida | Argomento |
| --- | --- |
| [Sviluppo](DEVELOPMENT.md) | Mappa dei sorgenti, test, contributi e convenzioni bilingui. |
| [Immagini del progetto](SHOWCASE_ASSETS.md) | Rigenerare le schermate dall’app in esecuzione con dati fittizi. |
| [Riferimento convertitore](../../Tools/HistoricalImportConverter/README.it.md) | Mappature avanzate e conversione locale. |

L’app attuale usa **schema SQLite 13**, **formato backup JSON 15** e accetta **schema seed 1–3**. I numeri precedenti nelle sezioni sulle migrazioni descrivono la storia del progetto. Backup, database di importazione ed esportazione dei movimenti hanno scopi diversi e non sono intercambiabili.
