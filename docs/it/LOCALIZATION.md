# Lingua dell’app

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/LOCALIZATION.md) / Italiano

EasyTrack si apre in italiano su installazioni nuove o esistenti finché l’utente non sceglie un’altra lingua. **Impostazioni → Lingua / Settings → Language** cambia subito l’interfaccia tra italiano e inglese. La scelta rimane dopo il riavvio e non modifica il registro finanziario.

La preferenza è locale nelle impostazioni, fuori dal database SQLite e dal backup JSON formato 15. Ripristinare un backup su un’installazione esistente mantiene la lingua di quell’installazione. Una nuova parte in italiano, anche ripristinando un backup creato con interfaccia inglese.

Date e importi visualizzati usano le convenzioni della lingua scelta. Gli importi acquisiti e memorizzati restano interi nelle unità minime della valuta. Nomi degli esercenti, descrizioni, conti, categorie personalizzate, etichette sorgente, notifiche originali, regole del parser, codici enum, campi CSV e dati di backup non vengono tradotti. L’App Intent e gli identificatori dei parametri restano stabili per i Comandi Rapidi esistenti; cambiano soltanto le etichette leggibili. Comandi Rapidi può seguire la lingua di sistema: la mappatura delle proprietà resta identica.

Il catalogo `Localizable.xcstrings` contiene le traduzioni dell’interfaccia. `InfoPlist.xcstrings` localizza le spiegazioni dei permessi per fotocamera, microfono e riconoscimento vocale; iOS controlla la lingua del proprio pannello dei permessi. Esegui `python3 scripts/audit_localization.py` per verificare chiavi letterali, ricerche esplicite, copertura italiana e segnaposto di formato.
