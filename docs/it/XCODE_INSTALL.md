# Compilare e installare con Xcode

[EasyTrack](../../README.it.md) · [Documentazione](README.md) · [English](../en/XCODE_INSTALL.md) / Italiano

Usa Xcode per sviluppare EasyTrack, eseguirlo sul simulatore o preparare un IPA non firmato per [SideStore](SIDESTORE_INSTALL.md). Per il rinnovo ordinario della firma su iPhone dopo il setup è consigliato SideStore.

## Requisiti

- Un Mac e **Xcode 26 o successivo**. Il progetto prevede **iOS 17+** e usa API SwiftUI di iOS 26 protette da controlli di disponibilità; versione minima di esecuzione e SDK di compilazione sono requisiti diversi.
- Una versione di macOS supportata dall’Xcode scelto. Consulta la [tabella Apple](https://developer.apple.com/xcode/system-requirements/): non tutte le versioni funzionano sugli stessi Mac.
- Simulatore iPhone e runtime già installati, oppure iPhone con iOS compatibile e firma di sviluppo per l’installazione sul dispositivo.
- Python 3 da riga di comando per validare l’IPA. Lo script di creazione usa `ditto` di macOS.

## Aprire il progetto

```sh
git clone https://github.com/Natizh/EasyTrack.git
cd EasyTrack
open EasyTrack.xcodeproj
```

Seleziona lo schema condiviso **EasyTrack**. Non servono pacchetti esterni per il runtime dell’app.

## Eseguire sul simulatore

Scegli un simulatore iPhone già installato e premi **Run**. Trovi gli UUID con `xcrun simctl list devices available`. Riutilizza un simulatore esistente senza crearne uno nuovo per ogni test. Non serve la firma di un account Apple per compilare sul simulatore.

## Eseguire su iPhone fisico

Seleziona il dispositivo collegato, scegli il team in **Signing & Capabilities**, abilita la modalità sviluppatore quando richiesta e premi **Run**. Il team potrebbe richiedere un bundle ID univoco. Cambiare ID o identità di firma può creare un’installazione separata con database vuoto; non trasferisce lo storico dell’app SideStore.

La firma gratuita Personal Team dura **sette giorni**; rinnovala rifirmando/reinstallando quando necessario ([guida Apple](https://developer.apple.com/help/account/basics/about-your-developer-account/)). Prima di cambiare o rimuovere un’installazione salva un [backup JSON](BACKUP_RESTORE.md) esterno.

## Creare un IPA non firmato

Esegui dalla radice del repository su macOS. Compila una build Release per iPhone fisico, non per simulatore:

```sh
xcodebuild -project EasyTrack.xcodeproj -scheme EasyTrack -configuration Release   -destination 'generic/platform=iOS' -derivedDataPath DerivedData   PRODUCT_BUNDLE_IDENTIFIER=local.easytrack.finance CODE_SIGNING_ALLOWED=NO build
EASYTRACK_IPA_OUTPUT=DerivedData/EasyTrack-0.2-build11-unsigned.ipa   sh scripts/package_unsigned_ipa.sh
```

Il nome d’esempio corrisponde alla versione attuale **0.2 (11)**. Il nome del file non imposta la versione: la definisce `EasyTrack/Info.plist`. Scegli un nuovo nome per ciascun pacchetto; lo script rifiuta di sovrascrivere un IPA esistente.

Lo script valida prima la build Release e poi l’IPA: versione/build rispetto al sorgente, bundle ID originale, piattaforma dispositivo, struttura del pacchetto non firmato, integrità ZIP ed esclusione di database, fogli, backup e file di firma. Questi controlli non sostituiscono i test dell’app.

Se usi una cartella di compilazione diversa, passala con `EASYTRACK_DERIVED_DATA` e imposta un percorso di output corrispondente. Installa l’IPA seguendo la [guida SideStore](SIDESTORE_INSTALL.md). Per aggiornare mantieni l’identità dell’app e della firma; il solo nome del file non garantisce la continuità dei dati.

La guida [Sviluppo](DEVELOPMENT.md) contiene test, organizzazione dei sorgenti e indicazioni per contribuire.
