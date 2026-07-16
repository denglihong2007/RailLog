using System.Security.Cryptography;
using Microsoft.AspNetCore.Cryptography.KeyDerivation;

namespace RailLog.API.Services;

public static class IdentityPasswordHasher
{
    private const byte FormatVersion = 0x01; // v3 版本号
    private const KeyDerivationPrf Prf = KeyDerivationPrf.HMACSHA256; // 默认算法
    private const int IterationCount = 100000; // 默认迭代次数
    private const int SaltSize = 16; // 盐值 128-bit
    private const int SubkeySize = 32; // 哈希密文 256-bit

    /// <summary>
    /// 验证明文密码是否与数据库中的旧哈希值匹配
    /// </summary>
    /// <param name="hashedPassword">数据库中存储的密文 (Base64 字符串)</param>
    /// <param name="providedPassword">用户登录时输入的明文密码</param>
    /// <returns>是否验证通过</returns>
    public static bool VerifyHashedPassword(string? hashedPassword, string providedPassword)
    {
        if (string.IsNullOrEmpty(hashedPassword) || string.IsNullOrEmpty(providedPassword))
        {
            return false;
        }

        try
        {
            // 1. Base64 解码成二进制数组
            byte[] decodedHashedPassword = Convert.FromBase64String(hashedPassword);

            // 2. 检查版本号是否为 v3 (0x01)
            if (decodedHashedPassword.Length == 0 || decodedHashedPassword[0] != FormatVersion)
            {
                return false; // 版本不匹配或数据损坏
            }

            // 3. 读取 PRF 算法 (4 字节，大端序)
            uint prfId = ReadNetworkByteOrder(decodedHashedPassword, 1);
            KeyDerivationPrf prf = (KeyDerivationPrf)prfId;

            // 4. 读取迭代次数 (4 字节，大端序)
            int iterCount = (int)ReadNetworkByteOrder(decodedHashedPassword, 5);

            // 5. 读取盐值长度 (4 字节，大端序)
            int saltLength = (int)ReadNetworkByteOrder(decodedHashedPassword, 9);
            if (saltLength != SaltSize)
            {
                return false;
            }

            // 6. 提取盐值 (Salt)
            byte[] salt = new byte[saltLength];
            Buffer.BlockCopy(decodedHashedPassword, 13, salt, 0, salt.Length);

            // 7. 提取预期的哈希密文 (Subkey)
            int subkeyLength = decodedHashedPassword.Length - 13 - salt.Length;
            if (subkeyLength != SubkeySize)
            {
                return false;
            }
            byte[] expectedSubkey = new byte[subkeyLength];
            Buffer.BlockCopy(decodedHashedPassword, 13 + salt.Length, expectedSubkey, 0, expectedSubkey.Length);

            // 8. 使用相同的参数对用户输入的明文密码进行 PBKDF2 哈希计算
            byte[] actualSubkey = KeyDerivation.Pbkdf2(providedPassword, salt, prf, iterCount, subkeyLength);

            // 9. 使用固定时间比较防止时序攻击 (Timing Attack)
            return CryptographicOperations.FixedTimeEquals(actualSubkey, expectedSubkey);
        }
        catch
        {
            return false; // 解析过程中发生异常视为验证失败
        }
    }

    /// <summary>
    /// (可选) 如果你在新系统中需要给新用户注册加密，可以使用这个方法生成兼容 Identity 格式的密文
    /// </summary>
    public static string HashPassword(string password)
    {
        if (password == null) throw new ArgumentNullException(nameof(password));

        // 1. 生成 16 字节随机盐值
        byte[] salt = RandomNumberGenerator.GetBytes(SaltSize);

        // 2. 计算 PBKDF2 哈希
        byte[] subkey = KeyDerivation.Pbkdf2(password, salt, Prf, IterationCount, SubkeySize);

        // 3. 申请最终打包的二进制数组空间 (1 + 4 + 4 + 4 + 16 + 32 = 61 字节)
        byte[] outputBytes = new byte[13 + salt.Length + subkey.Length];

        outputBytes[0] = FormatVersion;
        WriteNetworkByteOrder(outputBytes, 1, (uint)Prf);
        WriteNetworkByteOrder(outputBytes, 5, (uint)IterationCount);
        WriteNetworkByteOrder(outputBytes, 9, (uint)SaltSize);
        Buffer.BlockCopy(salt, 0, outputBytes, 13, salt.Length);
        Buffer.BlockCopy(subkey, 0, outputBytes, 13 + salt.Length, subkey.Length);

        // 4. 返回 Base64 字符串存储到数据库
        return Convert.ToBase64String(outputBytes);
    }

    // 辅助工具：读取大端序字节
    private static uint ReadNetworkByteOrder(byte[] buffer, int offset)
    {
        return ((uint)(buffer[offset]) << 24)
            | ((uint)(buffer[offset + 1]) << 16)
            | ((uint)(buffer[offset + 2]) << 8)
            | buffer[offset + 3];
    }

    // 辅助工具：写入大端序字节
    private static void WriteNetworkByteOrder(byte[] buffer, int offset, uint value)
    {
        buffer[offset] = (byte)(value >> 24);
        buffer[offset + 1] = (byte)(value >> 16);
        buffer[offset + 2] = (byte)(value >> 8);
        buffer[offset + 3] = (byte)value;
    }
}