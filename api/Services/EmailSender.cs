using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace RailLog.API.Services;

public sealed class EmailSender(IOptions<EmailOptions> options)
{
    private readonly SmtpOptions _options = options.Value.Smtp;

    public async Task SendVerificationCodeAsync(
        string recipient,
        string code,
        VerificationPurpose purpose,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.Password))
            throw new EmailDeliveryException("邮件服务尚未配置");

        var action = purpose == VerificationPurpose.Register ? "注册账号" : "重置密码";
        var message = new MimeMessage();
        message.From.Add(new MailboxAddress(_options.FromName, _options.FromEmail));
        message.To.Add(MailboxAddress.Parse(recipient));
        message.Subject = $"{code} - RailLog {action}验证码";
        message.Body = new BodyBuilder
        {
            TextBody = $"你的 RailLog {action}验证码是：{code}\n\n验证码 10 分钟内有效。若非本人操作，请忽略此邮件。",
            HtmlBody = $"""
                <div style="font-family:Arial,'Microsoft YaHei',sans-serif;color:#202124;line-height:1.6">
                  <h2 style="font-size:20px;margin:0 0 16px">RailLog {action}</h2>
                  <p>你的验证码是：</p>
                  <p style="font-size:30px;font-weight:700;letter-spacing:6px;margin:16px 0">{code}</p>
                  <p>验证码 10 分钟内有效。若非本人操作，请忽略此邮件。</p>
                </div>
                """,
        }.ToMessageBody();

        using var client = new SmtpClient();
        var socketOptions = _options.UseSsl
            ? SecureSocketOptions.SslOnConnect
            : SecureSocketOptions.StartTls;
        await client.ConnectAsync(
            _options.Host,
            _options.Port,
            socketOptions,
            cancellationToken);
        await client.AuthenticateAsync(
            _options.UserName,
            _options.Password,
            cancellationToken);
        await client.SendAsync(message, cancellationToken);
        await client.DisconnectAsync(true, cancellationToken);
    }
}

public sealed class EmailDeliveryException(string message, Exception? innerException = null)
    : Exception(message, innerException);
