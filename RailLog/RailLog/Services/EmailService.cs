using Microsoft.AspNetCore.Identity;
using System.Net;
using System.Net.Mail;
using RailLog.Data;
using RailLog.Models;

public class EmailService(IConfiguration config) : IEmailSender<ApplicationUser>
{
    // 这个方法负责发送确认链接邮件
    public async Task SendConfirmationLinkAsync(ApplicationUser user, string email, string confirmationLink)
    {
        await SendEmailAsync(email, "确认您的邮箱", $"请点击此链接确认：<a href='{confirmationLink}'>点击这里</a>");
    }

    private async Task SendEmailAsync(string email, string subject, string htmlMessage)
    {
        var settings = config.GetSection("EmailSettings").Get<EmailSettings>();

        if (settings == null) throw new Exception("Email settings not found");

        using var client = new SmtpClient(settings.SmtpServer, settings.Port)
        {
            EnableSsl = settings.EnableSsl,
            Credentials = new NetworkCredential(settings.SenderEmail, settings.Password),
            DeliveryMethod = SmtpDeliveryMethod.Network
        };

        var mailMessage = new MailMessage
        {
            From = new MailAddress(settings.SenderEmail, settings.SenderName),
            Subject = subject,
            Body = htmlMessage,
            IsBodyHtml = true
        };
        mailMessage.To.Add(email);

        await client.SendMailAsync(mailMessage);
    }

    // 其他接口方法（重置密码等）也需要类似实现
    public Task SendPasswordResetLinkAsync(ApplicationUser user, string email, string resetLink) =>
        SendEmailAsync(email, "重置密码", $"请点击链接重置密码：{resetLink}");

    public Task SendPasswordResetCodeAsync(ApplicationUser user, string email, string resetCode) =>
        SendEmailAsync(email, "重置密码验证码", $"您的验证码是：{resetCode}");
}