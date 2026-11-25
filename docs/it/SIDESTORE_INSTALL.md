# Installare e aggiornare con SideStore

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/SIDESTORE_INSTALL.md) / Italiano

SideStore è consigliato per l’uso quotidiano perché, dopo il setup iniziale, il rinnovo della firma può avvenire sull’iPhone senza riaprire Xcode. Xcode resta lo strumento adatto per compilare l’app o usare il debugger.

## Prima di iniziare

Servono un iPhone supportato sia da EasyTrack (**iOS 17+**) sia dalla versione installata di SideStore, un account Apple e un IPA EasyTrack non firmato compatibile. Segui i [prerequisiti](https://docs.sidestore.io/docs/installation/prerequisites) e la [guida ufficiale](https://docs.sidestore.io/it/docs/installation/install) per setup con computer, abbinamento, modalità sviluppatore dove richiesta e VPN locale. I requisiti SideStore possono differire dalla versione minima di iOS prevista da EasyTrack.

**Il repository non offre attualmente una release IPA precompilata.** Per compilare il pacchetto autonomamente usa la [guida Xcode](XCODE_INSTALL.md#creare-un-ipa-non-firmato). Un IPA non firmato deve essere firmato e installato prima di poter avviare l’app sull’iPhone. SideStore gestisce questa fase, non la compilazione.

## Installare EasyTrack

1. Completa il setup ufficiale e verifica che SideStore riesca a rinnovare la propria firma.
2. Trasferisci l’IPA EasyTrack in una posizione di File accessibile sull’iPhone.
3. Nella pagina **My Apps** di SideStore usa il comando di aggiunta/importazione, seleziona l’IPA e completa la firma con l’account Apple configurato.
4. Apri EasyTrack almeno una volta. Per l’inglese scegli **Impostazioni → Lingua → English**.
5. Crea un conto, eventualmente registra un movimento fittizio di prova e verifica che EasyTrack compaia tra le app attive di SideStore.

Con account gratuito SideStore indica un limite di tre app attive, compreso SideStore, oltre ai limiti sugli App ID. Consulta le [FAQ ufficiali](https://docs.sidestore.io/it/docs/faq) per le condizioni attuali.

## Rinnovo e aggiornamento sono operazioni diverse

Il **rinnovo / refresh** estende la validità della firma della build installata. Con firma gratuita va effettuato prima della scadenza dei sette giorni. Controlla tempo residuo ed esito in SideStore: il rinnovo in background non è garantito. Usa rete e VPN locale richieste dalla tua versione. L’uso ordinario del registro EasyTrack non richiede la VPN per la firma né Xcode aperto.

L’**aggiornamento** installa una nuova build EasyTrack da un altro IPA. Il solo rinnovo non scarica e non compila nuovo codice EasyTrack.

## Aggiornare un registro esistente

1. Esporta dall’EasyTrack installato un [backup JSON](BACKUP_RESTORE.md) aggiornato, in File **fuori dalla cartella dell’app**. Verifica che sia presente e leggibile.
2. Ottieni il nuovo IPA. I pacchetti compilati dal repository mantengono l’identificatore originale `local.easytrack.finance`.
3. Usa la stessa installazione SideStore, lo stesso account Apple e la stessa identità dell’app. Importa il pacchetto **sopra EasyTrack già presente**. Non disinstallare prima e non modificare l’identità per creare una seconda app.
4. Apri EasyTrack e controlla alcuni movimenti, conti e totali. Conserva il backup fino alla fine della verifica.
5. Se usi Comandi Rapidi, verifica che l’azione punti all’installazione corretta e prova la cattura con dati fittizi.

Il solo bundle ID originale non è una garanzia: gli strumenti di firma possono riscriverlo e un’identità di firma diversa può produrre un’installazione separata. Se compaiono due icone o un’app con registro vuoto, evita eliminazioni e sostituzioni. Conserva l’installazione con i dati, esportali e usa [backup e ripristino](BACKUP_RESTORE.md) per trasferirli consapevolmente.

## Risoluzione dei problemi

| Sintomo | Controllo |
| --- | --- |
| EasyTrack non si apre più | Controlla scadenza ed esito del rinnovo in SideStore. Non disinstallare l’app con il registro. |
| Rinnovo fallito | Controlla rete, VPN locale, abbinamento e account nella [guida SideStore](https://docs.sidestore.io/it/docs/troubleshooting). L’abbinamento può richiedere un rinnovo dopo aggiornamento o ripristino del dispositivo. |
| App assente dalle app attive | Verifica il completamento dell’installazione; un’app separata installata con Xcode non è necessariamente gestita da SideStore. |
| Registro vuoto dopo aggiornamento | Cerca una seconda identità dell’app; esporta dall’originale prima di scegliere dove ripristinare. |
| Azione assente da Comandi Rapidi | Apri l’app firmata, riapri Comandi Rapidi e consulta la [guida notifiche](SHORTCUTS_SETUP.md). |

Mantieni separati IPA e backup finanziari. Verifiche su dispositivo e punti ancora da controllare sono raccolti nella [issue #8](https://github.com/Natizh/EasyTrack/issues/8).

La issue #8 registra verifiche riferite dall’utente su installazione e conservazione dei dati nell’aggiornamento, e la successiva risoluzione della visibilità in My Apps. Queste segnalazioni non completano la checklist: rinnovi successivi e affidabilità delle notifiche richiedono prove specifiche.
