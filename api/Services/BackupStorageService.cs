using System.Net;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed record RemoteBackup(string Name, long SizeBytes, DateTime CreatedAt);

/// <summary>
/// 备份文件的对象存储读写。桶是私有的，只有服务端的访问密钥能读，
/// 因此这里直接存取数据库快照本身，不再做额外加密。
/// </summary>
public sealed class BackupStorageService : IDisposable
{
    private const string BackupNamePrefix = "raillog-";
    private const string BackupNameSuffix = ".db";
    private const int BufferSize = 64 * 1024;

    private readonly BackupStorageOptions _options;
    private readonly ILogger<BackupStorageService> _logger;
    private readonly IAmazonS3? _client;

    public BackupStorageService(
        IOptions<BackupStorageOptions> options,
        ILogger<BackupStorageService> logger)
    {
        _options = options.Value;
        _logger = logger;

        if (_options.IsConfigured)
        {
            var config = new AmazonS3Config
            {
                ServiceURL = _options.Endpoint,
                ForcePathStyle = true,
                AuthenticationRegion = string.IsNullOrWhiteSpace(_options.Region)
                    ? "us-east-1"
                    : _options.Region,
                // 桶端不要求分块校验，避免部分 S3 兼容实现拒绝 v4 SDK 默认的校验头。
                RequestChecksumCalculation = RequestChecksumCalculation.WHEN_REQUIRED,
            };
            _client = new AmazonS3Client(
                new BasicAWSCredentials(_options.AccessKey, _options.SecretKey), config);
        }
        else if (_options.IsPartiallyConfigured)
        {
            _logger.LogWarning("对象存储配置不完整，数据库备份将继续写入本地目录。");
        }
    }

    public bool IsEnabled => _client is not null;

    /// <summary>给管理后台展示的位置，不包含访问密钥。</summary>
    public string Location => $"s3://{_options.Bucket}/{Prefix}";

    private string Prefix => string.IsNullOrWhiteSpace(_options.Prefix)
        ? "backups"
        : _options.Prefix.Trim('/');

    public async Task<IReadOnlyList<RemoteBackup>> ListAsync(
        CancellationToken cancellationToken)
    {
        EnsureEnabled();
        var prefix = Prefix + "/";
        var items = new List<RemoteBackup>();
        string? continuationToken = null;

        do
        {
            var response = await _client!.ListObjectsV2Async(
                new ListObjectsV2Request
                {
                    BucketName = _options.Bucket,
                    Prefix = prefix,
                    ContinuationToken = continuationToken,
                },
                cancellationToken);

            foreach (var item in response.S3Objects ?? [])
            {
                var name = ParseBackupName(item.Key, prefix);
                if (name is null) continue;
                items.Add(new RemoteBackup(
                    name,
                    item.Size ?? 0,
                    item.LastModified?.ToUniversalTime() ?? DateTime.MinValue));
            }

            continuationToken = response.IsTruncated == true
                ? response.NextContinuationToken
                : null;
        }
        while (!string.IsNullOrEmpty(continuationToken));

        return items;
    }

    public async Task<bool> ExistsAsync(string name, CancellationToken cancellationToken)
    {
        EnsureEnabled();
        try
        {
            await _client!.GetObjectMetadataAsync(
                new GetObjectMetadataRequest
                {
                    BucketName = _options.Bucket,
                    Key = KeyFor(name),
                },
                cancellationToken);
            return true;
        }
        catch (AmazonS3Exception exception)
            when (exception.StatusCode == HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    public async Task UploadAsync(
        string name,
        string sourcePath,
        CancellationToken cancellationToken)
    {
        EnsureEnabled();
        await _client!.PutObjectAsync(
            new PutObjectRequest
            {
                BucketName = _options.Bucket,
                Key = KeyFor(name),
                FilePath = sourcePath,
                ContentType = "application/octet-stream",
            },
            cancellationToken);
    }

    /// <summary>下载到指定路径；调用方负责删除明文文件。</summary>
    public async Task DownloadAsync(
        string name,
        string destinationPath,
        CancellationToken cancellationToken)
    {
        EnsureEnabled();
        using var response = await _client!.GetObjectAsync(
            new GetObjectRequest
            {
                BucketName = _options.Bucket,
                Key = KeyFor(name),
            },
            cancellationToken);
        await using var source = response.ResponseStream;
        await using var destination = new FileStream(
            destinationPath,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            BufferSize,
            FileOptions.Asynchronous);
        await source.CopyToAsync(destination, BufferSize, cancellationToken);
        await destination.FlushAsync(cancellationToken);
    }

    public async Task DeleteAsync(string name, CancellationToken cancellationToken)
    {
        EnsureEnabled();
        await _client!.DeleteObjectAsync(
            new DeleteObjectRequest
            {
                BucketName = _options.Bucket,
                Key = KeyFor(name),
            },
            cancellationToken);
    }

    private string KeyFor(string name) => $"{Prefix}/{name}";

    private static string? ParseBackupName(string key, string prefix)
    {
        if (!key.StartsWith(prefix, StringComparison.Ordinal) ||
            !key.EndsWith(BackupNameSuffix, StringComparison.Ordinal))
            return null;

        var name = key[prefix.Length..];
        return name.StartsWith(BackupNamePrefix, StringComparison.Ordinal) &&
               !name.Contains('/')
            ? name
            : null;
    }

    private void EnsureEnabled()
    {
        if (_client is null)
            throw new InvalidOperationException("对象存储未配置，无法读写远程备份。");
    }

    public void Dispose() => _client?.Dispose();
}
