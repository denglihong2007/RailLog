using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public enum VerificationPurpose { Register, ResetPassword }

public sealed class EmailVerificationService(
    RailLogDatabase database,
    EmailSender emailSender,
    IOptions<EmailOptions> options,
    ILogger<EmailVerificationService> logger)
{
    private readonly VerificationOptions _options = options.Value.Verification;

    public async Task RequestCodeAsync(
        string rawEmail,
        VerificationPurpose purpose,
        CancellationToken cancellationToken)
    {
        var email = NormalizeEmail(rawEmail);
        if (!IsValidEmail(email)) throw new VerificationException("请输入有效邮箱");

        var emailExists = await database.EmailExistsAsync(email);
        if (purpose == VerificationPurpose.Register && emailExists)
            throw new VerificationException("该邮箱已注册");
        if (purpose == VerificationPurpose.ResetPassword && !emailExists)
            return;

        var lastCreatedAt = await database.GetLatestVerificationCreatedAtAsync(
            email,
            PurposeValue(purpose));
        var cooldown = TimeSpan.FromSeconds(_options.ResendCooldownSeconds);
        if (lastCreatedAt is not null && DateTime.UtcNow - lastCreatedAt.Value < cooldown)
            throw new VerificationException("验证码发送过于频繁，请稍后再试");

        var code = RandomNumberGenerator.GetInt32(100000, 1000000)
            .ToString(CultureInfo.InvariantCulture);
        var id = Guid.NewGuid().ToString("N");
        await database.InsertVerificationCodeAsync(
            id,
            email,
            PurposeValue(purpose),
            Hash(email, purpose, code),
            DateTime.UtcNow.AddMinutes(_options.CodeLifetimeMinutes));
        try
        {
            await emailSender.SendVerificationCodeAsync(
                email,
                code,
                purpose,
                cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            await database.DeleteVerificationCodeAsync(id);
            logger.LogError(exception, "Failed to send verification email to {Email}", email);
            throw new EmailDeliveryException("验证码邮件发送失败，请稍后重试", exception);
        }
    }

    public async Task<bool> VerifyAndConsumeAsync(
        string rawEmail,
        VerificationPurpose purpose,
        string rawCode)
    {
        var email = NormalizeEmail(rawEmail);
        var code = rawCode.Trim();
        if (!IsValidEmail(email) || !code.All(char.IsAsciiDigit) || code.Length != 6)
            return false;

        var stored = await database.GetLatestVerificationCodeAsync(
            email,
            PurposeValue(purpose));
        if (stored is null || stored.ExpiresAt <= DateTime.UtcNow ||
            stored.AttemptCount >= _options.MaxAttempts)
            return false;

        var expected = Convert.FromHexString(stored.CodeHash);
        var actual = Convert.FromHexString(Hash(email, purpose, code));
        if (!CryptographicOperations.FixedTimeEquals(expected, actual))
        {
            await database.IncrementVerificationAttemptsAsync(stored.Id);
            return false;
        }
        return await database.ConsumeVerificationCodeAsync(stored.Id);
    }

    public static bool TryParsePurpose(string value, out VerificationPurpose purpose)
    {
        purpose = value.Trim().ToLowerInvariant() switch
        {
            "register" => VerificationPurpose.Register,
            "reset-password" => VerificationPurpose.ResetPassword,
            _ => (VerificationPurpose)(-1),
        };
        return Enum.IsDefined(purpose);
    }

    private string Hash(string email, VerificationPurpose purpose, string code)
    {
        if (string.IsNullOrWhiteSpace(_options.HashKey))
            throw new InvalidOperationException("Email:Verification:HashKey is not configured");
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(_options.HashKey));
        return Convert.ToHexString(hmac.ComputeHash(
            Encoding.UTF8.GetBytes($"{email}\n{PurposeValue(purpose)}\n{code}")));
    }

    private static string NormalizeEmail(string value) => value.Trim().ToLowerInvariant();
    private static bool IsValidEmail(string value) =>
        value.Length <= 254 && value.Contains('@') && !value.StartsWith('@') && !value.EndsWith('@');
    private static string PurposeValue(VerificationPurpose purpose) => purpose switch
    {
        VerificationPurpose.Register => "register",
        VerificationPurpose.ResetPassword => "reset-password",
        _ => throw new ArgumentOutOfRangeException(nameof(purpose)),
    };
}

public sealed class VerificationException(string message) : Exception(message);
