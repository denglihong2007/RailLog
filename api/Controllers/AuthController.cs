using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController(
    RailLogDatabase database,
    EmailVerificationService verificationService) : ControllerBase
{
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest request)
    {
        if (!await verificationService.VerifyAndConsumeAsync(
                request.Email,
                VerificationPurpose.Register,
                request.VerificationCode))
            return BadRequest(new MessageResponse("验证码错误或已失效"));
        var result = await database.RegisterAsync(request);
        return result.Response is null ? BadRequest(new MessageResponse(result.Error!)) : Ok(result.Response);
    }

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest request)
    {
        var response = await database.LoginAsync(request);
        return response is null
            ? Unauthorized(new MessageResponse("邮箱或密码错误"))
            : Ok(response);
    }

    [Authorize]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        var token = Request.Headers.Authorization.ToString()["Bearer ".Length..].Trim();
        await database.RevokeTokenAsync(token);
        return NoContent();
    }

    [HttpPost("verification-code")]
    public async Task<ActionResult<MessageResponse>> SendVerificationCode(
        SendVerificationCodeRequest request,
        CancellationToken cancellationToken)
    {
        if (!EmailVerificationService.TryParsePurpose(request.Purpose, out var purpose))
            return BadRequest(new MessageResponse("不支持的验证码用途"));
        try
        {
            await verificationService.RequestCodeAsync(
                request.Email,
                purpose,
                cancellationToken);
            return Ok(new MessageResponse("验证码已发送，请检查邮箱"));
        }
        catch (VerificationException exception)
        {
            return BadRequest(new MessageResponse(exception.Message));
        }
        catch (EmailDeliveryException exception)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new MessageResponse(exception.Message));
        }
    }

    [HttpPost("reset-password")]
    public async Task<ActionResult<MessageResponse>> ResetPassword(ResetPasswordRequest request)
    {
        if (request.NewPassword.Length < 8)
            return BadRequest(new MessageResponse("密码至少需要 8 个字符"));
        if (!await verificationService.VerifyAndConsumeAsync(
                request.Email,
                VerificationPurpose.ResetPassword,
                request.VerificationCode))
            return BadRequest(new MessageResponse("验证码错误或已失效"));
        if (!await database.ResetPasswordAsync(request.Email, request.NewPassword))
            return BadRequest(new MessageResponse("密码重置失败"));
        return Ok(new MessageResponse("密码已重置，请使用新密码登录"));
    }

    [Authorize]
    [HttpDelete("account")]
    public async Task<IActionResult> DeleteAccount()
    {
        await database.DeleteAccountAsync(UserId);
        return NoContent();
    }

    private string UserId => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
}
