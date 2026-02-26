#!/usr/bin/env python3
"""
vw-credentials.py — Store credentials in Vaultwarden programmatically.

Handles the full Bitwarden protocol: user registration, authentication,
client-side encryption, and cipher creation.

Uses a deterministic service user derived from the admin token.
No manual interaction required.

Dependencies: Python 3.8+ (stdlib only — no external packages)

Usage:
    python3 vw-credentials.py --from-file /tmp/request.json

    python3 vw-credentials.py \
        --url http://127.0.0.1:8222 \
        --admin-token <token> \
        --action store \
        --name "My Credential" \
        --username "user" \
        --password "pass"
"""

import argparse
import base64
import hashlib
import hmac
import http.client
import json
import os
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request


# --- Pure-Python AES-256-CBC (no external dependencies) ---
# Implements AES per FIPS 197. Only CBC mode with PKCS7 padding.

# fmt: off
_SBOX = [
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
]
_INV_SBOX = [0] * 256
for _i, _v in enumerate(_SBOX):
    _INV_SBOX[_v] = _i

_RCON = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36]
# fmt: on


def _xtime(a):
    return ((a << 1) ^ 0x11B) & 0xFF if a & 0x80 else (a << 1) & 0xFF


def _mix_single(a):
    t = a[0] ^ a[1] ^ a[2] ^ a[3]
    u = a[0]
    a[0] ^= _xtime(a[0] ^ a[1]) ^ t
    a[1] ^= _xtime(a[1] ^ a[2]) ^ t
    a[2] ^= _xtime(a[2] ^ a[3]) ^ t
    a[3] ^= _xtime(a[3] ^ u) ^ t


def _inv_mix_single(a):
    u = _xtime(_xtime(a[0] ^ a[2]))
    v = _xtime(_xtime(a[1] ^ a[3]))
    a[0] ^= u; a[1] ^= v; a[2] ^= u; a[3] ^= v
    _mix_single(a)


def _key_expansion(key: bytes):
    nk = len(key) // 4
    nr = nk + 6
    w = list(struct.unpack(f">{nk}I", key))
    for i in range(nk, 4 * (nr + 1)):
        t = w[i - 1]
        if i % nk == 0:
            t = ((_SBOX[(t >> 16) & 0xFF] << 24) | (_SBOX[(t >> 8) & 0xFF] << 16) |
                 (_SBOX[t & 0xFF] << 8) | _SBOX[(t >> 24) & 0xFF])
            t ^= _RCON[i // nk - 1] << 24
        elif nk > 6 and i % nk == 4:
            t = ((_SBOX[(t >> 24)] << 24) | (_SBOX[(t >> 16) & 0xFF] << 16) |
                 (_SBOX[(t >> 8) & 0xFF] << 8) | _SBOX[t & 0xFF])
        w.append(w[i - nk] ^ t)
    rk = []
    for r in range(nr + 1):
        rk.append(struct.pack(">4I", *w[4*r:4*r+4]))
    return rk


def _aes_encrypt_block(block: bytes, round_keys) -> bytes:
    s = bytearray(a ^ b for a, b in zip(block, round_keys[0]))
    nr = len(round_keys) - 1
    for r in range(1, nr + 1):
        # SubBytes
        for i in range(16):
            s[i] = _SBOX[s[i]]
        # ShiftRows
        s[1], s[5], s[9], s[13] = s[5], s[9], s[13], s[1]
        s[2], s[6], s[10], s[14] = s[10], s[14], s[2], s[6]
        s[3], s[7], s[11], s[15] = s[15], s[3], s[7], s[11]
        # MixColumns (skip on last round)
        if r < nr:
            for c in range(4):
                col = [s[4*c], s[4*c+1], s[4*c+2], s[4*c+3]]
                _mix_single(col)
                s[4*c], s[4*c+1], s[4*c+2], s[4*c+3] = col
        # AddRoundKey
        rk = round_keys[r]
        for i in range(16):
            s[i] ^= rk[i]
    return bytes(s)


def _aes_decrypt_block(block: bytes, round_keys) -> bytes:
    s = bytearray(a ^ b for a, b in zip(block, round_keys[-1]))
    nr = len(round_keys) - 1
    for r in range(nr - 1, -1, -1):
        # InvShiftRows
        s[1], s[5], s[9], s[13] = s[13], s[1], s[5], s[9]
        s[2], s[6], s[10], s[14] = s[10], s[14], s[2], s[6]
        s[3], s[7], s[11], s[15] = s[7], s[11], s[15], s[3]
        # InvSubBytes
        for i in range(16):
            s[i] = _INV_SBOX[s[i]]
        # AddRoundKey
        rk = round_keys[r]
        for i in range(16):
            s[i] ^= rk[i]
        # InvMixColumns (skip on round 0)
        if r > 0:
            for c in range(4):
                col = [s[4*c], s[4*c+1], s[4*c+2], s[4*c+3]]
                _inv_mix_single(col)
                s[4*c], s[4*c+1], s[4*c+2], s[4*c+3] = col
    return bytes(s)


def _pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    pad_len = block_size - (len(data) % block_size)
    return data + bytes([pad_len]) * pad_len


def _pkcs7_unpad(data: bytes) -> bytes:
    pad_len = data[-1]
    if pad_len < 1 or pad_len > 16:
        raise ValueError("Invalid PKCS7 padding")
    if data[-pad_len:] != bytes([pad_len]) * pad_len:
        raise ValueError("Invalid PKCS7 padding")
    return data[:-pad_len]


def aes_cbc_encrypt(data: bytes, key: bytes, iv: bytes) -> bytes:
    rk = _key_expansion(key)
    data = _pkcs7_pad(data)
    out = bytearray()
    prev = iv
    for i in range(0, len(data), 16):
        block = bytes(a ^ b for a, b in zip(data[i:i+16], prev))
        prev = _aes_encrypt_block(block, rk)
        out.extend(prev)
    return bytes(out)


def aes_cbc_decrypt(data: bytes, key: bytes, iv: bytes) -> bytes:
    rk = _key_expansion(key)
    out = bytearray()
    prev = iv
    for i in range(0, len(data), 16):
        block = data[i:i+16]
        dec = _aes_decrypt_block(block, rk)
        out.extend(bytes(a ^ b for a, b in zip(dec, prev)))
        prev = block
    return _pkcs7_unpad(bytes(out))


# --- Pure-Python RSA-2048 Key Generation ---

def _is_probable_prime(n, k=20):
    if n < 2: return False
    if n == 2 or n == 3: return True
    if n % 2 == 0: return False
    r, d = 0, n - 1
    while d % 2 == 0:
        r += 1; d //= 2
    for _ in range(k):
        a = 2 + int.from_bytes(os.urandom(8), "big") % (n - 3)
        x = pow(a, d, n)
        if x == 1 or x == n - 1: continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1: break
        else:
            return False
    return True


def _gen_prime(bits):
    while True:
        p = int.from_bytes(os.urandom(bits // 8), "big")
        p |= (1 << (bits - 1)) | 1
        if _is_probable_prime(p):
            return p


def _modinv(a, m):
    g, x, _ = _extended_gcd(a, m)
    if g != 1:
        raise ValueError("No modular inverse")
    return x % m


def _extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x, y = _extended_gcd(b % a, a)
    return g, y - (b // a) * x, x


def _int_to_bytes(n, length):
    return n.to_bytes(length, "big")


def generate_rsa_2048():
    """Generate RSA-2048 keypair, return (pub_der, priv_der) in DER format."""
    e = 65537
    p = _gen_prime(1024)
    q = _gen_prime(1024)
    n = p * q
    phi = (p - 1) * (q - 1)
    d = _modinv(e, phi)

    # Encode public key as DER (SubjectPublicKeyInfo)
    def _encode_der_int(val):
        b = _int_to_bytes(val, (val.bit_length() + 8) // 8)
        if b[0] & 0x80:
            b = b'\x00' + b
        return b'\x02' + _der_length(len(b)) + b

    def _der_length(l):
        if l < 0x80:
            return bytes([l])
        bs = _int_to_bytes(l, (l.bit_length() + 7) // 8)
        return bytes([0x80 | len(bs)]) + bs

    def _der_sequence(*items):
        content = b''.join(items)
        return b'\x30' + _der_length(len(content)) + content

    def _der_bitstring(data):
        content = b'\x00' + data
        return b'\x03' + _der_length(len(content)) + content

    # RSAPublicKey
    rsa_pub = _der_sequence(_encode_der_int(n), _encode_der_int(e))

    # AlgorithmIdentifier for RSA
    rsa_oid = b'\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00'
    algo_id = _der_sequence(rsa_oid)

    # SubjectPublicKeyInfo
    pub_der = _der_sequence(algo_id, _der_bitstring(rsa_pub))

    # RSAPrivateKey (PKCS#1)
    dp = d % (p - 1)
    dq = d % (q - 1)
    qi = _modinv(q, p)
    rsa_priv_key = _der_sequence(
        _encode_der_int(0),  # version
        _encode_der_int(n),
        _encode_der_int(e),
        _encode_der_int(d),
        _encode_der_int(p),
        _encode_der_int(q),
        _encode_der_int(dp),
        _encode_der_int(dq),
        _encode_der_int(qi),
    )

    # PKCS#8 PrivateKeyInfo
    priv_der = _der_sequence(
        _encode_der_int(0),  # version
        algo_id,
        b'\x04' + _der_length(len(rsa_priv_key)) + rsa_priv_key,
    )

    return pub_der, priv_der


# --- Bitwarden Crypto Protocol ---

SERVICE_EMAIL = "loco-automation@localhost"
KDF_ITERATIONS = 600000


def pbkdf2(password: bytes, salt: bytes, iterations: int, length: int = 32) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password, salt, iterations, dklen=length)


def hkdf_expand(key: bytes, info: bytes, length: int) -> bytes:
    hash_len = 32
    n = (length + hash_len - 1) // hash_len
    okm = b""
    t = b""
    for i in range(1, n + 1):
        t = hmac.new(key, t + info + bytes([i]), hashlib.sha256).digest()
        okm += t
    return okm[:length]


def make_master_key(password: str, email: str, kdf=0, iterations=KDF_ITERATIONS,
                    memory=None, parallelism=None) -> bytes:
    if kdf == 1 and memory and parallelism:
        # Argon2id KDF — try to use hashlib (Python 3.13+) or argon2-cffi
        salt = hashlib.sha256(email.lower().encode()).digest()
        try:
            return hashlib.argon2(
                password.encode(), salt=salt, time_cost=iterations,
                memory_cost=memory * 1024, parallelism=parallelism,
                hash_len=32, type_="id",
            )
        except (AttributeError, TypeError):
            pass
        try:
            from argon2.low_level import hash_secret_raw, Type
            return hash_secret_raw(
                secret=password.encode(), salt=salt,
                time_cost=iterations, memory_cost=memory * 1024,
                parallelism=parallelism, hash_len=32, type=Type.ID,
            )
        except ImportError:
            raise RuntimeError(
                "Argon2id KDF required but neither Python 3.13+ hashlib.argon2 "
                "nor argon2-cffi is available. Install: pip install argon2-cffi"
            )
    # PBKDF2-SHA256 (kdf=0, default)
    return pbkdf2(password.encode(), email.lower().encode(), iterations)


def make_master_password_hash(password: str, master_key: bytes) -> str:
    h = pbkdf2(master_key, password.encode(), 1)
    return base64.b64encode(h).decode()


def stretch_key(master_key: bytes):
    prk = hmac.new(master_key, b"enc", hashlib.sha256).digest()
    enc_key = hkdf_expand(prk, b"enc", 32)
    prk_mac = hmac.new(master_key, b"mac", hashlib.sha256).digest()
    mac_key = hkdf_expand(prk_mac, b"mac", 32)
    return enc_key, mac_key


def encrypt_aes_cbc(data: bytes, enc_key: bytes, mac_key: bytes) -> str:
    iv = os.urandom(16)
    ct = aes_cbc_encrypt(data, enc_key, iv)
    mac_val = hmac.new(mac_key, iv + ct, hashlib.sha256).digest()
    return "2.{}|{}|{}".format(
        base64.b64encode(iv).decode(),
        base64.b64encode(ct).decode(),
        base64.b64encode(mac_val).decode(),
    )


def decrypt_aes_cbc(cipher_string: str, enc_key: bytes, mac_key: bytes) -> bytes:
    parts = cipher_string.split(".")
    if parts[0] != "2":
        raise ValueError(f"Unsupported cipher type: {parts[0]}")
    iv_b64, ct_b64, mac_b64 = parts[1].split("|")
    iv = base64.b64decode(iv_b64)
    ct = base64.b64decode(ct_b64)
    mac_expected = base64.b64decode(mac_b64)
    mac_actual = hmac.new(mac_key, iv + ct, hashlib.sha256).digest()
    if not hmac.compare_digest(mac_actual, mac_expected):
        raise ValueError("MAC verification failed")
    return aes_cbc_decrypt(ct, enc_key, iv)


def make_sym_key(master_key: bytes):
    sym_key = os.urandom(64)
    enc_key, mac_key = stretch_key(master_key)
    encrypted = encrypt_aes_cbc(sym_key, enc_key, mac_key)
    return sym_key, encrypted


def make_rsa_keys(sym_key: bytes):
    enc_key = sym_key[:32]
    mac_key = sym_key[32:]
    pub_der, priv_der = generate_rsa_2048()
    pub_b64 = base64.b64encode(pub_der).decode()
    priv_encrypted = encrypt_aes_cbc(priv_der, enc_key, mac_key)
    return pub_b64, priv_encrypted


def encrypt_string(text: str, sym_key: bytes) -> str:
    enc_key = sym_key[:32]
    mac_key = sym_key[32:]
    return encrypt_aes_cbc(text.encode(), enc_key, mac_key)


# --- Vaultwarden Client ---

class VaultwardenClient:
    def __init__(self, url: str, admin_token: str):
        self.url = url.rstrip("/")
        self.admin_token = admin_token
        self.service_password = hashlib.sha256(
            (admin_token + ":loco-service-user").encode()
        ).hexdigest()
        self.access_token = None
        self.sym_key = None
        self.admin_cookie = None

    def _http(self, method, path, data=None, headers=None, form=False):
        url = f"{self.url}/{path.lstrip('/')}"
        hdrs = headers or {}
        body = None
        if data is not None:
            if form:
                body = urllib.parse.urlencode(data).encode()
                hdrs.setdefault("Content-Type", "application/x-www-form-urlencoded")
            else:
                body = json.dumps(data).encode()
                hdrs.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
        try:
            resp = urllib.request.urlopen(req)
            content = resp.read().decode()
            if not content or not content.strip():
                return None
            try:
                return json.loads(content)
            except (json.JSONDecodeError, ValueError):
                return None
        except urllib.error.HTTPError as e:
            content = e.read().decode() if e.fp else ""
            raise RuntimeError(f"HTTP {e.code} {method} {url}: {content}") from e

    def admin_login(self):
        """Login to admin panel. Uses http.client to capture Set-Cookie
        from 302/303 redirects (urllib follows redirects and loses cookies)."""
        parsed = urllib.parse.urlparse(self.url)
        if parsed.scheme == "https":
            import ssl
            conn = http.client.HTTPSConnection(
                parsed.hostname, parsed.port,
                context=ssl._create_unverified_context(),
            )
        else:
            conn = http.client.HTTPConnection(parsed.hostname, parsed.port)
        body = urllib.parse.urlencode({"token": self.admin_token})
        conn.request(
            "POST", "/admin", body=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        resp = conn.getresponse()
        resp.read()  # consume body
        for val in resp.getheader("Set-Cookie", "").split(","):
            if "VW_ADMIN" in val:
                self.admin_cookie = val.split(";")[0].strip()
                break
        conn.close()
        if not self.admin_cookie:
            raise RuntimeError(
                f"Admin login failed (HTTP {resp.status}): no VW_ADMIN cookie. "
                "Check admin token."
            )

    def admin_request(self, method, path, data=None):
        if not self.admin_cookie:
            self.admin_login()
        url = f"{self.url}/admin/{path.lstrip('/')}"
        hdrs = {"Cookie": self.admin_cookie}
        body = None
        if data is not None:
            body = json.dumps(data).encode()
            hdrs["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
        try:
            resp = urllib.request.urlopen(req)
            content = resp.read().decode()
            if not content or not content.strip():
                return None
            try:
                return json.loads(content)
            except (json.JSONDecodeError, ValueError):
                return None
        except urllib.error.HTTPError as e:
            content = e.read().decode() if e.fp else ""
            if e.code == 409:
                return None
            raise RuntimeError(f"HTTP {e.code} admin {method} {path}: {content}") from e

    def check_user_exists(self, email):
        """Check if a user already exists via admin users overview."""
        try:
            users = self.admin_request("GET", "users/overview")
            if isinstance(users, list):
                for user in users:
                    user_email = user.get("Email", user.get("email", ""))
                    if user_email.lower() == email.lower():
                        return True
        except Exception:
            pass
        return False

    def delete_user(self, email):
        """Delete a user via admin API (by email)."""
        try:
            users = self.admin_request("GET", "users/overview")
            print(f"DEBUG: users/overview type={type(users).__name__}, "
                  f"is_list={isinstance(users, list)}", file=sys.stderr)
            if isinstance(users, list):
                for user in users:
                    user_email = user.get("Email", user.get("email", ""))
                    user_id = user.get("Id", user.get("id", ""))
                    if user_email.lower() == email.lower() and user_id:
                        print(f"DEBUG: Deleting user {user_email} id={user_id}",
                              file=sys.stderr)
                        # Try DELETE first, fall back to POST /delete
                        try:
                            self.admin_request("DELETE", f"users/{user_id}")
                            print("DEBUG: DELETE succeeded", file=sys.stderr)
                            return True
                        except RuntimeError:
                            pass
                        try:
                            self.admin_request("POST", f"users/{user_id}/delete")
                            print("DEBUG: POST /delete succeeded", file=sys.stderr)
                            return True
                        except RuntimeError as e:
                            print(f"DEBUG: Both delete methods failed: {e}",
                                  file=sys.stderr)
                            return False
            else:
                print(f"DEBUG: users/overview returned non-list: {str(users)[:200]}",
                      file=sys.stderr)
        except Exception as e:
            print(f"DEBUG: delete_user exception: {e}", file=sys.stderr)
        return False

    def _try_register(self, reg_data):
        """Try registration endpoints in order of preference.

        Vaultwarden changed registration endpoints across versions:
        - < 1.27: /api/accounts/register
        - 1.27-1.33: /identity/accounts/register
        - 1.34+: /identity/accounts/register/finish (two-step flow)

        With SIGNUPS_ALLOWED=false, older endpoints may return
        'Registration not allowed or user already exists' even for
        invited users. We must NOT treat this as success — instead
        we always try ALL endpoints.
        """
        last_error = None

        # 1) /identity/accounts/register (Vaultwarden 1.27-1.33)
        try:
            self._http("POST", "/identity/accounts/register", reg_data)
            print("DEBUG: register via /identity/accounts/register OK", file=sys.stderr)
            return True
        except RuntimeError as e:
            print(f"DEBUG: /identity/accounts/register: {e}", file=sys.stderr)
            last_error = e

        # 2) /api/accounts/register (legacy path, older Vaultwarden)
        try:
            self._http("POST", "/api/accounts/register", reg_data)
            print("DEBUG: register via /api/accounts/register OK", file=sys.stderr)
            return True
        except RuntimeError as e:
            print(f"DEBUG: /api/accounts/register: {e}", file=sys.stderr)
            last_error = e

        # 3) New flow: send-verification-email + finish (Vaultwarden 1.34+)
        # When mail is disabled, send-verification-email returns the token
        # directly in the response body instead of sending email.
        email_token = ""
        try:
            resp = self._http("POST", "/identity/accounts/register/send-verification-email", {
                "email": reg_data["email"],
                "name": reg_data.get("name", ""),
                "receiveMarketingEmails": False,
            })
            # When mail is disabled, token is returned directly
            if isinstance(resp, dict):
                email_token = resp.get("token", resp.get("Token", ""))
            elif isinstance(resp, str) and resp:
                email_token = resp
            print(f"DEBUG: send-verification-email OK, token={'set' if email_token else 'empty'}",
                  file=sys.stderr)
        except RuntimeError as e:
            print(f"DEBUG: send-verification-email: {e}", file=sys.stderr)
            # Continue — try finish anyway

        reg_data_finish = dict(reg_data)
        reg_data_finish["emailVerificationToken"] = email_token
        try:
            self._http("POST", "/identity/accounts/register/finish", reg_data_finish)
            print("DEBUG: register/finish OK", file=sys.stderr)
            return True
        except RuntimeError as e:
            print(f"DEBUG: register/finish: {e}", file=sys.stderr)
            last_error = e

        # All registration endpoints failed.
        # Do NOT treat "Registration not allowed or user already exists" as
        # success — the error message is deliberately ambiguous and usually
        # means signups are disabled, not that the user actually exists.
        # The caller (ensure_service_user) verifies user existence separately.
        raise last_error or RuntimeError("All registration endpoints failed")

    def _invite_and_register(self):
        """Invite and register the service user.

        Requires SIGNUPS_ALLOWED=true in the Vaultwarden environment.
        The Ansible credentials role handles toggling this setting and
        restarting the container when needed (see store.yml).
        """
        try:
            self.admin_request("POST", "invite", {"email": SERVICE_EMAIL})
            print("DEBUG: invite OK", file=sys.stderr)
        except RuntimeError as e:
            print(f"DEBUG: invite result: {e}", file=sys.stderr)
            if "409" not in str(e):
                raise

        master_key = make_master_key(self.service_password, SERVICE_EMAIL)
        master_hash = make_master_password_hash(self.service_password, master_key)
        sym_key_raw, sym_key_encrypted = make_sym_key(master_key)
        pub_key, priv_key_encrypted = make_rsa_keys(sym_key_raw)
        reg_data = {
            "email": SERVICE_EMAIL,
            "name": "LocoCloud Automation",
            "masterPasswordHash": master_hash,
            "masterPasswordHint": "",
            "key": sym_key_encrypted,
            "kdf": 0,
            "kdfIterations": KDF_ITERATIONS,
            "kdfMemory": None,
            "kdfParallelism": None,
            "keys": {"publicKey": pub_key, "encryptedPrivateKey": priv_key_encrypted},
        }
        print(f"DEBUG: registering with kdf=0 iterations={KDF_ITERATIONS}",
              file=sys.stderr)
        self._try_register(reg_data)

    def ensure_service_user(self):
        self.admin_login()
        print(f"DEBUG: admin_login OK, cookie={'set' if self.admin_cookie else 'MISSING'}",
              file=sys.stderr)

        user_exists = self.check_user_exists(SERVICE_EMAIL)
        print(f"DEBUG: user_exists={user_exists}", file=sys.stderr)

        if user_exists:
            # User exists — verify we can log in. If password doesn't match
            # (e.g. admin token changed since last run), delete and recreate.
            try:
                self.login()
                print("DEBUG: existing user login OK", file=sys.stderr)
                return  # login works, nothing to do
            except RuntimeError as e:
                print(f"DEBUG: existing user login FAILED: {e}", file=sys.stderr)
                deleted = self.delete_user(SERVICE_EMAIL)
                print(f"DEBUG: delete_user result={deleted}", file=sys.stderr)
                self.access_token = None
                self.sym_key = None
                if not deleted:
                    raise RuntimeError(
                        f"Cannot log in as service user and cannot delete it either. "
                        f"Login error: {e}"
                    )

        print("DEBUG: calling _invite_and_register", file=sys.stderr)
        self._invite_and_register()

        # Verify the freshly created user can log in
        print("DEBUG: verifying login after registration", file=sys.stderr)
        try:
            self.login()
            print("DEBUG: post-registration login OK", file=sys.stderr)
        except RuntimeError as e:
            # Get prelogin info for diagnostics
            try:
                kdf_info = self.prelogin(SERVICE_EMAIL)
            except Exception:
                kdf_info = "prelogin failed"
            raise RuntimeError(
                f"Freshly registered user cannot log in. "
                f"prelogin={kdf_info}, error={e}"
            )

    def prelogin(self, email):
        """Query server for KDF parameters before login."""
        try:
            resp = self._http("POST", "/api/accounts/prelogin", {"email": email})
            if resp:
                print(f"DEBUG: prelogin /api response: {resp}", file=sys.stderr)
                return resp
        except RuntimeError as e:
            print(f"DEBUG: prelogin /api failed: {e}", file=sys.stderr)
        try:
            resp = self._http("POST", "/identity/accounts/prelogin", {"email": email})
            if resp:
                print(f"DEBUG: prelogin /identity response: {resp}", file=sys.stderr)
                return resp
        except RuntimeError as e:
            print(f"DEBUG: prelogin /identity failed: {e}", file=sys.stderr)
        print(f"DEBUG: prelogin fallback to defaults kdf=0 iter={KDF_ITERATIONS}",
              file=sys.stderr)
        return {"kdf": 0, "kdfIterations": KDF_ITERATIONS}

    def login(self):
        kdf_info = self.prelogin(SERVICE_EMAIL)
        kdf_type = kdf_info.get("kdf", kdf_info.get("Kdf", 0))
        kdf_iter = kdf_info.get("kdfIterations", kdf_info.get("KdfIterations", KDF_ITERATIONS))
        kdf_mem = kdf_info.get("kdfMemory", kdf_info.get("KdfMemory"))
        kdf_par = kdf_info.get("kdfParallelism", kdf_info.get("KdfParallelism"))
        print(f"DEBUG: login with kdf={kdf_type} iter={kdf_iter} mem={kdf_mem} par={kdf_par}",
              file=sys.stderr)
        master_key = make_master_key(
            self.service_password, SERVICE_EMAIL,
            kdf=kdf_type, iterations=kdf_iter,
            memory=kdf_mem, parallelism=kdf_par,
        )
        master_hash = make_master_password_hash(self.service_password, master_key)
        token_data = {
            "grant_type": "password",
            "username": SERVICE_EMAIL,
            "password": master_hash,
            "scope": "api offline_access",
            "client_id": "cli",
            "deviceType": "14",
            "deviceIdentifier": "loco-ansible-automation",
            "deviceName": "LocoCloud Ansible",
        }
        resp = self._http("POST", "/identity/connect/token", token_data, form=True)
        self.access_token = resp["access_token"]
        enc_sym_key = resp.get("key", resp.get("Key", ""))
        if enc_sym_key:
            enc_key, mac_key = stretch_key(master_key)
            self.sym_key = decrypt_aes_cbc(enc_sym_key, enc_key, mac_key)

    def api_request(self, method, path, data=None):
        if not self.access_token:
            self.login()
        hdrs = {"Authorization": f"Bearer {self.access_token}"}
        return self._http(method, path, data, hdrs)

    def list_ciphers(self):
        resp = self.api_request("GET", "/api/ciphers")
        return resp.get("data", []) if resp else []

    def find_cipher(self, name: str):
        if not self.sym_key:
            return None
        for cipher in self.list_ciphers():
            enc_name = cipher.get("name", "")
            if not enc_name:
                continue
            try:
                dec_name = decrypt_aes_cbc(
                    enc_name, self.sym_key[:32], self.sym_key[32:]
                ).decode()
                if dec_name == name:
                    return cipher
            except Exception:
                continue
        return None

    def store_credential(self, name, username, password, uri="", notes=""):
        if not self.sym_key:
            raise RuntimeError("Not logged in or no encryption key")
        existing = self.find_cipher(name)
        enc_name = encrypt_string(name, self.sym_key)
        enc_username = encrypt_string(username, self.sym_key) if username else None
        enc_password = encrypt_string(password, self.sym_key) if password else None
        enc_notes = encrypt_string(notes, self.sym_key) if notes else None
        uris = None
        if uri:
            uris = [{"uri": encrypt_string(uri, self.sym_key), "match": None}]
        cipher_data = {
            "type": 1,
            "name": enc_name,
            "notes": enc_notes,
            "login": {
                "username": enc_username,
                "password": enc_password,
                "uris": uris,
                "totp": None,
            },
            "favorite": False,
        }
        if existing:
            cipher_id = existing["id"]
            self.api_request("PUT", f"/api/ciphers/{cipher_id}", cipher_data)
            return {"action": "updated", "id": cipher_id}
        else:
            resp = self.api_request("POST", "/api/ciphers", cipher_data)
            return {"action": "created", "id": resp.get("id", resp.get("Id", ""))}


def main():
    parser = argparse.ArgumentParser(description="Store credentials in Vaultwarden")
    parser.add_argument("--url", help="Vaultwarden URL")
    parser.add_argument("--admin-token", help="Admin token")
    parser.add_argument(
        "--action", choices=["store", "list", "setup"], default="store"
    )
    parser.add_argument("--name", help="Credential name")
    parser.add_argument("--username", default="", help="Username")
    parser.add_argument("--password", default="", help="Password")
    parser.add_argument("--uri", default="", help="URI")
    parser.add_argument("--notes", default="", help="Notes")
    parser.add_argument("--from-file", help="Read parameters from JSON file")
    args = parser.parse_args()

    if args.from_file:
        with open(args.from_file) as f:
            data = json.load(f)
        args.url = data.get("url", args.url)
        args.admin_token = data.get("admin_token", args.admin_token)
        args.action = data.get("action", args.action)
        args.name = data.get("name", args.name)
        args.username = data.get("username", args.username or "")
        args.password = data.get("password", args.password or "")
        args.uri = data.get("uri", args.uri or "")
        args.notes = data.get("notes", args.notes or "")

    if not args.url or not args.admin_token:
        parser.error("--url and --admin-token are required")

    client = VaultwardenClient(args.url, args.admin_token)

    if args.action == "setup":
        client.ensure_service_user()  # includes login verification
        print(json.dumps({"status": "ok", "message": "Service user ready"}))

    elif args.action == "list":
        client.ensure_service_user()  # includes login verification
        ciphers = client.list_ciphers()
        items = []
        for c in ciphers:
            try:
                name = decrypt_aes_cbc(
                    c["name"], client.sym_key[:32], client.sym_key[32:]
                ).decode()
            except Exception:
                name = "(encrypted)"
            items.append({"id": c["id"], "name": name})
        print(json.dumps(items, indent=2))

    elif args.action == "store":
        if not args.name:
            parser.error("--name required for store action")
        client.ensure_service_user()  # includes login verification
        result = client.store_credential(
            args.name, args.username, args.password, args.uri, args.notes
        )
        print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
