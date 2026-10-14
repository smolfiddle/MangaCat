# MangaCat

**MangaCat** (short for *Manga Catalogue*) is a fast, private, fully offline
series tracker for Android. It answers one question in under two seconds —
**"have I read this already?"** — and then gets out of the way. Paste a title,
see whether it is in your list, and add it with one tap.

All data lives in plain CSV files that you choose and own. There is no account,
no cloud sync, and no network permission in the release build.

- **Platform:** Android only (minSdk 26, Android 8.0+; targets API 36)
- **Connectivity:** none — the release manifest declares zero network permissions
- **Version:** 0.0.1
- **Package:** `ph.smolfiddle.mangacat`
- **Full specification:** [`MangaCat_Specification.md`](MangaCat_Specification.md)

---

## Why it exists

Most trackers are either online services or spreadsheet-shaped apps. MangaCat
takes a different position:

1. **Answer-first.** The app exists to answer "read already?" as fast as
   possible. Search opens focused, results are filtered in memory, and the add
   row is always one tap away.
2. **Tracker UX, never CSV UX.** CSV is the storage format, not the interface.
3. **The user owns the data.** Plain, human-readable CSV at a location you
   pick; editable on a PC; no lock-in.
4. **Discreet by default.** A PIN gate on every cold launch and an
   `artist` column that happily carries artist, studio, or circle names.

---

## Features

### Fast checks (the heartbeat)

- **Paste-to-verdict search.** Autofocus, 150 ms debounce, matching on title
  and artist with normalization (casefold, trim, collapsed whitespace).
- **Explicit verdicts.** Matches list under *In your list*; a query with no
  match shows *Not in your list.* plus a pinned **Add "<query>"** button.
- **Quick-add sheet.** Title prefilled, artist/studio/org optional with a
  **Skip** button, quick status chips, and Save. After saving, the search
  clears and the keyboard stays up for the next paste.
- **Every action is undoable.** A snackbar with Undo follows adds, deletes,
  status changes, batch imports, and history restores. Undo is one step,
  session-wide, and works even after saving to CSV because it operates on the
  local workspace.

### Tracking

- **Statuses** — none / reading / completed / planned / dropped, each with a
  distinct color dot.
- **Advanced mode** — per list, adds `status`, `rating` (0–5 stars),
  `progress` (free text, e.g. "ch. 143"), and `notes` columns. Toggling it on
  or off rewrites the CSV on the next save, with a warning dialog; the data
  itself is never lost from the local workspace.
- **Swipe gestures** — swipe left to delete, swipe right to mark completed;
  long-press enters multi-select for batch delete or batch status changes.
  A one-time hint teaches these on first use.
- **Autosave everywhere.** Every edit writes to a per-list SQLite workspace
  immediately. A dot on the app bar (and on the Home tile) shows unsaved
  changes; **Save to CSV** writes the file and clears it.
- **Detail sheet** — full editing with a transient *Saved* indicator,
  timestamps, and a red delete action covered by Undo.

### Cataloguing an archive

- **Scan folder** turns one directory level into entries: each subfolder and
  each file with a configured extension (default `cbz`, configurable) becomes
  a candidate.
- Preview screen: alphabetical, all pre-checked, items already in the list
  tagged, and a *hide duplicates* switch.
- Duplicate selections prompt **Add anyway / Skip them**.
- The whole batch is a single undo step and a single `BATCH_ADD` audit record.

### Lists and storage

- **Multiple independent lists.** Each CSV you open or create gets its own
  workspace keyed by the file's content URI.
- **Home library** shows every list with entry count, last-opened date, and a
  dirty badge, plus a **Continue** card for the most recent one.
- **External edits are detected.** On resume, the file's size and modification
  time are compared against the last saved fingerprint. If the file changed
  and you have unsaved edits, you choose: *Keep my edits* or *Discard edits &
  load file*. Otherwise the changed file loads automatically.
- **Corrupt workspace recovery.** If the SQLite file cannot be opened it is
  rebuilt from the CSV, with a warning that local history was reset.
- Long-press a Home tile to remove it from recents — the workspace is kept and
  the CSV is never deleted or modified by the app outside Save.

### History

- Every add, edit, delete, batch import, and restore is recorded with a
  human-readable summary and timestamp (500-entry FIFO).
- Deleted entries offer a **Restore** action; the original id is reused when
  still free, otherwise the next free id is assigned.
- Filter by action or clear the log; entries themselves are untouched.

### Privacy and security

- **No INTERNET permission** in the main manifest — offline is provable, not
  promised. (Debug and profile builds add it only for Flutter's hot-reload
  tooling; release builds never contain it.)
- **PIN gate** on every cold launch: 4–6 digits, salted PBKDF2-SHA256 with
  100,000 iterations and a per-install random salt. Five wrong attempts start
  a 30-second cooldown. There is no recovery path by design; the CSV files
  themselves are unaffected if the PIN is forgotten.
- Optional re-lock when leaving the app in the background.
- Android auto-backup is disabled, so the PIN hash and workspace never leave
  the device through backup services.
- All file access goes through the Storage Access Framework with persistable
  permissions — no broad storage permission is requested.

---

## The data model

### CSV files (normative format)

UTF-8, comma-delimited, RFC 4180 quoting, header row required, rows sorted by
`id`, CRLF line endings (LF is accepted when reading). The dialect is strict:
semicolon or tab files are rejected with a clear error.

Simple mode:

```csv
id,title,artist
1,"Solo Leveling",
2,"Frieren: Beyond Journey's End",Kanehito Yamada
```

Advanced mode:

```csv
id,title,artist,status,rating,progress,notes
1,"Solo Leveling",,completed,5,,
2,"Frieren: Beyond Journey's End",Kanehito Yamada,reading,4,ch. 93,
```

Reader behavior is deliberately forgiving and loud: malformed rows are
skipped with line numbers, duplicate ids are remapped, unknown columns are
ignored with a warning, over-long fields are truncated to their limits, and
invalid statuses or ratings fall back to defaults. The writer is strict:
sorted, quoted when necessary, CRLF, final newline.

### Per-list workspace

Each opened CSV gets a SQLite database at
`databases/<sha256(uri)>.db` in app-internal storage:

- `entries(id PK, title, artist, status, rating, progress, notes, created_at, updated_at)`
- `audit_log(seq, ts, action, entry_id, snapshot_json, summary)` — FIFO 500
- `meta` — source URI, display name, advanced mode, last-saved fingerprint,
  next id, show-id, sort preference, default filter

Ids are auto-assigned and never reused; `next_id` is persisted so deleting the
highest row cannot cause an id collision later.

External change detection uses size + mtime, treating components the provider
cannot report as "unknown" rather than "changed", which avoids false conflict
dialogs on providers with incomplete stat support.

---

## Architecture

```
UI screens (lib/features)
  → State layer (Riverpod 3 notifiers: pin gate, tracker session, home)
  → Repository (workspace ops, audit, one-step undo, fingerprinting)
  → Storage: Sqflite workspace | CSV codec | SAF MethodChannel (Kotlin)
```

- **State:** `flutter_riverpod` 3.x. A single `TrackerController` owns the
  open list session; UI state (query, filters, selection) is part of its
  immutable state, so filtering and sorting stay testable and in-memory.
- **Storage:** `sqflite` for workspaces, the `csv` package for encode/decode,
  `shared_preferences` for recents and settings.
- **File access:** a small custom Kotlin `MethodChannel` (`mangacat/saf`)
  implements SAF picking, persistable permissions, stat, read/write
  (truncating), and one-level directory listing. I/O runs on a background
  executor; results are posted to the main thread. No third-party storage
  plugin is involved.
- **PIN hashing:** PBKDF2-SHA256 implemented over `package:crypto`, executed
  in an isolate so the UI never blocks.

---

## Project structure

```
lib/
  main.dart, app.dart            # bootstrap, root gate, nested navigator shell
  core/                          # theme, palette, enums, text utils, brand marks
  data/
    models/                      # Entry, AuditRecord, RecentList
    csv_codec.dart               # normative CSV reader/writer
    workspace_db.dart            # sqflite schema and queries
    list_repository.dart         # per-list operations, audit, fingerprints
    saf_gateway.dart             # SAF abstraction + MethodChannel client
    pin_service.dart             # PBKDF2 hashing, lockout state
    recents_store.dart, settings_store.dart, fingerprint.dart
  state/                         # Riverpod notifiers and providers
  features/
    pin/                         # setup, lock screen, keypad
    home/                        # list library
    tracker/                     # core screen, sheets, widgets, dialogs
    scan/                        # folder import preview and import
    history/                     # audit log
    settings/                    # global settings
scripts/
  generate_keystore.sh           # one-time release signing setup
  build_release.sh               # AAB + per-ABI APKs + checksums
test/                            # unit + widget tests
.github/workflows/release.yml    # tag-triggered artifact builds
```

---

## Getting started

Requirements: Flutter stable (developed against 3.41.x / Dart 3.11), Android
SDK with build-tools, JDK 17.

```bash
flutter pub get
flutter run                  # debug on a connected device or emulator
```

Run the checks:

```bash
flutter analyze              # zero-issue policy
flutter test                 # unit + widget suite
```

The test suite covers the CSV codec (quoting, dialects, malformed rows,
duplicate ids, truncation), PBKDF2 against published test vectors, repository
behavior (id assignment, restore, audit retention, conflict-on-open), the
fingerprint comparison rules, and the PIN setup/lock widget flows.

---

## Building for release

Signing is a one-time setup:

```bash
./scripts/generate_keystore.sh
```

This creates `android/keystore/mangacat-release.p12` (PKCS12, 2048-bit RSA,
10,000-day validity) and `android/key.properties` with a random password.
Both files are gitignored. **Back them up somewhere private**: without the
keystore, Android will not accept future updates over an installed copy of the
app, and the only alternative is publishing under a new package name.

Build everything:

```bash
./scripts/build_release.sh
```

Output lands in `dist/mangacat-<version>/`:

| Artifact | Notes |
|---|---|
| `mangacat-<v>.aab` | Play Store upload |
| `mangacat-<v>-arm64-v8a.apk` | modern phones (Android 14 and most devices since 2017) |
| `mangacat-<v>-armeabi-v7a.apk` | older 32-bit devices |
| `mangacat-<v>-x86_64.apk` | emulators, Intel tablets |
| `SHA256SUMS` | checksums for all artifacts |

Notes and options:

- Release builds run R8 with resource shrinking and use per-ABI splits. This
  takes the universal APK from ~56 MB down to ~17–21 MB per device.
- Split APKs receive ABI-specific version codes (Flutter adds offsets such as
  +2000 for arm64) so installs and updates resolve correctly.
- `UNIVERSAL=1 ./scripts/build_release.sh` additionally produces a single
  universal APK.
- `OBFUSCATE=1 ./scripts/build_release.sh` enables Dart obfuscation and
  copies symbol files into `dist/` — keep those files if you ever need to
  symbolicate a stack trace.
- Without `android/key.properties`, release builds fall back to debug signing
  with a printed warning. That build installs and runs, but is only suitable
  for local testing.

### Continuous integration

`.github/workflows/release.yml` builds the same artifacts on `v*` tags or by
manual dispatch. To sign in CI, add repository secrets:

- `KEYSTORE_BASE64` — `base64 -w0 android/keystore/mangacat-release.p12`
- `KEY_PROPERTIES_BASE64` — `base64 -w0 android/key.properties`

When the secrets are absent the workflow still builds, using debug signing.
Artifacts are uploaded; no release is published automatically.

---

## Design system

Dark only, by design. Near-black base (`#17171B`), surface (`#1F1F24`),
magenta accent (`#E84E8A`), status colors for reading/completed/planned/
dropped. 4 pt spacing grid, 12 pt card/sheet radius, 8 pt chip radius, 64 px
list rows, Material Symbols rounded icons, 150–250 ms motion. The restrained
weeb flavor is limited to the cat brand mark and a faint カタログ watermark on
Home. Full token table: specification §8.

---

## Roadmap

- **v1.0 (this codebase, tagged 0.0.1):** everything above — PIN, library,
  tracker, add/edit/delete, undo, save-to-CSV, history, settings, scan.
- **v1.1:** list stats ("47 completed · 12 reading"), rating-based sort,
  per-list accent tint, CSV "Save a copy" export.
- **v2 (discussion only):** chapter progress with quick +1, cover thumbnails
  from local files, optional backup reminder.
