using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using RailLog.Models;

namespace RailLog.Services;

public sealed class BaiduTrainTicketOcrService(IHttpClientFactory httpClientFactory, IConfiguration configuration)
{
    public const int MaxImageBytes = 5 * 1024 * 1024;

    private const string TokenEndpoint = "oauth/2.0/token";
    private const string TicketOcrEndpoint = "rest/2.0/ocr/v1/train_ticket";

    public async Task<TrainTicketOcrResult> RecognizeAsync(byte[] imageBytes, CancellationToken cancellationToken = default)
    {
        if (imageBytes.Length == 0)
        {
            return TrainTicketOcrResult.Failed("上传图片不能为空。");
        }

        if (imageBytes.Length > MaxImageBytes)
        {
            return TrainTicketOcrResult.Failed($"图片大小不能超过 {MaxImageBytes / 1024 / 1024}MB。");
        }

        var apiKey = configuration["BaiduOcr:ApiKey"];
        var secretKey = configuration["BaiduOcr:SecretKey"];
        if (string.IsNullOrWhiteSpace(apiKey) || string.IsNullOrWhiteSpace(secretKey))
        {
            return TrainTicketOcrResult.Failed("未配置百度 OCR Key。请在配置中设置 BaiduOcr:ApiKey 和 BaiduOcr:SecretKey。");
        }

        var client = httpClientFactory.CreateClient("BaiduOcrApi");
        var tokenResult = await GetAccessTokenAsync(client, apiKey, secretKey, cancellationToken);
        if (!tokenResult.Success || string.IsNullOrWhiteSpace(tokenResult.AccessToken))
        {
            return TrainTicketOcrResult.Failed(tokenResult.ErrorMessage ?? "获取 OCR Access Token 失败。");
        }

        var imageBase64 = Convert.ToBase64String(imageBytes);
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{TicketOcrEndpoint}?access_token={Uri.EscapeDataString(tokenResult.AccessToken)}")
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["image"] = imageBase64
            })
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var response = await client.SendAsync(request, cancellationToken);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return TrainTicketOcrResult.Failed($"OCR 请求失败（HTTP {(int)response.StatusCode}）。");
        }

        BaiduTrainTicketOcrApiResponse? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<BaiduTrainTicketOcrApiResponse>(raw);
        }
        catch (JsonException)
        {
            return TrainTicketOcrResult.Failed("OCR 响应解析失败。");
        }

        if (parsed is null)
        {
            return TrainTicketOcrResult.Failed("OCR 响应为空。");
        }

        if (parsed.ErrorCode.HasValue)
        {
            return TrainTicketOcrResult.Failed($"OCR 服务错误：{parsed.ErrorMessage ?? parsed.ErrorCode.Value.ToString(CultureInfo.InvariantCulture)}");
        }

        if (parsed.WordsResult is null)
        {
            return TrainTicketOcrResult.Failed("未识别到车票字段。");
        }

        var words = parsed.WordsResult;
        return TrainTicketOcrResult.Succeeded(new TrainTicketOcrDto
        {
            TrainNumber = NormalizeTrainNumber(words.TrainNumber),
            TravelDate = ParseDate(words.Date),
            DepartureTime = ParseTime(words.Time),
            FromStation = NormalizeStation(words.StartingStation),
            ToStation = NormalizeStation(words.DestinationStation),
            SeatType = NormalizeText(words.SeatCategory),
            SeatNumber = NormalizeText(words.SeatNumber),
            Price = ParsePrice(words.TicketRates)
        });
    }

    private static async Task<TokenResult> GetAccessTokenAsync(HttpClient client, string apiKey, string secretKey, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, TokenEndpoint)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "client_credentials",
                ["client_id"] = apiKey,
                ["client_secret"] = secretKey
            })
        };
        using var response = await client.SendAsync(request, cancellationToken);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return TokenResult.Failed($"获取 Access Token 失败（HTTP {(int)response.StatusCode}）。");
        }

        BaiduTokenResponse? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<BaiduTokenResponse>(raw);
        }
        catch (JsonException)
        {
            return TokenResult.Failed("Access Token 响应解析失败。");
        }

        if (parsed is null || string.IsNullOrWhiteSpace(parsed.AccessToken))
        {
            return TokenResult.Failed(parsed?.ErrorDescription ?? "Access Token 为空。");
        }

        return TokenResult.Succeeded(parsed.AccessToken);
    }

    private static string NormalizeText(string? value)
    {
        return value?.Trim() ?? string.Empty;
    }

    private static string NormalizeTrainNumber(string? value)
    {
        var text = NormalizeText(value).Replace(" ", string.Empty, StringComparison.Ordinal).ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        var match = Regex.Match(text, @"[A-Z]\d{1,4}");
        if (match.Success)
        {
            return match.Value;
        }

        return text;
    }

    private static string NormalizeStation(string? value)
    {
        var text = NormalizeText(value);
        if (text.Length > 1 && text.EndsWith("站", StringComparison.Ordinal))
        {
            return text[..^1];
        }

        return text;
    }

    private static DateOnly? ParseDate(string? value)
    {
        var text = NormalizeText(value);
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var formats = new[] { "yyyy年MM月dd日", "yyyy-M-d", "yyyy-MM-dd", "yyyy/M/d", "yyyy/MM/dd" };
        if (DateOnly.TryParseExact(text, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
        {
            return date;
        }

        return null;
    }

    private static TimeOnly? ParseTime(string? value)
    {
        var text = NormalizeText(value);
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var formats = new[] { "HH:mm", "H:mm" };
        if (TimeOnly.TryParseExact(text, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var time))
        {
            return time;
        }

        return null;
    }

    private static decimal? ParsePrice(string? value)
    {
        var text = NormalizeText(value);
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var match = Regex.Match(text, @"\d+(?:\.\d+)?");
        if (!match.Success)
        {
            return null;
        }

        if (!decimal.TryParse(match.Value, NumberStyles.Number, CultureInfo.InvariantCulture, out var price))
        {
            return null;
        }

        return price > 0 ? price : null;
    }

    private sealed record TokenResult(bool Success, string? AccessToken, string? ErrorMessage)
    {
        public static TokenResult Succeeded(string token) => new(true, token, null);
        public static TokenResult Failed(string message) => new(false, null, message);
    }

    private sealed class BaiduTokenResponse
    {
        [JsonPropertyName("access_token")]
        public string? AccessToken { get; set; }

        [JsonPropertyName("error_description")]
        public string? ErrorDescription { get; set; }
    }

    private sealed class BaiduTrainTicketOcrApiResponse
    {
        [JsonPropertyName("words_result")]
        public BaiduTrainTicketWordsResult? WordsResult { get; set; }

        [JsonPropertyName("error_code")]
        public int? ErrorCode { get; set; }

        [JsonPropertyName("error_msg")]
        public string? ErrorMessage { get; set; }
    }

    private sealed class BaiduTrainTicketWordsResult
    {
        [JsonPropertyName("train_num")]
        public string? TrainNumber { get; set; }

        [JsonPropertyName("date")]
        public string? Date { get; set; }

        [JsonPropertyName("time")]
        public string? Time { get; set; }

        [JsonPropertyName("starting_station")]
        public string? StartingStation { get; set; }

        [JsonPropertyName("destination_station")]
        public string? DestinationStation { get; set; }

        [JsonPropertyName("seat_category")]
        public string? SeatCategory { get; set; }

        [JsonPropertyName("seat_num")]
        public string? SeatNumber { get; set; }

        [JsonPropertyName("ticket_rates")]
        public string? TicketRates { get; set; }
    }
}
