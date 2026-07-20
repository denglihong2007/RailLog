using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using RailLog.API.Models;

namespace RailLog.API.Services;

public sealed partial class TicketGeneratorService(
    RailLogDatabase database,
    StationPinyinService stationPinyin,
    TicketRenderer renderer,
    HttpClient httpClient,
    IOptions<TicketPdfOptions> pdfOptions)
{
    private const string DefaultRestrictionText = "限乘当日当次车";
    private const string DefaultMemorialText = "仅供收藏纪念使用";
    private const string DefaultNoticeLine1 = "买票请到12306  发货请到95306";
    private const string DefaultNoticeLine2 = "中国铁路祝您旅途愉快";

    public async Task<TicketGenerationResult?> GenerateAsync(
        GenerateTicketRequest request,
        bool pdf,
        CancellationToken cancellationToken) =>
        await GenerateAsync(request, pdf, TicketText.Default, cancellationToken);

    private async Task<TicketGenerationResult?> GenerateAsync(
        GenerateTicketRequest request,
        bool pdf,
        TicketText text,
        CancellationToken cancellationToken)
    {
        var error = Validate(request, out var style);
        if (error is not null) throw new TicketRequestException(error);
        var details = await database.GetPublicTripDetailsAsync(request.TripId);
        if (details is null) return null;
        var trip = details.Trip;

        var ticketNumber = $"A{trip.TicketId.ToString("D6", CultureInfo.InvariantCulture)}";
        var fromPinyinTask = stationPinyin.ResolveAsync(trip.FromStation, cancellationToken);
        var toPinyinTask = stationPinyin.ResolveAsync(trip.ToStation, cancellationToken);
        var qrTask = DownloadQrAsync(trip.TicketId, cancellationToken);
        await Task.WhenAll(fromPinyinTask, toPinyinTask, qrTask);
        var data = new TicketRenderData(
            style,
            ticketNumber,
            trip.FromStation,
            await fromPinyinTask,
            trip.ToStation,
            await toPinyinTask,
            trip.TrainNumber,
            trip.DepartureTime ?? trip.CreatedAt,
            FormatCarriageSeat(trip.SeatNumber, trip.SeatType),
            trip.Price,
            FormatSeatClass(trip.SeatType, request.ShowNewAirConditioned),
            request.Passenger.Trim(),
            request.MaskedId.Trim(),
            text.Restriction,
            text.Memorial,
            text.NoticeLine1,
            text.NoticeLine2,
            $"{request.SerialPrefix.Trim()}{ticketNumber}    JM");
        var bytes = pdf
            ? renderer.RenderPdf(data, await qrTask)
            : renderer.RenderPng(data, await qrTask, includeBackground: true);
        return new TicketGenerationResult(bytes, ticketNumber, style);
    }

    public async Task<TicketGenerationResult?> GenerateWebPdfAsync(
        DownloadTicketPdfRequest request,
        CancellationToken cancellationToken)
    {
        ValidatePdfPassword(request.Password);
        var normalizedKey = NormalizeDownloadKey(request.Key);
        var requestJson = await database.GetTicketPdfDownloadAsync(HashDownloadKey(normalizedKey));
        if (requestJson is null) throw new TicketPdfKeyException();
        var generationRequest = JsonSerializer.Deserialize<GenerateTicketRequest>(requestJson)
            ?? throw new TicketPdfKeyException();
        return await GenerateAsync(generationRequest, pdf: true,
            ResolvePdfText(request), cancellationToken);
    }

    public async Task<CreateTicketPdfKeyResponse?> CreatePdfKeyAsync(GenerateTicketRequest request)
    {
        var error = Validate(request, out _);
        if (error is not null) throw new TicketRequestException(error);
        if (await database.GetPublicTripDetailsAsync(request.TripId) is null) return null;

        var normalizedKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(8));
        var displayKey = string.Join('-', Enumerable.Range(0, 4)
            .Select(index => normalizedKey.Substring(index * 4, 4)));
        var expiresAt = DateTime.Now.AddHours(24);
        await database.CreateTicketPdfDownloadAsync(
            HashDownloadKey(normalizedKey),
            JsonSerializer.Serialize(request),
            expiresAt);
        return new CreateTicketPdfKeyResponse(displayKey, expiresAt);
    }

    private static TicketText ResolvePdfText(DownloadTicketPdfRequest request) => new(
        NormalizePdfText(request.RestrictionText, DefaultRestrictionText),
        NormalizePdfText(request.MemorialText, DefaultMemorialText),
        NormalizePdfText(request.NoticeLine1, DefaultNoticeLine1),
        NormalizePdfText(request.NoticeLine2, DefaultNoticeLine2));

    private static string NormalizePdfText(string? value, string fallback)
    {
        if (value is null) return fallback;
        return value;
    }

    private void ValidatePdfPassword(string? supplied)
    {
        var configured = pdfOptions.Value.DownloadPassword;
        if (string.IsNullOrWhiteSpace(configured))
            throw new TicketAssetException("服务端未配置 TicketPdf:DownloadPassword");
        if (string.IsNullOrEmpty(supplied) || supplied.Length > 256)
            throw new TicketPdfPasswordException();
        var expectedHash = SHA256.HashData(Encoding.UTF8.GetBytes(configured));
        var suppliedHash = SHA256.HashData(Encoding.UTF8.GetBytes(supplied));
        if (!CryptographicOperations.FixedTimeEquals(expectedHash, suppliedHash))
            throw new TicketPdfPasswordException();
    }

    private static string NormalizeDownloadKey(string? value)
    {
        var normalized = new string((value ?? string.Empty)
            .Where(Uri.IsHexDigit)
            .Select(char.ToUpperInvariant)
            .ToArray());
        if (normalized.Length != 16) throw new TicketPdfKeyException();
        return normalized;
    }

    private static string HashDownloadKey(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    private async Task<byte[]> DownloadQrAsync(long tripId, CancellationToken cancellationToken)
    {
        var target = $"https://www.raillog.top/?trip=1&id={tripId}";
        var path = $"qr?text={Uri.EscapeDataString(target)}&format=png&light=ffffff00&margin=0";
        using var response = await httpClient.GetAsync(path, cancellationToken);
        response.EnsureSuccessStatusCode();
        const int maximumBytes = 2 * 1024 * 1024;
        if (response.Content.Headers.ContentLength > maximumBytes)
            throw new InvalidOperationException("二维码响应过大");
        var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        if (bytes.Length > maximumBytes) throw new InvalidOperationException("二维码响应过大");
        return bytes;
    }

    private static string? Validate(GenerateTicketRequest request, out TicketStyle style)
    {
        style = string.IsNullOrWhiteSpace(request.Style)
            ? (TicketStyle)(-1)
            : request.Style.Trim().ToLowerInvariant() switch
        {
            "red" => TicketStyle.Red,
            "blue" => TicketStyle.Blue,
            _ => (TicketStyle)(-1),
        };
        if (!Enum.IsDefined(style)) return "车票样式只能是 red 或 blue";
        if (request.TripId <= 0) return "行程 ID 无效";
        if (string.IsNullOrWhiteSpace(request.Passenger)) return "请输入乘车人";
        if (request.Passenger.Trim().Length is < 1 or > 30) return "乘车人长度应为 1 至 30 个字符";
        if (string.IsNullOrWhiteSpace(request.MaskedId)) return "请输入脱敏身份证号码";
        if (request.MaskedId.Trim().Length is < 1 or > 30) return "脱敏身份证号码长度应为 1 至 30 个字符";
        if (string.IsNullOrWhiteSpace(request.SerialPrefix)) return "请输入票号前缀";
        if (!SerialPrefixRegex().IsMatch(request.SerialPrefix.Trim())) return "票号前缀必须是 14 位数字";
        return null;
    }

    private static string FormatSeatClass(string? value, bool showNewAirConditioned)
    {
        var seatClass = string.IsNullOrWhiteSpace(value) ? "未记录" : value.Trim();
        if (!showNewAirConditioned || seatClass.StartsWith("新空调", StringComparison.Ordinal) ||
            !IsConventionalSeatClass(seatClass))
            return seatClass;
        return $"新空调{seatClass}";
    }

    private static string FormatCarriageSeat(string? value, string? seatClass)
    {
        var normalized = string.IsNullOrWhiteSpace(value) ? "未记录" : value.Trim();
        var carriage = CarriageSeatRegex().Match(normalized);
        var prefix = string.Empty;
        var seat = normalized;
        if (carriage.Success)
        {
            prefix = $"{carriage.Groups["car"].Value.PadLeft(2, '0')}车";
            seat = carriage.Groups["seat"].Value;
        }

        if (IsConventionalSeatClass(seatClass))
        {
            var number = SeatNumberRegex().Match(seat);
            if (number.Success)
                seat = seat[..number.Index] + number.Value.PadLeft(3, '0') +
                       seat[(number.Index + number.Length)..];
        }
        else
        {
            var number = SeatNumberRegex().Match(seat);
            if (number.Success)
                seat = seat[..number.Index] + number.Value.PadLeft(2, '0') +
                       seat[(number.Index + number.Length)..];
        }
        return prefix + seat;
    }

    private static bool IsConventionalSeatClass(string? value) =>
        !string.IsNullOrWhiteSpace(value) && (value.Contains('硬') || value.Contains('软'));

    [GeneratedRegex("^[0-9]{14}$", RegexOptions.CultureInvariant)]
    private static partial Regex SerialPrefixRegex();

    [GeneratedRegex(@"^(?<car>\d+)\s*车\s*(?<seat>.*)$", RegexOptions.CultureInvariant)]
    private static partial Regex CarriageSeatRegex();

    [GeneratedRegex(@"\d+", RegexOptions.CultureInvariant)]
    private static partial Regex SeatNumberRegex();

    private sealed record TicketText(
        string Restriction,
        string Memorial,
        string NoticeLine1,
        string NoticeLine2)
    {
        public static TicketText Default { get; } = new(
            DefaultRestrictionText,
            DefaultMemorialText,
            DefaultNoticeLine1,
            DefaultNoticeLine2);
    }
}

public sealed record TicketGenerationResult(byte[] Bytes, string TicketNumber, TicketStyle Style);
public sealed class TicketRequestException(string message) : Exception(message);
public sealed class TicketPdfPasswordException : Exception;
public sealed class TicketPdfKeyException : Exception;
