# MangaCat — Complete Product & Technical Specification

**Version:** 1.0 | **Date:** 2026-10-14 | **Status:** Approved for build
**Platform:** Android only (minSdk 26) | **Connectivity:** Fully offline (no INTERNET permission)

---

## 1. Product Overview

**Name:** MangaCat (short for *Manga Catalogue*)

**One-line summary:** A fast, private, offline personal series tracker that answers *"have I read this already?"* in under two seconds, with batch tools for cataloguing an archive folder, backed by plain CSV files the user fully owns.

**Core promise:** Paste a title → instantly know if it's in your list → one tap to add it. That's the heartbeat of the app; everything else serves it.

**Design philosophy:**
1. **Answer-first** — the app exists to answer "read already?" as fast as possible.
2. **Tracker UX, never CSV UX** — CSV is the storage format, never the interface. The app looks and behaves like a weeb catalogue tool, not a spreadsheet.
3. **User owns the data** — plain readable CSV, user-chosen location, no lock-in, no accounts.
4. **Discreet by default** — PIN on every launch, manga-framed, and the artist/circle column supports h-doujinshi tracking without the app ever calling attention to it.

---

## 2. Goals & Non-Goals

**Goals**
- Answer "is this in my list?" in < 2 seconds (paste → verdict).
- Log finished titles with minimal friction (batch paste workflow).
- Bulk-catalogue a sorted archive folder (folders + CBZ files → entries, with preview and duplicate handling).
- Keep data in a strict, human-readable CSV the user can hand-edit on PC; app detects external edits.
- Multiple independent lists (one CSV each), each with its own fast SQLite workspace.
- Full audit history of every change, with restore of deleted entries.

**Non-goals (explicitly out of scope)**
- No cloud sync, no accounts, no analytics, no crash reporting.
- No INTERNET permission at all.
- No file/folder deletion from storage — the app only ever edits *list entries*.
- No genre tags, no recommendations, no cover art fetching.
- No light theme (dark only), no iOS/desktop/web builds.
- No chapter-level auto-tracking (progress is free text; auto chapter tracking is a possible v2 discussion only).
- Not a generic CSV editor — the tracker schema is the product; foreign CSV columns are warned about, not edited.

---

## 3. Personas & Primary Use Cases

**Primary persona — the Archivist.** Organizes a local manga/doujinshi archive in batches: sorts files into folders, scans the folder into the app, records what's read, deletes files manually outside the app. Needs speed, bulk tools, and a list they can trust.

**Secondary persona — the Casual Tracker.** Just wants "did I finish this?" before starting a new series. Uses search + add almost exclusively.

| ID | Use case | Main flow |
|---|---|---|
| UC-01 | Quick read-check | Open app (PIN) → paste title → see match/not → optionally add |
| UC-02 | Batch archive scan | Tracker → Scan folder → pick directory → preview checkbox list → resolve duplicates → import → undo if wrong |
| UC-03 | Edit an entry | Tap row → detail sheet → change fields → autosaved to workspace |
| UC-04 | Manage multiple lists | Home screen lists all CSVs with counts → tap to switch |
| UC-05 | Hand-edit on PC | Edit CSV on PC → return to app → app detects change on focus → reload dialog (external wins) |
| UC-06 | Recover a mistake | Snackbar Undo (1 step) for anything; History screen restores deleted entries |

---

## 4. Definitions

- **List** — one CSV file; a named collection of entries.
- **Entry** — one row: a series title + metadata.
- **Workspace** — the per-list SQLite database the app actually edits. CSV is the export/save format.
- **"Read"** — user-toggleable definition in search filter chip: *Completed only* (default) or *anything except Planned*.
- **Dirty state** — workspace has changes not yet written to CSV. Shown as a dot/badge on the app bar.
- **Normalization** — for matching only: casefold + trim + collapse internal whitespace. Storage is always raw.

---

## 5. Data Model

### 5.1 Entry schema

| Field | Type | Req. | Simple mode | Notes |
|---|---|---|---|---|
| `id` | positive int | yes | CSV col 1 | Auto-assigned `max(id)+1`; never reused; displayed by default (toggleable) |
| `title` | string | yes | CSV col 2 | Free text |
| `artist` | string | no | CSV col 3 | Empty shown as "—" |
| `status` | enum | no | advanced only | `none` (default) / `reading` / `completed` / `planned` / `dropped` |
| `rating` | int 0–5 | no | advanced only | 0 = unrated |
| `progress` | free text ≤ 40 chars | no | advanced only | e.g. "ch. 143", "Vol 7" |
| `notes` | free text ≤ 500 chars | no | advanced only | |

### 5.2 CSV format (normative)

- UTF-8, comma-delimited, **RFC 4180 quoting** (handles titles containing commas), header row **required**.
- Header: `id,title,artist` (simple) or `id,title,artist,status,rating,progress,notes` (advanced).
- Rows written sorted by `id` ascending; line endings CRLF (parser also accepts LF).
- **Strict dialect:** comma only, semicolon/tab files are rejected with a clear error.
- **Toggling advanced mode rewrites the CSV on next Save.** Toggling OFF removes advanced columns from the CSV but keeps the data in the workspace; a warning dialog states this. Re-enabling brings the data back into the CSV.
- Unparseable rows → load continues, user warned with line numbers (rows skipped).

**Example (advanced):**
```csv
id,title,artist,status,rating,progress,notes
1,"Solo Leveling",,completed,5,,
2,"Frieren: Beyond Journey's End",Kanehito Yamada,completed,5,,
3,"Bocchi the Rock!",,reading,4,ch. 60,
```

### 5.3 SQLite workspace (one per list)

File: `databases/<sha256(uri)>.db` in internal storage.

- `entries(id PK, title, artist, status, rating, progress, notes, created_at, updated_at)`
- `audit_log(seq PK AUTOINCREMENT, ts, action, entry_id, snapshot_json, summary)` — FIFO, last 500 entries
- `meta(key, value)` — `source_uri`, `display_name`, `advanced_mode`, `last_saved_hash`, `last_saved_size`, `last_saved_mtime`, `show_id`, `sort_pref`

### 5.4 Multi-file model

Each CSV opens/creates its own workspace. Recent lists (URI, name, cached entry count, last opened) stored in SharedPreferences. URIs held via Android SAF persistable permission.

---

## 6. Architecture & Data Lifecycle

```
UI screens/widgets
   → State layer (Riverpod providers: currentList, settings, dirtyFlag)
   → Repository (workspace ops + audit + undo stack + fingerprinting)
   → Storage: Sqflite workspace | CsvCodec (csv pkg) | SafGateway (SAF URIs)
```

**Lifecycle:**
1. **Open:** resolve URI → open/create workspace → parse CSV → load into `entries` → record fingerprint.
2. **Edit:** every mutation writes to the workspace immediately (autosave), marks dirty, writes an audit entry, pushes an undo snapshot.
3. **Save to CSV:** serialize (sorted by id, header per current mode) → write via SAF truncate → clear dirty → toast "Saved to <file>".
4. **External change detection:** on app resume, hash the CSV contents and compare against `last_saved_hash` in meta (size and mtime from some providers are stale after out-of-band edits, so the hash is authoritative; size+mtime remain a fallback for pre-hash workspaces). If changed → dialog: *"The CSV changed outside the app."* **[Load file]** (default, discards unsaved workspace edits — external wins) / **[Keep my edits]**.

---

## 7. Feature Specifications

### 7.1 PIN lock
- Numeric PIN, 4–6 digits, set on first launch (before anything else).
- Stored as salted PBKDF2-SHA256 hash (100k iterations) in SharedPreferences. No fingerprint.
- Required on **every cold launch**. Optional setting: also re-lock when returning from background.
- Wrong PIN → red shake + error text. 5 failures → 30 s cooldown.
- No recovery mechanism; forgotten PIN means reinstall (CSV files themselves are safe).

### 7.2 Home — File Library
- Vertical list of all opened lists: file name, entry count, last-opened date, dirty badge.
- Top card: **Continue** (most recent list, one tap).
- FAB `+` → SAF picker → open existing CSV *or* create new (writes header-only CSV at chosen location).
- First launch (no last file) lands here. Afterwards the app opens the last-used list directly; Home is reachable via back/drawer.
- Long-press a list → remove from recents (workspace kept; confirm dialog). Never deletes the CSV.

### 7.3 Tracker screen (the core)

**App bar:** file name + dirty badge; a Save icon appears whenever there are
unsaved changes; the overflow opens a grouped **List menu** (bottom sheet):
*Data* (Save to CSV with state subtitle, Scan folder), *Display* (Filters with
an active-filter summary, Sort with the current choice, Show ID switch), *More*
(History, List settings).

**Body:**
- **Search bar** at top (autofocus on open, setting-toggleable). Debounce 150 ms. Matches `title` **and** `artist`, normalized (casefold/trim/collapse).
- **Filter chips row:** status filter; "Read = Completed only / any except Planned" toggle chip.
- **List rows:** `[id]` · Title — artist (secondary line) · status dot · compact rating stars (advanced only). Tap → detail sheet.
- **Suggestion area:** matches under "In your list"; pinned action row at bottom: **＋ Add "<query>"**.
- **Fast scroll:** a draggable scrollbar thumb on the right edge jumps through
  long lists; the list stays lazy, no pagination needed at spec scale.
- **Add flow:** tap Add → bottom sheet (title prefilled) → artist field (skippable — used because same title exists from different artists) → quick status chips → Save → **search field clears, keyboard stays up** → snackbar "Added '<title>'" with **Undo**. Optimized for rapid paste-add-paste-add batches.
- **Row gestures:** swipe right = toggle completed; swipe left = delete (no confirm; Undo snackbar covers it). Long-press = multi-select → batch delete / batch set status.
- **Pull-to-refresh:** re-check file fingerprint.
- **Empty states:** no entries → illustration + "Add your first title"; no matches → only the Add row shows.

### 7.4 Entry detail / edit
- Large bottom sheet: all fields for current mode (status selector, 1–5 star rating, progress, notes).
- Shows created/updated timestamps. Delete button (red) with Undo via snackbar.
- All saves go straight to workspace (autosave). No Save button.

### 7.5 Batch scan
1. Tracker → **List menu** → Scan folder → SAF directory picker (one level deep; user pre-sorts the folder).
2. Candidates: each immediate **subfolder** + each file matching configured extensions (default: `cbz`; configurable in Settings). Name = raw folder name / file name without extension.
3. **Preview screen:** alphabetical, checkbox per item (all pre-checked), items already in the list tagged "in list" (normalized exact title match) with a "hide duplicates" toggle.
4. Import: if selected items include existing titles → dialog *"N selected items already exist. Add anyway / Skip them."*
5. Result: snackbar "Added X · Skipped Y" with **Undo** (whole batch = one undo step).
6. Audit: one `BATCH_ADD` entry recording every item (enables per-item restore).

### 7.6 History (audit log)
- Reverse-chronological list: action icon, timestamp, one-line summary ("Added 'X' (#142)").
- **Delete entries show a Restore action** — re-adds with original id if free, else new id. Edits/adds are informational only (no full rollback; that's what Undo is for).
- Filter by action; "Clear log" with confirm; 500-entry FIFO retention.

### 7.7 Settings
- **Global:** change PIN, re-lock on background toggle, scan extensions, about/version.
- **Per list (List menu → List settings):** advanced mode toggle (with warning dialog, both directions), show ID, default sort, default filter.

### 7.8 Save to CSV
- No confirmation; idempotent. Success → toast, dirty badge clears.
- Failure (file moved/permission lost) → error dialog offering to re-pick the file or remove from recents.

---

## 8. Visual Design System (dark only)

**Palette** (n-inspired: near-black base, magenta accent, white type):

| Token | Hex | Use |
|---|---|---|
| Background | `#17171B` | App scaffold |
| Surface | `#1F1F24` | Cards, sheets |
| Surface variant | `#26262C` | Chips, pressed |
| Accent | `#E84E8A` | FAB, primary buttons, active states |
| Accent press | `#F06A9C` | |
| Text primary | `#F4F4F5` | |
| Text secondary | `#A0A0AA` | Captions, artist line |
| Status: Reading | `#E84E8A` | |
| Status: Completed | `#4CC38A` | |
| Status: Planned | `#8B8B94` | |
| Status: Dropped | `#E05E5E` | |

**Typography:** Inter or Roboto — titles 20/600, body 15/400, caption 12/500.
**Shape:** 4 pt grid; cards/sheets radius 12, chips radius 8; list row height 64.
**Icons:** Material Symbols rounded.
**Motion:** 150–250 ms, standard emphasized easing; PIN error shake.
**Weeb flavor, restrained:** accent-driven identity, cat silhouette in logo/empty states, "Catalogue" copy. No gratuitous Japanese text; at most a faint カタログ watermark on Home.

---

## 9. Security & Privacy

- `AndroidManifest.xml` declares **no INTERNET permission** — offline is provable, not promised.
- PIN: salted PBKDF2-SHA256, 100k iterations, per-install salt.
- Workspaces live in app-internal storage (unreadable without root).
- SAF persistable URI permissions only; no broad storage permission.
- Zero telemetry, zero third-party SDKs that phone home.

---

## 10. Error Handling Matrix

| Scenario | Detection | Behavior |
|---|---|---|
| Malformed CSV row | Parse | Skip row, warn with line numbers after load |
| Wrong delimiter file | Header sniff | Reject: "Not a valid MangaCat CSV" |
| Unknown extra columns | Header vs schema | Load known columns, warn that extras are ignored |
| CSV edited on PC while open | Content fingerprint on resume | Dialog; Load file (default) / Keep my edits |
| CSV deleted/moved externally | SAF resolution fail on save | Error dialog → re-pick or remove from recents |
| Corrupt workspace | DB open failure | Rebuild from CSV, warn "Local history was reset" |
| Duplicate id in CSV | Parse | Reassign next free id, warn |
| Scan permission lost | SAF | Prompt to re-grant folder |

---

## 11. Locked-In Decisions Log (from "whatever is best" rounds)

1. **Workspace persistence:** SQLite db persists per list; autosave on every edit; CSV save is manual via "Save to CSV".
2. **Conflict:** external CSV change wins by default; dialog still offered when unsaved edits exist.
3. **Advanced toggle-off:** hides advanced columns from CSV, preserves data in workspace.
4. **Duplicates:** adding case-variant titles is *allowed* (no blocking); batch scan asks instead.
5. **Undo:** one step, session-wide, snackbar-based; works after CSV save (undo touches workspace only).
6. **Quick-add:** artist asked at add-time via sheet, with explicit Skip.
7. **Multi-file:** Home library + auto-open last list; new file via FAB.
8. **Progress:** free text.
9. **Search "read" definition:** filter chip on tracker (Completed-only default).
10. **First launch:** PIN setup → Home → open/create CSV.

---

## 12. Performance Targets

- Cold launch → PIN < 1.5 s; PIN accept → list visible < 500 ms @ 5,000 entries.
- Search keystroke → rendered results < 100 ms @ 5,000 (in-memory list + debounce).
- Save-to-CSV < 1 s @ 5,000 entries. Scan of 2,000 folders < 3 s.

---

## 13. Technical Stack & Project Structure

- **Flutter (stable channel), Dart**, single-module app.
- State: **flutter_riverpod** | DB: **sqflite** + `path` | CSV: **csv** | Settings/recents: **shared_preferences** | SAF: **saf / shared_storage** | PIN hash: **crypto** | Dates: **intl**.
- Suggested package: `ph.smolfiddle.mangacat`.

```
lib/
  main.dart, app.dart
  core/ (theme, constants, result types)
  data/ (models/, db/, csv_codec.dart, saf_gateway.dart, fingerprint.dart)
  features/
    pin/ (lock screen, setup)
    home/ (library)
    tracker/ (list, search, add sheet, detail sheet, filters)
    scan/ (picker, preview, import)
    history/ (audit log)
    settings/
```

---

## 14. Acceptance Criteria (v1.0)

1. Fresh install → PIN setup → Home → open a CSV → entries visible.
2. Paste a title → see match or Add row → add with artist → snackbar Undo → Undo removes it.
3. Toggle completed via swipe; kill app; relaunch → state persists (workspace).
4. Dirty badge appears after edit; Save to CSV writes file verifiable on PC; badge clears.
5. Edit CSV on PC (add a row) → return to app → reload dialog → Load file → new row appears.
6. Scan a folder of 10 folders + CBZ files → preview → exclude 2 → import → 8 entries, correct names.
7. Duplicate scan selection → dialog offers Add anyway / Skip.
8. Delete an entry → restore it from History.
9. Toggle advanced mode → CSV gains columns on save; toggle off → columns gone, data returns on re-enable.
10. APK manifest contains zero `android.permission` network entries.

---

## 15. Roadmap

- **v1.0:** everything in §14 (PIN, library, tracker, add/edit/delete, undo, save-to-CSV, history, settings, scan).
- **v1.1:** list stats ("47 completed · 12 reading"), rating-based sort, per-list accent tint, CSV "Save a copy" export.
- **v2 (discussion only):** chapter progress with quick +1, cover thumbnails from local files, optional backup reminder.

---

*End of specification. Approved for build.*
