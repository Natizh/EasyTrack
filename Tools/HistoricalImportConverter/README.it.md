# Convertitore di importazione storica

[EasyTrack](../../README.it.md) · [English](README.md) / [Italiano](README.it.md)

Questo strumento locale e deterministico converte un XLSX mappato in un seed SQLite EasyTrack. Usa solo la libreria standard Python, non modifica il foglio e non indovina una struttura sconosciuta.

Per iniziare usa [esempio a foglio unico e guida passo passo](../../docs/it/EXCEL_IMPORT.md). Per uno storico più complesso:

1. Copia `mapping.example.json` fuori dal repository e adatta nomi dei fogli e intestazioni.
2. Mantieni un ID sorgente stabile per ogni movimento. Se manca, configura `stable_id.fields` con campi immutabili e verifica collisioni prima dell’import.
3. Dichiara `date_system` (`1900` o `1904`) e `source_timezone` per ogni foglio. Le date con offset vengono convertite in `Europe/Rome`; quelle senza usano il fuso dichiarato.
4. Esegui dalla radice:

```sh
python3 Tools/HistoricalImportConverter/convert_xlsx.py   --input /explicit/path/history.xlsx   --mapping /explicit/path/private-mapping.json   --output /explicit/path/history-seed.sqlite
```

Il rapporto `*-import-audit.txt` contiene diagnostica privata ed è ignorato da Git. Controlla ogni avviso prima di selezionare il seed nell’app. Una formula viene usata solo se il foglio contiene un risultato già calcolato; formule e celle originali restano nel JSON di provenienza. Il foglio rimane il riferimento per formati, formule e informazioni non rappresentate dalla mappatura.

Usa `--replace-output` soltanto per sostituire un seed generato in precedenza. Il file XLSX sorgente non viene mai sostituito.
