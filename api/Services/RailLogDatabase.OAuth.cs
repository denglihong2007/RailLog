using Microsoft.Data.Sqlite;

namespace RailLog.API.Services;

public sealed record OAuthClientRecord(
    string ClientId,
    string Name,
    string? LogoUrl,
    string? ClientSecretHash,
    IReadOnlyList<string> RedirectUris,
    IReadOnlyList<string> Scopes,
    DateTime CreatedAt,
    DateTime? RevokedAt);

public sealed record OAuthAuthorizationCodeRecord(
    string ClientId,
    string UserId,
    string RedirectUri,
    string Scope,
    string CodeChallenge,
    DateTime ExpiresAt,
    DateTime? ConsumedAt);

public sealed record OAuthAccessTokenRecord(
    string ClientId,
    string UserId,
    string Scope,
    DateTime ExpiresAt);

public sealed record OAuthRefreshTokenRecord(
    string ClientId,
    string UserId,
    string Scope,
    DateTime ExpiresAt);

public sealed record OAuthConsentRecord(
    string ClientId,
    string Name,
    string? LogoUrl,
    string Scope,
    DateTime CreatedAt);

public sealed partial class RailLogDatabase
{
    public async Task CreateOAuthClientAsync(
        string clientId,
        string name,
        string? logoUrl,
        string? clientSecretHash,
        IReadOnlyList<string> redirectUris,
        IReadOnlyList<string> scopes)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO OAuthClients
                (ClientId, Name, LogoUrl, ClientSecretHash, RedirectUris, Scopes, CreatedAt, RevokedAt)
            VALUES
                ($clientId, $name, $logoUrl, $secretHash, $redirectUris, $scopes, $createdAt, NULL);
            """;
        command.Parameters.AddWithValue("$clientId", clientId);
        command.Parameters.AddWithValue("$name", name);
        command.Parameters.AddWithValue("$logoUrl", DbValue(logoUrl));
        command.Parameters.AddWithValue("$secretHash", DbValue(clientSecretHash));
        command.Parameters.AddWithValue("$redirectUris", string.Join('\n', redirectUris));
        command.Parameters.AddWithValue("$scopes", string.Join(' ', scopes));
        command.Parameters.AddWithValue("$createdAt", ToDb(DateTime.Now));
        await command.ExecuteNonQueryAsync();
    }

    public async Task<OAuthClientRecord?> GetOAuthClientAsync(string clientId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT ClientId, Name, LogoUrl, ClientSecretHash, RedirectUris, Scopes, CreatedAt, RevokedAt
            FROM OAuthClients
            WHERE ClientId = $clientId
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$clientId", clientId);
        await using var reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync() ? ReadOAuthClient(reader) : null;
    }

    public async Task<IReadOnlyList<OAuthClientRecord>> GetOAuthClientsAsync()
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT ClientId, Name, LogoUrl, ClientSecretHash, RedirectUris, Scopes, CreatedAt, RevokedAt
            FROM OAuthClients
            ORDER BY CreatedAt DESC;
            """;
        await using var reader = await command.ExecuteReaderAsync();
        var clients = new List<OAuthClientRecord>();
        while (await reader.ReadAsync()) clients.Add(ReadOAuthClient(reader));
        return clients;
    }

    public async Task<bool> RevokeOAuthClientAsync(string clientId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE OAuthClients SET RevokedAt = $now WHERE ClientId = $clientId AND RevokedAt IS NULL;
            UPDATE OAuthAuthorizationCodes SET ConsumedAt = $now WHERE ClientId = $clientId AND ConsumedAt IS NULL;
            UPDATE OAuthAccessTokens SET RevokedAt = $now WHERE ClientId = $clientId AND RevokedAt IS NULL;
            UPDATE OAuthRefreshTokens SET RevokedAt = $now WHERE ClientId = $clientId AND RevokedAt IS NULL;
            """;
        command.Parameters.AddWithValue("$clientId", clientId);
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        return await command.ExecuteNonQueryAsync() > 0;
    }

    public async Task CreateOAuthAuthorizationCodeAsync(
        string codeHash,
        string clientId,
        string userId,
        string redirectUri,
        string scope,
        string codeChallenge,
        DateTime expiresAt)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            DELETE FROM OAuthAuthorizationCodes WHERE ExpiresAt <= $now;
            INSERT INTO OAuthAuthorizationCodes
                (CodeHash, ClientId, UserId, RedirectUri, Scope, CodeChallenge, CodeChallengeMethod,
                 CreatedAt, ExpiresAt, ConsumedAt)
            VALUES
                ($codeHash, $clientId, $userId, $redirectUri, $scope, $codeChallenge, 'S256',
                 $createdAt, $expiresAt, NULL);
            """;
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$codeHash", codeHash);
        command.Parameters.AddWithValue("$clientId", clientId);
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$redirectUri", redirectUri);
        command.Parameters.AddWithValue("$scope", scope);
        command.Parameters.AddWithValue("$codeChallenge", codeChallenge);
        command.Parameters.AddWithValue("$createdAt", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$expiresAt", ToDb(expiresAt));
        await command.ExecuteNonQueryAsync();
    }

    public async Task<OAuthAuthorizationCodeRecord?> GetOAuthAuthorizationCodeAsync(string codeHash)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT ClientId, UserId, RedirectUri, Scope, CodeChallenge, ExpiresAt, ConsumedAt
            FROM OAuthAuthorizationCodes
            WHERE CodeHash = $codeHash
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$codeHash", codeHash);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        return new OAuthAuthorizationCodeRecord(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            FromDb(reader.GetString(5)),
            NullableDate(reader, 6));
    }

    /// <summary>
    /// 一次性消费授权码。返回 true 表示本次调用抢到了这个码，
    /// 并发的第二个请求会拿到 false。
    /// </summary>
    public async Task<bool> ConsumeOAuthAuthorizationCodeAsync(string codeHash)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE OAuthAuthorizationCodes
            SET ConsumedAt = $now
            WHERE CodeHash = $codeHash AND ConsumedAt IS NULL AND ExpiresAt > $now;
            """;
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$codeHash", codeHash);
        return await command.ExecuteNonQueryAsync() == 1;
    }

    public async Task CreateOAuthTokensAsync(
        string accessTokenHash,
        string refreshTokenHash,
        string clientId,
        string userId,
        string scope,
        DateTime accessExpiresAt,
        DateTime refreshExpiresAt)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            DELETE FROM OAuthAccessTokens WHERE ExpiresAt <= $now;
            DELETE FROM OAuthRefreshTokens WHERE ExpiresAt <= $now;
            INSERT INTO OAuthAccessTokens
                (TokenHash, ClientId, UserId, Scope, CreatedAt, ExpiresAt, RevokedAt)
            VALUES
                ($accessHash, $clientId, $userId, $scope, $now, $accessExpiresAt, NULL);
            INSERT INTO OAuthRefreshTokens
                (TokenHash, ClientId, UserId, Scope, CreatedAt, ExpiresAt, RevokedAt, RotatedAt)
            VALUES
                ($refreshHash, $clientId, $userId, $scope, $now, $refreshExpiresAt, NULL, NULL);
            """;
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        command.Parameters.AddWithValue("$accessHash", accessTokenHash);
        command.Parameters.AddWithValue("$refreshHash", refreshTokenHash);
        command.Parameters.AddWithValue("$clientId", clientId);
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$scope", scope);
        command.Parameters.AddWithValue("$accessExpiresAt", ToDb(accessExpiresAt));
        command.Parameters.AddWithValue("$refreshExpiresAt", ToDb(refreshExpiresAt));
        await command.ExecuteNonQueryAsync();
    }

    public async Task<OAuthAccessTokenRecord?> GetOAuthAccessTokenAsync(string tokenHash)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT ClientId, UserId, Scope, ExpiresAt
            FROM OAuthAccessTokens
            WHERE TokenHash = $tokenHash AND RevokedAt IS NULL AND ExpiresAt > $now
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$tokenHash", tokenHash);
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        return new OAuthAccessTokenRecord(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2),
            FromDb(reader.GetString(3)));
    }

    public async Task<OAuthRefreshTokenRecord?> GetOAuthRefreshTokenAsync(string tokenHash)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT ClientId, UserId, Scope, ExpiresAt
            FROM OAuthRefreshTokens
            WHERE TokenHash = $tokenHash
              AND RevokedAt IS NULL AND RotatedAt IS NULL AND ExpiresAt > $now
            LIMIT 1;
            """;
        command.Parameters.AddWithValue("$tokenHash", tokenHash);
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        return new OAuthRefreshTokenRecord(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2),
            FromDb(reader.GetString(3)));
    }

    /// <summary>刷新令牌轮换：只有第一次调用能成功，避免重放。</summary>
    public async Task<bool> RotateOAuthRefreshTokenAsync(string tokenHash)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE OAuthRefreshTokens
            SET RotatedAt = $now
            WHERE TokenHash = $tokenHash
              AND RevokedAt IS NULL AND RotatedAt IS NULL AND ExpiresAt > $now;
            """;
        command.Parameters.AddWithValue("$tokenHash", tokenHash);
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        return await command.ExecuteNonQueryAsync() == 1;
    }

    /// <summary>
    /// 撤销令牌。按 RFC 7009：撤销刷新令牌时一并作废同一授权下的访问令牌；
    /// 只撤销访问令牌时，刷新令牌仍然有效。解绑请撤销 refresh_token。
    /// </summary>
    public async Task RevokeOAuthTokenAsync(string tokenHash, string clientId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();

        // 先判断是不是刷新令牌；访问令牌与刷新令牌用的是同一套随机格式，
        // 但两表分别存储，不会同时命中。
        await using var lookup = connection.CreateCommand();
        lookup.CommandText = """
            SELECT UserId FROM OAuthRefreshTokens
            WHERE TokenHash = $tokenHash AND ClientId = $clientId
            LIMIT 1;
            """;
        lookup.Parameters.AddWithValue("$tokenHash", tokenHash);
        lookup.Parameters.AddWithValue("$clientId", clientId);
        var refreshOwner = await lookup.ExecuteScalarAsync() as string;
        if (refreshOwner is not null)
        {
            await using var revokeGrant = connection.CreateCommand();
            revokeGrant.CommandText = """
                UPDATE OAuthAccessTokens SET RevokedAt = $now
                WHERE UserId = $userId AND ClientId = $clientId AND RevokedAt IS NULL;
                UPDATE OAuthRefreshTokens SET RevokedAt = $now
                WHERE UserId = $userId AND ClientId = $clientId AND RevokedAt IS NULL;
                """;
            revokeGrant.Parameters.AddWithValue("$userId", refreshOwner);
            revokeGrant.Parameters.AddWithValue("$clientId", clientId);
            revokeGrant.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
            await revokeGrant.ExecuteNonQueryAsync();
            return;
        }

        await using var revokeAccess = connection.CreateCommand();
        revokeAccess.CommandText = """
            UPDATE OAuthAccessTokens SET RevokedAt = $now
            WHERE TokenHash = $tokenHash AND ClientId = $clientId AND RevokedAt IS NULL;
            """;
        revokeAccess.Parameters.AddWithValue("$tokenHash", tokenHash);
        revokeAccess.Parameters.AddWithValue("$clientId", clientId);
        revokeAccess.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        await revokeAccess.ExecuteNonQueryAsync();
    }

    public async Task UpsertOAuthConsentAsync(string userId, string clientId, string scope)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO OAuthConsents (UserId, ClientId, Scope, CreatedAt, RevokedAt)
            VALUES ($userId, $clientId, $scope, $createdAt, NULL)
            ON CONFLICT (UserId, ClientId) DO UPDATE SET
                Scope = excluded.Scope,
                CreatedAt = excluded.CreatedAt,
                RevokedAt = NULL;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$clientId", clientId);
        command.Parameters.AddWithValue("$scope", scope);
        command.Parameters.AddWithValue("$createdAt", ToDb(DateTime.Now));
        await command.ExecuteNonQueryAsync();
    }

    public async Task<IReadOnlyList<OAuthConsentRecord>> GetOAuthConsentsAsync(string userId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT consent.ClientId, client.Name, client.LogoUrl, consent.Scope, consent.CreatedAt
            FROM OAuthConsents consent
            JOIN OAuthClients client ON client.ClientId = consent.ClientId
            WHERE consent.UserId = $userId
              AND consent.RevokedAt IS NULL
              AND client.RevokedAt IS NULL
            ORDER BY consent.CreatedAt DESC;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        await using var reader = await command.ExecuteReaderAsync();
        var consents = new List<OAuthConsentRecord>();
        while (await reader.ReadAsync())
        {
            consents.Add(new OAuthConsentRecord(
                reader.GetString(0),
                reader.GetString(1),
                NullableString(reader, 2),
                reader.GetString(3),
                FromDb(reader.GetString(4))));
        }
        return consents;
    }

    /// <summary>用户解除授权：同时吊销该应用名下这个用户的全部令牌。</summary>
    public async Task RevokeOAuthConsentAsync(string userId, string clientId)
    {
        await using var connection = OpenConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE OAuthConsents SET RevokedAt = $now
            WHERE UserId = $userId AND ClientId = $clientId AND RevokedAt IS NULL;
            UPDATE OAuthAccessTokens SET RevokedAt = $now
            WHERE UserId = $userId AND ClientId = $clientId AND RevokedAt IS NULL;
            UPDATE OAuthRefreshTokens SET RevokedAt = $now
            WHERE UserId = $userId AND ClientId = $clientId AND RevokedAt IS NULL;
            """;
        command.Parameters.AddWithValue("$userId", userId);
        command.Parameters.AddWithValue("$clientId", clientId);
        command.Parameters.AddWithValue("$now", ToDb(DateTime.Now));
        await command.ExecuteNonQueryAsync();
    }

    private static OAuthClientRecord ReadOAuthClient(SqliteDataReader reader) =>
        new(
            reader.GetString(0),
            reader.GetString(1),
            NullableString(reader, 2),
            NullableString(reader, 3),
            SplitOAuthList(reader.GetString(4), '\n'),
            SplitOAuthList(reader.GetString(5), ' '),
            FromDb(reader.GetString(6)),
            NullableDate(reader, 7));

    private static IReadOnlyList<string> SplitOAuthList(string value, char separator) =>
        value.Split(
            separator,
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}
