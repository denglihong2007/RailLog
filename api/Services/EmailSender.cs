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

        // 两层预算：client.Timeout 限制每次 socket 操作，外层 CTS 限制整次调用的总时长
        // —— DNS 解析和连接黑洞不受 socket 超时约束，只有总预算能兜住。
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        budget.CancelAfter(TimeSpan.FromSeconds(_options.TimeoutSeconds * 2));
        var token = budget.Token;
        try
        {
            using var client = new SmtpClient { Timeout = _options.TimeoutSeconds * 1000 };
            var socketOptions = _options.UseSsl
                ? SecureSocketOptions.SslOnConnect
                : SecureSocketOptions.StartTls;
            await client.ConnectAsync(
                _options.Host,
                _options.Port,
                socketOptions,
                token);
            await client.AuthenticateAsync(
                _options.UserName,
                _options.Password,
                token);
            await client.SendAsync(message, token);
            // SendAsync 返回即表示服务器已接收。若在此之后的断开失败就向上抛，
            // 调用方会删掉验证码并返回 503，而用户其实已经收到了那封邮件 —— 所以只记录、不上报。
            try
            {
                await client.DisconnectAsync(true, token);
            }
            catch (Exception)
            {
                // 邮件已投递，断开失败的后果仅为连接被服务端回收。
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // 只有我方总预算耗尽才会走到这里。客户端断开时外层 token 已取消，应原样抛出
            // （调用方据此区分「用户走了」和「我们超时了」）。
            throw new EmailDeliveryException("邮件服务超时，请稍后重试");
        }
    }
}

public sealed class EmailDeliveryException(string message, Exception? innerException = null)
    : Exception(message, innerException);
