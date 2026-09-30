# GHIN Golf (offline-first, 100% OSS)

Local-first golf handicap app: WHS engine, score posting, offline GPS
rangefinder, stats, side games. No accounts, no API keys, no quotas.

Course search covers the bundled demo course, any local courses
you add manually, and — when online — the OpenGolfAPI open database
(16,900+ US courses with GPS + hole-by-hole par, ODbL 1.0, no key;
~1,000 hosted-API calls/day, so detail is fetched on demand and
cached on-device after import). One search box on the Courses tab
covers saved + online together: saved courses filter per keystroke,
online follows after a short pause (3+ chars). Tap Import to prefill
the add form. Every tee box the database knows arrives
**prefilled with its rating and slope**, which the handicap maths needs,
so an imported course does not have to be retyped by hand. Stroke index
is read from the card's own handicap row when the database holds a valid
1..n permutation, and otherwise estimated odd-front/even-back. Per-hole
yardage is only published for some tees — where it is missing the app
shows "—" rather than borrowing another tee's numbers, so check any tee
whose yardage row is blank. Men's tees only are imported, since the app
stores one rating per tee; a database row with no rating or slope is
skipped, and if no tee survives the form falls back to one blank tee box
to type into. Multi-token search
falls back to shorter queries and ranks city/state matches first, so
"Crystal Lake Golf Club Lakeville MN" surfaces the MN club above its
same-name clubs in RI/MI/MA (bad community data can be reported at
opengolfapi/data issues).

Attribution shown in-app: `Course data © OpenStreetMap contributors
via OpenGolfAPI (opengolfapi.org), ODbL 1.0`.

## Sources (verified 2026-09-26)

- OpenGolfAPI dataset + API docs: [opengolfapi/data](https://github.com/opengolfapi/data)
  (ODbL 1.0; GeoJSON/CSV/NDJSON downloads; keyless REST API)
- Schema: [OpenGolf Schema v1.0](https://github.com/opengolfapi/data/blob/HEAD/SCHEMA.md)
- Open-data landscape notes: [course-data-registry.md](https://github.com/sebrock/rideordie-opengolf/blob/HEAD/course-data-registry.md)
  (confirms OSM as global fallback; rating/slope only via commercial feeds)

## Reading the recent rounds list

Each row under **Recent rounds** shows, left to right: your gross score, the
course and tee, then a second line carrying the date as `MM-DD-YY`, the par for
the holes you actually played, the tee rating, the tee slope, how many strokes
you were over or under par, your course handicap, and the edit and delete
controls.

Rating and slope come from the tee the round was played, are printed to the
precision they are published at (rating to one decimal), and show as a dash
when that tee is no longer on file — a rating of `0.0` would be a course nobody
plays, and a missing slope is not a flat slope. The second line is allowed to
wrap onto two lines on a narrow screen rather than clip: on a phone the
trailing figures get cut off otherwise, and a missing slope reads as data.

Par is the par of the holes played, not the full 18: a nine started on the 5th
is scored against the par of holes 5 through 13, so the figure can be 36 on one
course and 38 on another. A round of exactly par is shown as `E`, the way a
printed card shows it; a bare `0` next to a score reads like missing data.

The new-round tee defaults to **White**, which is what most golfers mean by
"just let me play". Tee names are matched without regard to case or
surrounding whitespace, since they vary wildly between courses. A course with
no tee called White falls back to the **second** tee — tee data is stored
longest first, so the second is a reasonable guess at a middle tee — and a
course with only one tee gets that tee.

## Correct or remove a posted round

Every row under **Recent rounds** carries an explicit edit and delete button,
and tapping the row itself opens it for editing. The swipe-to-delete still
works, but it is not the only way in: a control that is invisible until you
know to swipe reads as a row that cannot be removed at all.

Editing opens the normal score entry prefilled with what was posted, and
saving **updates that round** rather than posting a second one — otherwise a
correction would double the round in the handicap average. The round keeps its
id, its date, and the handicap index it was played under, because it was still
played on that date; only the scores and the resulting course handicap change.
Abandoning the edit changes nothing.

Deleting offers an undo for as long as the snackbar is up, and puts the round
back in the position it came from, since list order feeds the stats and the
CSV export.

## Back up and restore scores

The save-all icon in the app bar (top right) does all four:

- **Export CSV** — one row per round, for reading in a spreadsheet.
- **Import CSV** — read a ghin-golf CSV back in. See below.
- **Export full backup** — everything the app holds: every round, every course
  (custom *and* bundled, so restored rounds still resolve their handicap),
  the score-versus-par colors, and the scanned scorecard photos. This is the
  only format that can be imported back.
- **Import backup** — restore a full backup.

Photos are stored in the course's own storage, not just referenced by path, so
the backup carries the image bytes and a restore puts them back where the app
expects them. A photo that cannot be read or written costs that one image, not
the rest of the backup.

## Import a CSV

**Import CSV** reads a ghin-golf CSV export back in, which is the way to move a
history in from a spreadsheet or from another phone.

Courses and tees are matched **by name**, ignoring case and extra spaces, since
the ids in a spreadsheet either came from a different install or a different
app entirely. A round naming a course you already have is posted against that
course, so its real pars and stroke indexes apply.

Two things it will not do:

- **It does not invent a course.** If the file names a course the app has never
  seen, one is built and the confirmation dialog says how many, because a built
  course is a stand-in: the file carries a par *total*, not a hole-by-hole
  layout, so the par is spread across the holes. Edit those pars before trusting
  what the app says the round was worth.
- **It does not post the same round twice.** A round is identified by its
  course, tee, date and scores, not by the id in the file, so importing the
  same file again adds nothing. This holds even if the file's ids have changed
  in the meantime.

The import is undoable from the snackbar, and only removes the rounds it added —
a round posted since is left alone.

A row whose scores are missing, out of range, or undated is dropped rather than
guessed at: a wrong number in a handicap average is worse than a round you have
to type in yourself.

Files are written wherever you choose in the save dialog — the app's Documents
directory on a device if you skip it, and a browser download on the web. The
filename carries a timestamp (`ghin-golf-rounds-20260928-1842.json`) so a
second export does not overwrite the first.

A backup records the app version that wrote it. Backups from before the full
snapshot used a different course key; those still import.

Import **merges** rather than replaces: rounds and courses already in the app
are left alone, so restoring a backup can never cost you the history you
currently have. Importing the same file twice changes nothing the second time.
The whole file is parsed before anything is written, so a truncated or
unrelated file leaves your scores untouched.

Before anything is written, the confirmation lists **everything** the file
would bring in — rounds, courses, score colors and photos — not just the
rounds. A backup whose rounds are all already present still restores the
courses, settings and photos it carries; that is a common restore, since
re-importing your own backup is how you check it works. If the file really
holds nothing this app is missing, the app says so and names what the file
did contain rather than reporting "nothing new" and stopping.

A course keeps a photo it already has on disk. If its `imagePath` is set but
the file is gone — app data cleared, say — the backup's copy is written back
and the course is repointed at it.

## Test on PC (no toolchain needed)

```bash
cd ~/ghin-golf
flutter test            # WHS vectors + widget boot test
flutter build web --release
cd build/web && python3 -m http.server 8080
# open http://localhost:8080 in Brave/any browser
```

`flutter run -d linux` additionally requires:
`clang cmake ninja-build libgtk-3-dev mesa-utils` (needs sudo).

## Build the APK

Needs a full JDK 17+ (not just a JRE) plus the Android SDK:

```bash
export JAVA_HOME=~/.local/share/temurin/jdk-17.0.20.1+1   # full JDK, see below
export PATH=$JAVA_HOME/bin:$PATH
flutter doctor --android-licenses   # accept once
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

If only a JRE is installed, fetch a user-local Temurin 17 JDK:

```bash
mkdir -p ~/.local/share/temurin && cd ~/.local/share/temurin
curl -L -o jdk17.tar.gz https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse
tar xzf jdk17.tar.gz
```

## Handicap score eligibility

Full 18-hole scores use the tee's full-course rating and slope. Partial scores
on an 18-hole tee are accepted for index purposes only with at least 10 holes
played and a recorded valid reason; unplayed holes use an index-based expected
score estimate. Nine-hole scores are retained but excluded from the index and
have no Course Handicap until tee data includes separate nine-hole ratings and
slopes. The app does not infer those ratings from the full-course values.

## Layout

- `lib/whs.dart` — pure-Dart WHS engine (differentials, best-8-of-20,
  small-field table, soft/hard cap vs the Low Handicap Index, Exceptional Score
  Reduction, Course/Playing Handicap, haversine yards). `handicapIndexFromRecord`
  replays posted scores in date order so historical caps, the active Low
  Handicap Index, and exceptional reductions stay attached to the right scores.
- `lib/csv_import.dart` — reads a CSV export back in: an RFC 4180 table
  reader (quoted fields, embedded newlines, CRLF, BOM) and the row-to-round
  mapping. Flutter-free so the parsing can be asserted on directly.
- `lib/models.dart` — Course/Tee/Round/HoleScore/Golfer
- `lib/data.dart` — the bundled demo course (Crystal Lake) + demo golfers
- `lib/store.dart` — ChangeNotifier + JSON file persistence
  (`$HOME/.ghin-golf.json`, temp-dir fallback on mobile). Saves are chained
  and land via a temp file renamed into place, so a save is never left
  half-written; an unreadable file is copied aside before anything overwrites
  it.
- `lib/main.dart` — Home / Play / Courses+GPS / Stats tabs
- `lib/theme_toggle.dart` — the app-bar appearance control
- `lib/design_tokens.dart` / `lib/app_theme.dart` — spacing, colour, type and
  the light/dark themes
- `tool/make_icon.dart` — draws every launcher icon from code:
  `dart run tool/make_icon.dart`
- `tool/check_icon.dart` — asserts the generated icons are the right size, are
  not clipped by a launcher's own mask, and keep the Android adaptive mark
  inside its 72dp safe zone. `test/icon_test.dart` runs the same checks as
  part of `flutter test`.
- `lib/opengolf.dart` — OpenGolfAPI search + detail client (ODbL 1.0)
- Scorecard scan: photo (camera/gallery) -> on-device Tesseract OCR
  (`flutter_tesseract_ocr`, BSD-3; bundled eng tessdata on mobile,
  tesseract.js on web) -> `lib/scorecard_scan.dart` heuristic parser
  prefills pars, per-tee yardages, rating/slope — user verifies all
  values before saving
- `lib/scan_service.dart` — image preprocessing, OCR variants, engine args
- `lib/hocr.dart` / `lib/table_geometry.dart` — read the card's table from
  word boxes, so a dropped digit leaves a hole unknown instead of silently
  shifting every value after it
- `test/whs_test.dart` — WHS vectors (durable coverage)
- `test/widget_test.dart` — app boots to Home
