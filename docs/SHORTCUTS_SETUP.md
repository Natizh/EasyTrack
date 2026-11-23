# Configurare le notifiche con Comandi Rapidi / Set up notifications with Shortcuts

Questa guida parte da zero. EasyTrack **non legge direttamente tutte le notifiche** delle altre app: un'automazione personale di Apple **Comandi Rapidi / Shortcuts** deve ricevere la notifica di un'app scelta da te e passarne i campi all'azione EasyTrack. Il trigger, i campi disponibili e l'esecuzione a schermo bloccato dipendono da iOS e dall'app selezionata. Una notifica catturata **non è ancora un movimento finanziario**.

Tutti i nomi, i messaggi e gli importi di esempio qui sotto sono inventati. Non inserire password, numeri di carta o codici OTP nella sorgente, nei test o in una issue pubblica.

```text
App scelta nel trigger → Notifica → azione EasyTrack → Notifiche catturate
                                                    → formato approvato → Attività
```

## 1. Preparare la sorgente in EasyTrack

1. Installa e apri EasyTrack almeno una volta. In **Impostazioni / Settings → Conti / Accounts**, crea o scegli il conto locale a cui attribuire i movimenti di questa sorgente. EasyTrack non chiede credenziali bancarie.
2. Apri **Automazioni / Automations → Notification setup**. Nel primo riquadro scegli **EasyTrack account** e scrivi una **Source app label** stabile, per esempio `Northstar Pay (fictional)`; premi **Save source and account**, poi **Copy name**. Copia il nome *esattamente*, inclusi spazi e maiuscole. Questa etichetta identifica la sorgente dentro EasyTrack; non sceglie un'app installata sul telefono.
3. Una sorgente EasyTrack è collegata a un solo conto e può avere più formati, per esempio uno per pagamenti in uscita e uno per accrediti. Il formato riconosce il messaggio; non assegna automaticamente una categoria. Se hai più conti, verifica quello corretto prima di continuare.

Se non vedi un conto selezionabile, torna a **Accounts** e creane uno. Se cambi in seguito la mappatura della sorgente, i movimenti già salvati conservano il conto originale.

## 2. Scegliere l'app nel trigger di Comandi Rapidi

1. Apri **Comandi Rapidi / Shortcuts** sull'iPhone e vai alla scheda **Automazione / Automation**. Tocca **+** o **Nuova automazione / New Automation**. Su alcune versioni di iOS il pulsante apre prima l'editor di un comando: in tal caso torna alla scheda Automazione oppure apri il comando e scegli **Modifica / Edit → Automazione / Automation**.
2. Scegli il trigger **Notifica / Notification**, poi **App** o **Quando ricevo una notifica da**. Qui seleziona **l'app reale che invia la notifica**, installata sul tuo iPhone. Nel nostro esempio immaginario sarebbe l'app `Northstar Pay`; nella configurazione reale scegli la tua app effettiva. Questa scelta è diversa dalla *Source app label* salvata in EasyTrack.
3. All'inizio non impostare filtri stretti su **Titolo / Title**, **Sottotitolo / Subtitle** o **Messaggio / Message**: sono filtri del *trigger*, non i valori da passare all'azione. Una condizione troppo specifica può impedire l'avvio per un pagamento valido. Potrai restringerla dopo aver visto un campione innocuo.
4. Se la tua versione di iOS offre l'esecuzione automatica o il permesso di eseguire a schermo bloccato, abilitala solo dopo aver letto la schermata e concesso i permessi richiesti. Le opzioni cambiano fra versioni e trigger; EasyTrack non può attivarle al tuo posto né garantire l'esecuzione automatica.

La [guida Apple ai trigger](https://support.apple.com/guide/shortcuts/apd932ff833f/ios) distingue la scelta dell'app dai filtri sui campi. La [guida Apple alle automazioni](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios) mostra la procedura generale; i nomi e l'ordine dei pulsanti possono cambiare con iOS.

## 3. Aggiungere l'azione EasyTrack

Nell'editor dell'automazione scegli **Aggiungi azione / Add Action**, cerca **EasyTrack** nella sezione App o nella ricerca e aggiungi **Capture Payment Notification**. Il riepilogo dell'azione può comparire come **Capture notification from [source]**.

Nel parametro **Source app** incolla l'etichetta fissa copiata da EasyTrack, per esempio `Northstar Pay (fictional)`. **Non** scegliere qui la variabile magica `Notifica`: il testo deve corrispondere alla sorgente salvata. L'app selezionata nel trigger, l'etichetta della sorgente e il conto EasyTrack sono tre cose distinte.

Se l'azione EasyTrack non compare, apri EasyTrack una volta, riapri Comandi Rapidi e controlla che l'installazione sia disponibile e attendibile. Se usi SideStore, controlla la firma e il rinnovo dell'app **senza disinstallare l'installazione che contiene i dati**; conserva prima un backup JSON esterno.

## 4. Collegare quattro proprietà dinamiche

Per ogni parametro dell'azione tocca **il valore**, non il nome del campo. Scegli la variabile blu **🔔 Notifica** prodotta dal trigger; poi tocca **il chip blu appena inserito** per aprire il menu **Ottieni / Get** e seleziona la proprietà specifica. Ripeti la scelta separatamente per ogni campo.

| Campo nell'azione EasyTrack | Variabile del trigger | Proprietà da scegliere nel chip blu |
| --- | --- | --- |
| **Title** | `Notifica` | **Titolo** |
| **Subtitle** | `Notifica` | **Sottotitolo**; può essere vuoto per alcune notifiche |
| **Message** | `Notifica` | **Corpo**; di solito contiene importo e descrizione |
| **Notification date** | `Notifica` | **Data**, *solo se Shortcuts offre un valore realmente di tipo Data/Date* |

Riepilogo: **Title = `Notifica → Titolo`**, **Subtitle = `Notifica → Sottotitolo`**, **Message = `Notifica → Corpo`**, **Notification date = `Notifica → Data`** quando il valore è di tipo Data.

Esempio visivo del passaggio: `Title: [🔔 Notifica]` → tocca il chip → **Ottieni: Titolo** → `Title: [🔔 Titolo]`. Un chip che rimane sulla notifica intera non ha ancora la proprietà giusta. Non scrivere `Title`, `Message`, `€12,34` o altri valori di esempio come testo fisso nell'automazione di produzione: verrebbero inviati identici ogni volta.

Per **Notification date**, il selettore iOS può mostrare **Formato data: Intermedio** e **Formato ora: Intermedio** con un'anteprima simile a `15 set 2026, 09:41:00`. È soltanto un'anteprima di presentazione: **non dimostra** che l'App Intent riceva un valore `Date`. Se la proprietà manca o non è compatibile, lascia vuoto il campo facoltativo; EasyTrack userà l'istante della cattura. Non digitare una data localizzata a mano.

## 5. Salvare e verificare i tre passaggi distinti

1. Salva l'automazione in Comandi Rapidi. Se vuoi controllare solo che l'azione EasyTrack sia raggiungibile, puoi eseguire un test manuale con testi **fittizi**, per esempio `Card purchase` e `Paid €12,34 at Cedar Books`. Questo prova l'ingresso nell'App Intent, **non** il trigger della notifica né i chip dinamici.
2. Per verificare il trigger, provoca una **notifica innocua che controlli tu** dall'app selezionata, se l'app lo consente. Apri **EasyTrack → Automations → [sorgente] → Captured notifications**. Controlla che Titolo e Corpo riflettano il nuovo evento. Due notifiche innocue con testi diversi sono utili per scoprire un valore fisso inserito per errore. Se Sottotitolo è vuoto, può essere normale. Non pubblicare il testo della notifica.
3. **Cattura ≠ formato ≠ movimento.** Una cattura prova che qualcosa è arrivato all'App Intent. Solo un formato approvato può proporre un movimento. Infine controlla in **Activity / Attività** che un evento finanziario reale, verificato da te, sia comparso una sola volta e sul conto giusto. Confronta i movimenti con la fonte originale: iOS o Comandi Rapidi possono non consegnare tutti gli eventi.

Un test su simulatore o un test manuale dell'azione non prova il comportamento di notifiche bancarie reali, a schermo bloccato o con EasyTrack sospesa. Ripeti le verifiche su un iPhone fisico, dopo il rilancio dell'app e con eventi ripetuti, senza registrare testi privati nei log.

## 6. Approvare il formato dopo la prima cattura

In **Automations → [sorgente] → Captured notifications**, tocca il campione e scegli **Set up format** oppure **Add notification format**. Se la sorgente non ha un formato valido, Home di Automations mostra anche **Set up this sample**. Il configuratore usa sette blocchi: input, sorgente/conto, direzione/tipo, importo, descrizione, protezione duplicati e creazione del movimento.

Verifica con il testo fittizio `Paid €12,34 at Cedar Books` che il parser trovi **€12,34**, descriva **Cedar Books**, proponga una **spesa** e usi il conto previsto. Controlla una notifica promozionale o OTP fittizia: non deve creare una spesa. Usa **Test automation** nel configuratore, poi approva esplicitamente il formato. Puoi scegliere **Create first transaction** soltanto se il campione è un vero pagamento controllato, oppure **Activate without adding sample** per un test o un evento non finanziario. Non creare manualmente una seconda copia di un movimento già salvato.

Un'app può inviare messaggi in entrata e in uscita con strutture diverse: crea formati distinti se necessario. Se l'importo non è in EUR o non è verificabile, EasyTrack non deve inventare una conversione. Le catture non riconosciute restano diagnostiche; i testi grezzi seguono il periodo di conservazione configurabile e vengono eliminati alla prossima occasione di pulizia, non necessariamente mentre l'app è chiusa. Puoi eliminare singoli campioni senza cancellare i movimenti già registrati.

## Troubleshooting / Risoluzione dei problemi

| Cosa vedi | Controllo concreto |
| --- | --- |
| L'app bancaria non compare in **Notifica → App** | Verifica che sia installata su questo iPhone e che invii notifiche. EasyTrack non può selezionarla da remoto. |
| L'azione EasyTrack non compare in **Aggiungi azione** | Apri EasyTrack, poi riavvia Comandi Rapidi. Controlla disponibilità e firma dell'installazione SideStore; non eliminare l'app con il database. |
| Nessuna cattura | Verifica automazione abilitata, app corretta nel trigger, permessi e filtri del trigger. Esegui prima un test manuale dell'azione, poi una notifica reale innocua. Se manca solo a schermo bloccato, controlla le opzioni iOS disponibili: EasyTrack non può imporre la consegna. |
| **Captured · 0 active** | Il campione è arrivato ma non esiste ancora un formato attivo. Apri la sorgente e configura il campione; non attribuire subito il problema a privacy o conservazione. |
| **Untitled notification** | Tocca il valore di **Title**, poi il chip blu `Notifica` e scegli **Titolo**. Controlla anche che quella notifica abbia un titolo. |
| **No text in selected field** | Il chip può puntare alla proprietà sbagliata, oppure la notifica non contiene un sottotitolo. Prova **Corpo** per **Message**; un campo facoltativo vuoto non dimostra un blocco di sicurezza. |
| **No EUR amount found** | Verifica prima **Message → Notifica → Corpo**; poi confronta la struttura del campione con i prefissi/suffissi dell'importo nel formato. Nessuna spesa viene creata con importo indovinato. |
| La sorgente non è riconosciuta o non ha conto | **Source app** deve essere il nome fisso esatto salvato in EasyTrack. Salva anche la mappatura a un conto attivo nella guida di configurazione. |
| Valori identici a ogni notifica | Hai probabilmente digitato testo statico. Sostituiscilo con quattro chip dinamici e verifica due eventi diversi. |
| **Duplicate skipped** o movimento già presente | Apri lo stato diagnostico e il movimento in Activity prima di aggiungerne uno manualmente. La protezione duplicati evita una seconda registrazione dello stesso evento. |
| Cattura presente ma nessun movimento | Controlla formato attivo, direzione, importo, descrizione e stato di rifiuto/ambiguità. Una promozione o un OTP devono restare fuori dal registro. |
| **Notification date** non funziona | Lascia vuoto il campo se non è disponibile una proprietà Data compatibile: l'azione usa il timestamp di cattura. L'anteprima formattata del selettore non è una prova. |

Per una verifica completa su iPhone fisico restano aperte [#8](https://github.com/Natizh/EasyTrack/issues/8), [#13](https://github.com/Natizh/EasyTrack/issues/13) e [#31](https://github.com/Natizh/EasyTrack/issues/31). Non allegare a quelle issue notifiche reali, screenshot bancari, codici o importi personali: usa solo dati sintetici e conteggi privi di testo sensibile.
