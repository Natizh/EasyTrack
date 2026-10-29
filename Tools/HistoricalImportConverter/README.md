# Historical import converter

This local, deterministic tool converts a mapped XLSX workbook into an EasyTrack seed SQLite file. It uses only the Python standard library, never edits the workbook, and does not infer an unknown workbook layout.

1. Copy `mapping.example.json` outside the repository and adapt worksheet/header names to the real workbook.
2. Keep a stable source identifier for every movement. If the workbook has no durable identifier, configure `stable_id.fields` using immutable business fields and review collisions before import.
3. Run:

```sh
python3 Tools/HistoricalImportConverter/convert_xlsx.py \
  --input /explicit/path/history.xlsx \
  --mapping /explicit/path/private-mapping.json \
  --output /explicit/path/history-seed.sqlite
```

The generated `*-import-audit.txt` is private diagnostics and is ignored by Git. Review every warning before selecting the SQLite seed in EasyTrack. A formula is used only when the XLSX contains a cached result; formulas and original cell values remain in provenance JSON. The workbook remains authoritative for formatting, formulas, and information not represented by the mapping.

Use `--replace-output` only to replace a previously generated seed. The source XLSX is never a replacement target.
