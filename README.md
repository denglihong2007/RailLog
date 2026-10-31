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
