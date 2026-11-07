using System.Security.Cryptography;
using System.Text;

namespace Vilep.Api.Infrastructure;

/// <summary>
/// AES-256-GCM envelope for sensitive values (bank account numbers).
/// Key comes from configuration (Encryption:Key, base64) so the same ciphertext is readable
/// by every replica and no OS key store (DPAPI) is required — important for Docker/containers.
/// </summary>
public class Encryptor
{
    private readonly byte[] _key;

    public Encryptor(IConfiguration config)
    {
        var raw = config["Encryption:Key"];
        _key = string.IsNullOrWhiteSpace(raw)
            ? SHA256.HashData(Encoding.UTF8.GetBytes(config["Jwt:Key"] ?? "vilep-dev"))
            : Convert.FromBase64String(raw);
        if (_key.Length != 32) throw new InvalidOperationException("Encryption:Key must be 32 bytes (base64)");
    }

    public string Encrypt(string plain)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var plainBytes = Encoding.UTF8.GetBytes(plain);
        var cipher = new byte[plainBytes.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(_key, 16);
        aes.Encrypt(nonce, plainBytes, cipher, tag);
        return Convert.ToBase64String([.. nonce, .. tag, .. cipher]);
    }

    public string Decrypt(string cipherText)
    {
        var data = Convert.FromBase64String(cipherText);
        var nonce = data.AsSpan(0, 12);
        var tag = data.AsSpan(12, 16);
        var cipher = data.AsSpan(28);
        var plain = new byte[cipher.Length];
        using var aes = new AesGcm(_key, 16);
        aes.Decrypt(nonce, cipher, tag, plain);
        return Encoding.UTF8.GetString(plain);
    }

    public string Last4(string plain) => plain.Length <= 4 ? plain : plain[^4..];
}
