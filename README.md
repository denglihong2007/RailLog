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
