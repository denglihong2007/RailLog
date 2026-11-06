namespace RailLog.API.Services;

/// <summary>
/// 备份的对象存储配置。备份文件含用户数据，而对象存储桶允许公开读取，
/// 因此上传前必须用 <see cref="Passphrase"/> 派生的密钥加密。
/// 密钥通过环境变量 DatabaseBackup__Storage__* 注入，不写入仓库。
/// </summary>
public sealed class BackupStorageOptions
{
    public string Endpoint { get; init; } = "";
    public string Region { get; init; } = "cn-nb2";
    public string Bucket { get; init; } = "";
    public string Prefix { get; init; } = "backups";
    public string AccessKey { get; init; } = "";
    public string SecretKey { get; init; } = "";
    public string Passphrase { get; init; } = "";

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(Endpoint) &&
        !string.IsNullOrWhiteSpace(Bucket) &&
        !string.IsNullOrWhiteSpace(AccessKey) &&
        !string.IsNullOrWhiteSpace(SecretKey) &&
        !string.IsNullOrWhiteSpace(Passphrase);

    /// <summary>密钥配了一半时值得告警：备份会悄悄退回本地目录。</summary>
    public bool IsPartiallyConfigured =>
        !IsConfigured &&
        (!string.IsNullOrWhiteSpace(AccessKey) ||
         !string.IsNullOrWhiteSpace(SecretKey) ||
         !string.IsNullOrWhiteSpace(Passphrase));
}
