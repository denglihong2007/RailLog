using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class AmapOptions
{
    public string WebApiKey { get; set; } = string.Empty;
}

public sealed class AmapProxyService(
    HttpClient httpClient,
    IOptions<AmapOptions> options)
{
    private readonly AmapOptions _options = options.Value;

    public Task<HttpResponseMessage> GetMapsSdkAsync(
        CancellationToken cancellationToken) => SendAsync(
        "https://webapi.amap.com/maps?v=2.0" +
        $"&key={Uri.EscapeDataString(RequiredWebApiKey())}" +
        "&plugin=AMap.Scale,AMap.ToolBar",
        cancellationToken);

    public Task<HttpResponseMessage> GetLocaSdkAsync(
        CancellationToken cancellationToken) => SendAsync(
        "https://webapi.amap.com/loca?v=2.0.0" +
        $"&key={Uri.EscapeDataString(RequiredWebApiKey())}",
        cancellationToken);

    private async Task<HttpResponseMessage> SendAsync(
        string target,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, target);
        return await httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
    }

    private string RequiredWebApiKey() => Required(
        _options.WebApiKey,
        "Amap__WebApiKey");

    private static string Required(string value, string environmentVariable) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException(
                $"AMap proxy is not configured. Set {environmentVariable}.")
            : value.Trim();
}
