#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .cache/modulecache .build/database-smoke
CLANG_MODULE_CACHE_PATH="$PWD/.cache/modulecache" SWIFT_MODULECACHE_PATH="$PWD/.cache/modulecache" \
  xcrun swiftc -module-cache-path "$PWD/.cache/modulecache" \
  EasyTrack/Shared/Models.swift EasyTrack/Shared/NotificationParser.swift \
  EasyTrack/Shared/DailyModels.swift EasyTrack/Shared/RecurringSchedule.swift EasyTrack/Import/SeedMapper.swift \
  EasyTrack/Persistence/SQLiteDatabase.swift EasyTrack/Persistence/SQLiteDatabase+Daily.swift \
  EasyTrack/Persistence/SQLiteDatabase+Backup.swift EasyTrack/Persistence/LegacyBackupConverter.swift \
  Tests/DatabaseSmoke/main.swift \
  -lsqlite3 -o .build/database-smoke/database-smoke
.build/database-smoke/database-smoke
