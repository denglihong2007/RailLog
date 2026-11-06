#!/usr/bin/env python3
"""解密 RailLog 上传到对象存储的备份文件（RLBK1 格式）。

需要 Python 3.8+ 与 cryptography：

    pip install cryptography

用法：

    python tools/decrypt-backup.py -i raillog-20261106-120000000Z.db.enc -o raillog.db

口令优先从环境变量 RAILLOG_BACKUP_PASSPHRASE 读取，也可以用 -p 传入。
口令即服务器 web.config 中的 DatabaseBackup__Storage__Passphrase。
"""

import argparse
import hashlib
import hmac
import os
import sys
from pathlib import Path

MAGIC = b"RLBK1"
SALT_SIZE = 16
IV_SIZE = 16
MAC_SIZE = 32
PBKDF2_ITERATIONS = 210_000


def decrypt(data: bytes, passphrase: str) -> bytes:
    minimum = len(MAGIC) + SALT_SIZE + IV_SIZE + MAC_SIZE + 16
    if len(data) < minimum:
        raise ValueError("文件过短，不是完整的加密备份")
    if data[: len(MAGIC)] != MAGIC:
        raise ValueError("文件头不是 RLBK1，可能不是 RailLog 加密备份")

    offset = len(MAGIC)
    salt = data[offset : offset + SALT_SIZE]
    offset += SALT_SIZE
    iv = data[offset : offset + IV_SIZE]
    offset += IV_SIZE
    ciphertext = data[offset:-MAC_SIZE]
    mac = data[-MAC_SIZE:]

    material = hashlib.pbkdf2_hmac(
        "sha256", passphrase.encode("utf-8"), salt, PBKDF2_ITERATIONS, dklen=64
    )
    encryption_key, mac_key = material[:32], material[32:]

    expected = hmac.new(mac_key, data[:-MAC_SIZE], hashlib.sha256).digest()
    if not hmac.compare_digest(expected, mac):
        raise ValueError("校验失败：口令错误或文件已损坏")

    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    decryptor = Cipher(algorithms.AES(encryption_key), modes.CBC(iv)).decryptor()
    plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    padding = plaintext[-1]
    if not 1 <= padding <= 16 or plaintext[-padding:] != bytes([padding]) * padding:
        raise ValueError("填充无效，文件可能已损坏")
    return plaintext[:-padding]


def main() -> int:
    parser = argparse.ArgumentParser(description="解密 RailLog 对象存储备份")
    parser.add_argument("-i", "--input", required=True, help="加密备份文件路径")
    parser.add_argument("-o", "--output", required=True, help="解密后的数据库路径")
    parser.add_argument(
        "-p",
        "--passphrase",
        default=os.environ.get("RAILLOG_BACKUP_PASSPHRASE"),
        help="加密口令，默认读取 RAILLOG_BACKUP_PASSPHRASE",
    )
    args = parser.parse_args()

    if not args.passphrase:
        print(
            "缺少口令：请设置 RAILLOG_BACKUP_PASSPHRASE 或使用 -p 传入。",
            file=sys.stderr,
        )
        return 2

    source = Path(args.input)
    if not source.is_file():
        print(f"找不到输入文件：{source}", file=sys.stderr)
        return 2

    try:
        plaintext = decrypt(source.read_bytes(), args.passphrase)
    except ValueError as error:
        print(f"解密失败：{error}", file=sys.stderr)
        return 1

    destination = Path(args.output)
    destination.write_bytes(plaintext)
    print(f"已解密到 {destination}（{len(plaintext)} 字节）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
