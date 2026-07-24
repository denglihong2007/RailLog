using System.Collections.Concurrent;
using System.Security.Cryptography;

namespace RailLog.API.Services;

public sealed class TicketDownloadLinkStore : IDisposable
{
    private static readonly TimeSpan LinkLifetime = TimeSpan.FromHours(1);
    private readonly ConcurrentDictionary<string, StoredTicketDownload> _downloads = new();
    private readonly Timer _cleanupTimer;

    public TicketDownloadLinkStore()
    {
        _cleanupTimer = new Timer(
            _ => RemoveExpired(),
            null,
            TimeSpan.FromMinutes(5),
            TimeSpan.FromMinutes(5));
    }

    public (string Token, DateTime ExpiresAt) Add(TicketDownloadResult download)
    {
        RemoveExpired();
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        var expiresAt = DateTime.Now.Add(LinkLifetime);
        _downloads[token] = new StoredTicketDownload(
            download.FilePath,
            download.ContentType,
            download.FileName,
            expiresAt);
        return (token, expiresAt);
    }

    public OpenTicketDownload? Open(string token)
    {
        if (string.IsNullOrWhiteSpace(token) ||
            !_downloads.TryGetValue(token, out var download))
            return null;
        if (download.ExpiresAt <= DateTime.Now || !File.Exists(download.FilePath))
        {
            Remove(token, download);
            return null;
        }
        try
        {
            var stream = new FileStream(
                download.FilePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read | FileShare.Delete,
                bufferSize: 64 * 1024,
                options: FileOptions.Asynchronous | FileOptions.SequentialScan);
            return new OpenTicketDownload(stream, download.ContentType, download.FileName);
        }
        catch (FileNotFoundException)
        {
            Remove(token, download);
            return null;
        }
    }

    private void RemoveExpired()
    {
        var now = DateTime.Now;
        foreach (var item in _downloads)
        {
            if (item.Value.ExpiresAt <= now) Remove(item.Key, item.Value);
        }
    }

    private void Remove(string token, StoredTicketDownload download)
    {
        if (!_downloads.TryRemove(new KeyValuePair<string, StoredTicketDownload>(token, download)))
            return;
        try { File.Delete(download.FilePath); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public void Dispose()
    {
        _cleanupTimer.Dispose();
        foreach (var item in _downloads) Remove(item.Key, item.Value);
    }
}

public sealed record StoredTicketDownload(
    string FilePath,
    string ContentType,
    string FileName,
    DateTime ExpiresAt);
public sealed record OpenTicketDownload(Stream Stream, string ContentType, string FileName);
