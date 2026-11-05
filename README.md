# RailLog

RailLog consists of a Flutter client in `app` and an ASP.NET Core API in `api`.
The client keeps an offline SQLite database and synchronizes account-scoped
trip records with the API after login.

## Run the API

```powershell
dotnet run --project api\RailLog.API.csproj --launch-profile http
```

The default endpoint is `http://localhost:5149`. The server database is
`api\raillog.db`. To use an existing compatible database, override the
connection string:

```powershell
$env:ConnectionStrings__RailLog = 'Data Source=C:\path\to\raillog.db'
dotnet run --project api\RailLog.API.csproj --launch-profile http
```

Legacy `AspNetUsers` and `TripRecords` tables are migrated in place on startup.
Back up a production database before its first migration.

While the API is running it backs up the database every other day via the
SQLite online backup API. Backups are written to `api\backups` by default and
the newest seven are kept. Configure the behavior in `appsettings.json`:

```json
"DatabaseBackup": {
  "Enabled": true,
  "Directory": "backups",
  "IntervalDays": 2,
  "KeepCount": 7
}
```

`Directory` may be absolute. The interval is measured from the newest existing
backup, so restarting the process does not create a duplicate, and a missed
window is caught up on the next hourly check.

The historical timetables (about 860MB in total) are not included in the
repository. The API syncs them from the private `denglihong2007/Timetable-Results`
GitHub releases: it fills in missing versions shortly after startup, then checks
again every day at 06:00 Beijing time. Each release asset is stored as-is as
`timetables/{yyyy.MM.dd}.db` and queried directly; versions already on disk are
skipped. Configure the schedule in `appsettings.json`:

```json
"TrainTimetables": {
  "Sync": {
    "Enabled": true,
    "Hour": 6,
    "Minute": 0,
    "TimeZone": "Asia/Shanghai",
    "Owner": "denglihong2007",
    "Repository": "Timetable-Results",
    "AssetName": "train_timetables.db"
  }
}
```

The release repository is private, so the API needs a GitHub token with read
access. Set it with user-secrets; never put it in `appsettings.json`:

```powershell
cd api
dotnet user-secrets set "TrainTimetables:Sync:GitHubToken" "<github-token>"
```

The synchronized databases are stored under `api\timetables\`, relative to the
API content root. The directory is created on first sync and is excluded from
Git.

The Flutter map loads AMap through API proxy endpoints. Configure the AMap key
only on the API host; do not place it in the Flutter client:

```powershell
$env:Amap__WebApiKey = 'your-amap-web-api-key'
```

The SDK proxy endpoints are GET-only and IP rate-limited.

The ticket generator reads its private fonts, ticket backgrounds, and station
pinyin data only from a server-side directory. Configure that directory before
using the authenticated generator endpoints:

```powershell
$env:TicketAssets__Directory = 'C:\path\to\private\ticket-assets'
```

For local API development, the same setting can be stored in .NET User Secrets:

```powershell
cd api
dotnet user-secrets set "TicketAssets:Directory" "C:\path\to\private\ticket-assets"
dotnet user-secrets set "TicketPdf:DownloadPassword" "your-private-download-password"
```

For deployed environments, set the PDF download password with the
`TicketPdf__DownloadPassword` environment variable. Never place the password
in the web or Flutter client.

The directory must contain `CODE1.OTF`, `PAPERTICKETS.OTF`, `red.png`,
`blue.png`, and `District.json`. These files are intentionally excluded from
Git and must never be deployed with the web or Flutter client.

## Web admin console

The web project doubles as the admin console at `/admin` (in development,
`http://localhost:55634/admin`). Administrators log in with their normal
RailLog account (email and password). Admin permission is granted only to the
account IDs listed in `appsettings.json`:

```json
"Admin": {
  "UserIds": [
    "632e229a-5801-4f08-b700-ea4dc44600af",
    "e6550bc3b5a345209f34a7520995d2cb"
  ]
}
```

GUID formatting is normalized before comparison, so hyphenated GUIDs and the
32-character form both work. The console reuses the account's normal 30-day
token; deleting or revoking that token also ends admin access. Login attempts
are rate-limited to five per minute per IP, and a non-admin account receives
403 with the freshly issued token revoked.

The console also turns the leaderboards into a correction tool: selecting a
user opens all of their trips, selecting a trip opens its editor directly, and
selecting a station, route, train, rolling-stock type or company jumps to the
reviews for that entity. Reviews themselves can be searched, inspected and
deleted from the console; deleting a review also removes the reactions on it
and triggers a recompute of the author's achievements.

Beyond data correction, the console covers day-to-day operations:

- duplicate detection (same user, train, travel date, origin/destination, fare
  and mileage) with per-trip deletion or "keep the earliest entry";
- user profile editing and user deletion;
- levels and achievements in one page: per-level user counts derived from each
  user's unlocked-achievement experience, editable LV1–LV6 experience floors,
  and a read-only achievement table with unlock records. Clicking a level opens
  the user list filtered to that level, and users can also be filtered by level
  or searched by email, nickname or ID. Saving new floors starts a single
  background recompute of all achievements — repeated saves while one is
  running are folded into it — and the page shows its progress and refreshes
  the counts when it finishes. The app and the public website pick up the new
  floors from the public `GET /api/user-levels` endpoint;
- PDF download management — the download password plus the 24-hour request keys
  issued by the website, which can be searched by passenger or masked ID,
  inspected and revoked;
- database backups — generate and download a fresh snapshot, download any
  retained backup, or delete one after typing its file name;
- audit log — an append-only record of destructive and configuration-changing
  operations (deletions, profile edits, level floors, password and request-key
  changes, backup downloads and deletions, manual timetable syncs) with the
  operator name captured at the time;
- historical timetable sync — local versions, schedule, a manual trigger and a
  diff against the GitHub Release upstream.

Announcements entered in the console are stored in the `Announcements` table
and served to clients through the existing advertisement endpoint. Only when
the table has no rows at all does the server fall back to the `Announcements`
section in `appsettings.json`; disabling every row means no announcements.

## Run the client

```powershell
cd app
flutter run -d windows
```

Debug and profile builds default to `http://localhost:5149`; release builds
default to `https://api.raillog.top`. Override it for another host:

```powershell
flutter run --dart-define=RAILLOG_API_URL=http://192.168.1.10:5149
```

Use `http://10.0.2.2:5149` from an Android emulator. Password-reset email
delivery is intentionally left as a placeholder endpoint.
