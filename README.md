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

## Run the client

```powershell
cd app
flutter run -d windows
```

The client defaults to `http://localhost:5149`. Override it for another host:

```powershell
flutter run --dart-define=RAILLOG_API_URL=http://192.168.1.10:5149
```

Use `http://10.0.2.2:5149` from an Android emulator. Password-reset email
delivery is intentionally left as a placeholder endpoint.
