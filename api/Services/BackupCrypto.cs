using System.Buffers;
using System.Security.Cryptography;
using System.Text;

namespace RailLog.API.Services;

/// <summary>
/// 备份文件的对称加密。对象存储桶是公开读的，上传前必须把数据库内容加密；
/// 下载时在服务端解密后再交给管理员。
///
/// 文件格式：
///   magic(5) | salt(16) | iv(16) | AES-256-CBC 密文 | HMAC-SHA256(32)
/// 加密密钥与校验密钥由口令经 PBKDF2-HMAC-SHA256 派生，先校验完整性再解密。
/// </summary>
public static class BackupCrypto
{
    private const int MagicSize = 5;
    private static readonly byte[] Magic = "RLBK1"u8.ToArray();
    private const int SaltSize = 16;
    private const int IvSize = 16;
    private const int MacSize = 32;
    private const int Pbkdf2Iterations = 210_000;
    private const int BufferSize = 64 * 1024;
    private const int HeaderSize = MagicSize + SaltSize + IvSize;

    public static async Task EncryptFileAsync(
        string sourcePath,
        string destinationPath,
        string passphrase,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(passphrase))
            throw new InvalidOperationException("未配置备份加密口令。");

        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var iv = RandomNumberGenerator.GetBytes(IvSize);
        var (encryptionKey, macKey) = DeriveKeys(passphrase, salt);

        await using var source = OpenRead(sourcePath);
        await using var destination = new FileStream(
            destinationPath,
            FileMode.Create,
            FileAccess.ReadWrite,
            FileShare.None,
            BufferSize,
            FileOptions.Asynchronous);

        await destination.WriteAsync(Magic, cancellationToken);
        await destination.WriteAsync(salt, cancellationToken);
        await destination.WriteAsync(iv, cancellationToken);

        using (var aes = Aes.Create())
        {
            aes.Key = encryptionKey;
            aes.IV = iv;
            aes.Mode = CipherMode.CBC;
            aes.Padding = PaddingMode.PKCS7;
            await using var crypto = new CryptoStream(
                destination, aes.CreateEncryptor(), CryptoStreamMode.Write, leaveOpen: true);
            await source.CopyToAsync(crypto, BufferSize, cancellationToken);
            await crypto.FlushFinalBlockAsync(cancellationToken);
        }

        await destination.FlushAsync(cancellationToken);

        // 完整性校验覆盖头部与全部密文，单独追加在文件末尾。
        destination.Position = 0;
        var mac = await ComputeMacAsync(
            destination, destination.Length, macKey, cancellationToken);
        destination.Position = destination.Length;
        await destination.WriteAsync(mac, cancellationToken);
        await destination.FlushAsync(cancellationToken);
    }

    public static async Task DecryptFileAsync(
        string sourcePath,
        string destinationPath,
        string passphrase,
        CancellationToken cancellationToken)
    {
        await using var source = OpenRead(sourcePath);
        if (source.Length < HeaderSize + MacSize + 16)
            throw new InvalidDataException("备份文件格式无效。");

        var header = new byte[HeaderSize];
        await source.ReadExactlyAsync(header, cancellationToken);
        if (!header.AsSpan(0, MagicSize).SequenceEqual(Magic))
            throw new InvalidDataException("不是 RailLog 加密备份文件。");

        var salt = header.AsSpan(MagicSize, SaltSize).ToArray();
        var iv = header.AsSpan(MagicSize + SaltSize, IvSize).ToArray();
        var (encryptionKey, macKey) = DeriveKeys(passphrase, salt);

        var cipherLength = source.Length - HeaderSize - MacSize;
        if (cipherLength <= 0)
            throw new InvalidDataException("备份文件格式无效。");

        // 先校验完整性再解密，口令错误或被篡改的文件不会产出半份数据库。
        source.Position = 0;
        var actualMac = await ComputeMacAsync(
            source, source.Length - MacSize, macKey, cancellationToken);
        var expectedMac = new byte[MacSize];
        await source.ReadExactlyAsync(expectedMac, cancellationToken);
        if (!CryptographicOperations.FixedTimeEquals(expectedMac, actualMac))
            throw new InvalidDataException("备份文件校验失败（口令错误或文件已损坏）。");

        source.Position = HeaderSize;
        await using var payload = new BoundedReadStream(source, cipherLength);
        using var aes = Aes.Create();
        aes.Key = encryptionKey;
        aes.IV = iv;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;
        await using var crypto = new CryptoStream(
            payload, aes.CreateDecryptor(), CryptoStreamMode.Read, leaveOpen: true);
        await using var destination = new FileStream(
            destinationPath,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            BufferSize,
            FileOptions.Asynchronous);
        await crypto.CopyToAsync(destination, BufferSize, cancellationToken);
        await destination.FlushAsync(cancellationToken);
    }

    private static (byte[] EncryptionKey, byte[] MacKey) DeriveKeys(
        string passphrase, byte[] salt)
    {
        var material = Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(passphrase),
            salt,
            Pbkdf2Iterations,
            HashAlgorithmName.SHA256,
            64);
        return (material[..32], material[32..]);
    }

    private static async Task<byte[]> ComputeMacAsync(
        Stream stream, long length, byte[] key, CancellationToken cancellationToken)
    {
        using var hmac = IncrementalHash.CreateHMAC(HashAlgorithmName.SHA256, key);
        var buffer = ArrayPool<byte>.Shared.Rent(BufferSize);
        try
        {
            var remaining = length;
            while (remaining > 0)
            {
                var read = await stream.ReadAsync(
                    buffer.AsMemory(0, (int)Math.Min(BufferSize, remaining)),
                    cancellationToken);
                if (read == 0) throw new EndOfStreamException("备份文件不完整。");
                hmac.AppendData(buffer, 0, read);
                remaining -= read;
            }
            return hmac.GetHashAndReset();
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    private static FileStream OpenRead(string path) => new(
        path,
        FileMode.Open,
        FileAccess.Read,
        FileShare.Read,
        BufferSize,
        FileOptions.Asynchronous | FileOptions.SequentialScan);

    /// <summary>只暴露指定长度的只读视图，避免解密时把末尾的 HMAC 当成密文。</summary>
    private sealed class BoundedReadStream(Stream inner, long length) : Stream
    {
        private long _remaining = length;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override void Flush()
        {
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            if (_remaining <= 0) return 0;
            var read = inner.Read(buffer, offset, (int)Math.Min(count, _remaining));
            _remaining -= read;
            return read;
        }

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (_remaining <= 0) return 0;
            var read = await inner.ReadAsync(
                buffer[..(int)Math.Min(buffer.Length, _remaining)],
                cancellationToken);
            _remaining -= read;
            return read;
        }

        public override long Seek(long offset, SeekOrigin origin) =>
            throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();
    }
}
