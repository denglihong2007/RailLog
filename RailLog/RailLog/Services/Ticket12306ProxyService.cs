using Microsoft.Extensions.Caching.Memory;
using System.Globalization;
using System.Net;
using System.Text.Json;

namespace RailLog.Services;

public sealed class Ticket12306ProxyService(IMemoryCache cache, ILogger<Ticket12306ProxyService> logger)
{
    private const string LoginPageUrl = "https://kyfw.12306.cn/otn/resources/login.html";
    private const string PassportRedirectUrl = "https://kyfw.12306.cn/otn/passport?redirect=/otn/login/userLogin";
    private const string TrainOrderPageUrl = "https://kyfw.12306.cn/otn/view/train_order.html";
    private const string PassportBaseUrl = "https://kyfw.12306.cn/passport/web";
    private const string OtnBaseUrl = "https://kyfw.12306.cn/otn";
    private const int MaxRedirects = 5;
    private const int OrderPageSize = 8;
    private const string SessionKeyPrefix = "12306:session:";

    public async Task<CreateQrCodeResponse> CreateQrCodeAsync(string userId, CancellationToken cancellationToken)
    {
        var session = CreateSession(userId);

        try
        {
            return await ExecuteInSessionAsync(session, async (current, ct) =>
            {
                using var request = BuildAjaxPostRequest(
                    $"{PassportBaseUrl}/create-qr64",
                    new Dictionary<string, string>
                    {
                        ["appid"] = "otn"
                    },
                    LoginPageUrl,
                    "*/*");
                using var doc = await SendJsonAsync(current.Client, request, ct);
                var uuid = ReadString(doc.RootElement, "uuid");
                var image = ReadString(doc.RootElement, "image");

                if (string.IsNullOrWhiteSpace(uuid) || string.IsNullOrWhiteSpace(image))
                {
                    throw new InvalidOperationException("12306 未返回有效二维码。");
                }

                return new CreateQrCodeResponse(
                    SessionId: current.SessionId,
                    Uuid: uuid,
                    Image: image);
            }, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to create 12306 qr code for user {UserId}", userId);
            RemoveSession(session.SessionId);
            throw;
        }
    }

    public async Task<QrStatusResponse> CheckQrStatusAsync(
        string userId,
        string sessionId,
        string uuid,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(uuid))
        {
            throw new InvalidOperationException("二维码 UUID 不能为空。");
        }

        var session = GetRequiredSession(userId, sessionId);
        return await ExecuteInSessionAsync(session, async (current, ct) =>
        {
            using var request = BuildAjaxPostRequest(
                $"{PassportBaseUrl}/checkqr",
                new Dictionary<string, string>
                {
                    ["uuid"] = uuid.Trim(),
                    ["appid"] = "otn"
                },
                LoginPageUrl,
                "*/*");
            using var doc = await SendJsonAsync(current.Client, request, ct);
            var resultCode = ReadResultCodeText(doc.RootElement);
            var resultMessage = ReadString(doc.RootElement, "result_message");
            var uamtk = ReadString(doc.RootElement, "uamtk");

            return new QrStatusResponse(
                ResultCode: resultCode,
                ResultMessage: resultMessage,
                Uamtk: uamtk);
        }, cancellationToken);
    }

    public async Task<CompleteLoginResponse> CompleteLoginAsync(
        string userId,
        string sessionId,
        string uamtk,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(uamtk))
        {
            throw new InvalidOperationException("扫码票据 (uamtk) 不能为空。");
        }

        var session = GetRequiredSession(userId, sessionId);
        return await ExecuteInSessionAsync(session, async (current, ct) =>
        {
            await NavigateWithRedirectsAsync($"{OtnBaseUrl}/login/userLogin", LoginPageUrl, current.Client, ct);

            current.CookieContainer.Add(
                new Uri("https://kyfw.12306.cn/passport/"),
                new Cookie("uamtk", uamtk.Trim(), "/passport", "kyfw.12306.cn"));

            using var authRequest = BuildAjaxPostRequest(
                $"{PassportBaseUrl}/auth/uamtk",
                new Dictionary<string, string>
                {
                    ["appid"] = "otn"
                },
                PassportRedirectUrl,
                "application/json, text/javascript, */*; q=0.01");
            using var authDoc = await SendJsonAsync(current.Client, authRequest, ct);
            if (ReadResultCode(authDoc.RootElement) != 0)
            {
                throw new InvalidOperationException("UAMTK 验证失败：" + ReadString(authDoc.RootElement, "result_message"));
            }

            var newAppTk = ReadString(authDoc.RootElement, "newapptk");
            if (string.IsNullOrWhiteSpace(newAppTk))
            {
                throw new InvalidOperationException("未获取到 newapptk。");
            }

            using var uamAuthRequest = BuildAjaxPostRequest(
                $"{OtnBaseUrl}/uamauthclient",
                new Dictionary<string, string>
                {
                    ["tk"] = newAppTk
                },
                PassportRedirectUrl,
                "*/*");
            using var uamAuthDoc = await SendJsonAsync(current.Client, uamAuthRequest, ct);
            if (ReadResultCode(uamAuthDoc.RootElement) != 0)
            {
                throw new InvalidOperationException("UamAuthClient 认证失败：" + ReadString(uamAuthDoc.RootElement, "result_message"));
            }

            var username = ReadString(uamAuthDoc.RootElement, "username");
            await NavigateWithRedirectsAsync($"{OtnBaseUrl}/login/userLogin", PassportRedirectUrl, current.Client, ct);

            return new CompleteLoginResponse(Username: username);
        }, cancellationToken);
    }

    public async Task<IReadOnlyList<OrderTicketResponse>> QueryOrdersAsync(
        string userId,
        string sessionId,
        CancellationToken cancellationToken)
    {
        var session = GetRequiredSession(userId, sessionId);
        return await ExecuteInSessionAsync(session, async (current, ct) =>
        {
            await NavigateWithRedirectsAsync(TrainOrderPageUrl, $"{OtnBaseUrl}/login/userLogin", current.Client, ct);

            var startDate = DateOnly.FromDateTime(DateTime.Today.AddMonths(-1));
            var historyEndDate = DateOnly.FromDateTime(DateTime.Today.AddDays(-1));
            var upcomingEndDate = DateOnly.FromDateTime(DateTime.Today);

            var merged = new Dictionary<string, OrderTicketResponse>(StringComparer.Ordinal);

            var historyTickets = await QueryOrdersByTypeAsync(current.Client, startDate, historyEndDate, "H", ct);
            foreach (var ticket in historyTickets)
            {
                merged[BuildMergeKey(ticket)] = ticket;
            }

            var upcomingTickets = await QueryOrdersByTypeAsync(current.Client, startDate, upcomingEndDate, "G", ct);
            foreach (var ticket in upcomingTickets)
            {
                merged[BuildMergeKey(ticket)] = ticket;
            }

            return merged.Values.ToList();
        }, cancellationToken);
    }

    private async Task<List<OrderTicketResponse>> QueryOrdersByTypeAsync(
        HttpClient client,
        DateOnly startDate,
        DateOnly endDate,
        string queryWhere,
        CancellationToken cancellationToken)
    {
        var tickets = new List<OrderTicketResponse>();
        if (endDate < startDate)
        {
            return tickets;
        }

        var pageIndex = 0;
        var totalOrderCount = int.MaxValue;

        while (pageIndex * OrderPageSize < totalOrderCount)
        {
            using var request = BuildAjaxPostRequest(
                $"{OtnBaseUrl}/queryOrder/queryMyOrder",
                new Dictionary<string, string>
                {
                    ["come_from_flag"] = "my_order",
                    ["pageIndex"] = pageIndex.ToString(CultureInfo.InvariantCulture),
                    ["pageSize"] = OrderPageSize.ToString(CultureInfo.InvariantCulture),
                    ["query_where"] = queryWhere,
                    ["queryStartDate"] = startDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    ["queryEndDate"] = endDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    ["queryType"] = "1",
                    ["sequeue_train_name"] = string.Empty
                },
                TrainOrderPageUrl,
                "application/json, text/javascript, */*; q=0.01");
            using var doc = await SendJsonAsync(client, request, cancellationToken);
            var root = doc.RootElement;

            if (!root.TryGetProperty("status", out var statusElement) || statusElement.ValueKind != JsonValueKind.True)
            {
                throw new InvalidOperationException($"12306 订单查询失败：query_where={queryWhere} status=false。");
            }

            if (!root.TryGetProperty("data", out var dataElement) ||
                !dataElement.TryGetProperty("OrderDTODataList", out var orderListElement) ||
                orderListElement.ValueKind != JsonValueKind.Array)
            {
                break;
            }

            if (TryGetIntValue(dataElement, "order_total_number", out var parsedTotal) && parsedTotal > 0)
            {
                totalOrderCount = parsedTotal;
            }

            var currentCount = 0;
            var orderIndex = 0;

            foreach (var order in orderListElement.EnumerateArray())
            {
                currentCount++;
                var sequenceNo = ReadString(order, "sequence_no");

                if (!order.TryGetProperty("tickets", out var ticketsElement) || ticketsElement.ValueKind != JsonValueKind.Array)
                {
                    orderIndex++;
                    continue;
                }

                var ticketIndex = 0;
                foreach (var ticket in ticketsElement.EnumerateArray())
                {
                    var startTime = ReadString(ticket, "start_train_date_page");
                    var arriveTime = startTime;
                    var trainCode = string.Empty;
                    var fromStation = string.Empty;
                    var toStation = string.Empty;
                    var distance = string.Empty;

                    if (ticket.TryGetProperty("stationTrainDTO", out var stationTrainElement) &&
                        stationTrainElement.ValueKind == JsonValueKind.Object)
                    {
                        trainCode = ReadString(stationTrainElement, "station_train_code");
                        fromStation = ReadString(stationTrainElement, "from_station_name");
                        toStation = ReadString(stationTrainElement, "to_station_name");
                        distance = ReadString(stationTrainElement, "distance");

                        var arriveDate = ExtractDatePart(ReadString(stationTrainElement, "arrive_date_local"));
                        var arriveClock = ExtractTimePart(ReadString(stationTrainElement, "arrive_time_local"));
                        if (!string.IsNullOrWhiteSpace(arriveDate) && !string.IsNullOrWhiteSpace(arriveClock))
                        {
                            arriveTime = $"{arriveDate} {arriveClock}";
                        }
                    }

                    var passengerName = string.Empty;
                    if (ticket.TryGetProperty("passengerDTO", out var passengerElement) &&
                        passengerElement.ValueKind == JsonValueKind.Object)
                    {
                        passengerName = ReadString(passengerElement, "passenger_name");
                    }

                    var seatType = ReadString(ticket, "seat_type_name");
                    var coachName = ReadString(ticket, "coach_name");
                    var seatName = ReadString(ticket, "seat_name");
                    var seatDisplay = BuildSeatDisplay(seatType, coachName, seatName);

                    tickets.Add(new OrderTicketResponse(
                        Id: BuildTicketId(sequenceNo, pageIndex, orderIndex, ticketIndex, trainCode, startTime, passengerName),
                        SequenceNo: sequenceNo,
                        StartTime: startTime,
                        ArriveTime: arriveTime,
                        TrainCode: trainCode,
                        FromStation: fromStation,
                        ToStation: toStation,
                        Distance: distance,
                        PassengerName: passengerName,
                        SeatType: seatType,
                        CoachName: coachName,
                        SeatName: seatName,
                        SeatDisplay: seatDisplay,
                        PriceText: ReadString(ticket, "str_ticket_price_page"),
                        StatusText: ReadString(ticket, "ticket_status_name")));

                    ticketIndex++;
                }

                orderIndex++;
            }

            if (currentCount < OrderPageSize)
            {
                break;
            }

            pageIndex++;
        }

        return tickets;
    }

    private Ticket12306Session CreateSession(string userId)
    {
        var session = new Ticket12306Session(userId);
        cache.Set(GetCacheKey(session.SessionId), session, CreateSessionCacheOptions());
        return session;
    }

    private Ticket12306Session GetRequiredSession(string userId, string sessionId)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            throw new InvalidOperationException("12306 会话无效，请重新扫码登录。");
        }

        if (!cache.TryGetValue(GetCacheKey(sessionId.Trim()), out Ticket12306Session? session) || session is null)
        {
            throw new InvalidOperationException("12306 会话已过期，请重新扫码登录。");
        }

        if (!string.Equals(session.UserId, userId, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("12306 会话与当前用户不匹配，请重新扫码登录。");
        }

        return session;
    }

    private void RemoveSession(string sessionId)
    {
        if (!string.IsNullOrWhiteSpace(sessionId))
        {
            cache.Remove(GetCacheKey(sessionId.Trim()));
        }
    }

    private static async Task<T> ExecuteInSessionAsync<T>(
        Ticket12306Session session,
        Func<Ticket12306Session, CancellationToken, Task<T>> operation,
        CancellationToken cancellationToken)
    {
        await session.Gate.WaitAsync(cancellationToken);
        try
        {
            return await operation(session, cancellationToken);
        }
        finally
        {
            session.Touch();
            session.Gate.Release();
        }
    }

    private static string GetCacheKey(string sessionId) => $"{SessionKeyPrefix}{sessionId}";

    private static MemoryCacheEntryOptions CreateSessionCacheOptions()
    {
        var options = new MemoryCacheEntryOptions
        {
            SlidingExpiration = TimeSpan.FromMinutes(20),
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(6)
        };
        options.RegisterPostEvictionCallback(static (_, value, _, _) =>
        {
            if (value is Ticket12306Session session)
            {
                session.Dispose();
            }
        });
        return options;
    }

    private static HttpRequestMessage BuildAjaxPostRequest(
        string url,
        IEnumerable<KeyValuePair<string, string>> formData,
        string referer,
        string accept)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new FormUrlEncodedContent(formData)
        };

        request.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        request.Headers.TryAddWithoutValidation("Origin", "https://kyfw.12306.cn");
        request.Headers.TryAddWithoutValidation("Accept", accept);
        request.Headers.Referrer = new Uri(referer);
        return request;
    }

    private static HttpRequestMessage BuildNavigateGetRequest(string url, string referer)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        request.Headers.Referrer = new Uri(referer);
        return request;
    }

    private static async Task<string> SendExpectBodyAsync(HttpClient client, HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var response = await client.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        response.EnsureSuccessStatusCode();
        return body;
    }

    private static async Task<JsonDocument> SendJsonAsync(HttpClient client, HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = await SendExpectBodyAsync(client, request, cancellationToken);
        try
        {
            return JsonDocument.Parse(body);
        }
        catch (JsonException ex)
        {
            throw new InvalidOperationException("12306 返回了无效 JSON。", ex);
        }
    }

    private static async Task NavigateWithRedirectsAsync(
        string startUrl,
        string referer,
        HttpClient client,
        CancellationToken cancellationToken)
    {
        var currentUrl = startUrl;
        var currentReferer = referer;

        for (var i = 0; i <= MaxRedirects; i++)
        {
            using var request = BuildNavigateGetRequest(currentUrl, currentReferer);
            using var response = await client.SendAsync(request, cancellationToken);
            _ = await response.Content.ReadAsStringAsync(cancellationToken);

            var statusCode = (int)response.StatusCode;
            if (statusCode >= 300 && statusCode < 400)
            {
                if (response.Headers.Location is null)
                {
                    throw new InvalidOperationException($"12306 导航重定向缺少 Location：{currentUrl}");
                }

                var nextUrl = response.Headers.Location.IsAbsoluteUri
                    ? response.Headers.Location
                    : new Uri(new Uri(currentUrl), response.Headers.Location);

                currentReferer = currentUrl;
                currentUrl = nextUrl.ToString();
                continue;
            }

            response.EnsureSuccessStatusCode();
            return;
        }

        throw new InvalidOperationException($"12306 导航重定向次数超过上限：{startUrl}");
    }

    private static int ReadResultCode(JsonElement root)
    {
        if (!root.TryGetProperty("result_code", out var codeElement))
        {
            return -1;
        }

        return codeElement.ValueKind switch
        {
            JsonValueKind.Number when codeElement.TryGetInt32(out var intCode) => intCode,
            JsonValueKind.String when int.TryParse(codeElement.GetString(), out var parsedCode) => parsedCode,
            _ => -1
        };
    }

    private static string ReadResultCodeText(JsonElement root)
    {
        if (!root.TryGetProperty("result_code", out var codeElement))
        {
            return string.Empty;
        }

        return codeElement.ValueKind switch
        {
            JsonValueKind.Number => codeElement.GetRawText(),
            JsonValueKind.String => codeElement.GetString() ?? string.Empty,
            _ => string.Empty
        };
    }

    private static string ReadString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property)
            ? property.GetString() ?? string.Empty
            : string.Empty;
    }

    private static bool TryGetIntValue(JsonElement element, string propertyName, out int value)
    {
        value = 0;
        if (!element.TryGetProperty(propertyName, out var property))
        {
            return false;
        }

        if (property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out var numberValue))
        {
            value = numberValue;
            return true;
        }

        if (property.ValueKind == JsonValueKind.String &&
            int.TryParse(property.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var stringValue))
        {
            value = stringValue;
            return true;
        }

        return false;
    }

    private static string ExtractDatePart(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        if (DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var parsed) ||
            DateTime.TryParse(value, CultureInfo.GetCultureInfo("zh-CN"), DateTimeStyles.AllowWhiteSpaces, out parsed))
        {
            return parsed.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        return value.Length >= 10 ? value[..10] : string.Empty;
    }

    private static string ExtractTimePart(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        if (DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var parsed) ||
            DateTime.TryParse(value, CultureInfo.GetCultureInfo("zh-CN"), DateTimeStyles.AllowWhiteSpaces, out parsed))
        {
            return parsed.ToString("HH:mm", CultureInfo.InvariantCulture);
        }

        var colonIndex = value.IndexOf(':');
        if (colonIndex >= 1)
        {
            var start = Math.Max(0, colonIndex - 2);
            if (start + 5 <= value.Length)
            {
                return value.Substring(start, 5);
            }
        }

        return string.Empty;
    }

    private static string BuildSeatDisplay(string seatType, string coachName, string seatName)
    {
        if (!string.IsNullOrWhiteSpace(seatType) &&
            !string.IsNullOrWhiteSpace(coachName) &&
            !string.IsNullOrWhiteSpace(seatName))
        {
            return $"{seatType} {coachName}车{seatName}";
        }

        if (!string.IsNullOrWhiteSpace(seatType))
        {
            return seatType;
        }

        if (!string.IsNullOrWhiteSpace(coachName) && !string.IsNullOrWhiteSpace(seatName))
        {
            return $"{coachName}车{seatName}";
        }

        if (!string.IsNullOrWhiteSpace(coachName))
        {
            return $"{coachName}车";
        }

        return seatName;
    }

    private static string BuildTicketId(
        string sequenceNo,
        int pageIndex,
        int orderIndex,
        int ticketIndex,
        string trainCode,
        string startTime,
        string passengerName)
    {
        return string.Join("|",
        [
            sequenceNo.Trim(),
            pageIndex.ToString(CultureInfo.InvariantCulture),
            orderIndex.ToString(CultureInfo.InvariantCulture),
            ticketIndex.ToString(CultureInfo.InvariantCulture),
            trainCode.Trim(),
            startTime.Trim(),
            passengerName.Trim()
        ]);
    }

    private static string BuildMergeKey(OrderTicketResponse ticket)
    {
        return string.Join("|",
        [
            ticket.SequenceNo.Trim(),
            ticket.StartTime.Trim(),
            ticket.TrainCode.Trim(),
            ticket.FromStation.Trim(),
            ticket.ToStation.Trim(),
            ticket.PassengerName.Trim(),
            ticket.SeatName.Trim()
        ]);
    }

    private sealed class Ticket12306Session : IDisposable
    {
        private static readonly Version BrowserVersion = new(146, 0, 0, 0);

        public Ticket12306Session(string userId)
        {
            UserId = userId;
            SessionId = Guid.NewGuid().ToString("N");
            CookieContainer = new CookieContainer();
            Handler = new HttpClientHandler
            {
                CookieContainer = CookieContainer,
                UseCookies = true,
                AllowAutoRedirect = false,
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli
            };

            Client = new HttpClient(Handler)
            {
                Timeout = TimeSpan.FromSeconds(30)
            };
            Client.DefaultRequestHeaders.TryAddWithoutValidation(
                "User-Agent",
                $"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{BrowserVersion} Safari/537.36 Edg/{BrowserVersion}");
            Client.DefaultRequestHeaders.TryAddWithoutValidation("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8");
        }

        public string UserId { get; }

        public string SessionId { get; }

        public CookieContainer CookieContainer { get; }

        public HttpClientHandler Handler { get; }

        public HttpClient Client { get; }

        public SemaphoreSlim Gate { get; } = new(1, 1);

        public void Touch()
        {
            _ = DateTime.UtcNow;
        }

        public void Dispose()
        {
            Gate.Dispose();
            Client.Dispose();
            Handler.Dispose();
        }
    }
}

public sealed record CreateQrCodeResponse(string SessionId, string Uuid, string Image);

public sealed record QrStatusResponse(string ResultCode, string ResultMessage, string Uamtk);

public sealed record CompleteLoginResponse(string Username);

public sealed record OrderTicketResponse(
    string Id,
    string SequenceNo,
    string StartTime,
    string ArriveTime,
    string TrainCode,
    string FromStation,
    string ToStation,
    string Distance,
    string PassengerName,
    string SeatType,
    string CoachName,
    string SeatName,
    string SeatDisplay,
    string PriceText,
    string StatusText);

public sealed record CheckQrRequest(string SessionId, string Uuid);

public sealed record CompleteLoginRequest(string SessionId, string Uamtk);

public sealed record QueryOrdersRequest(string SessionId);
