#!/usr/bin/env python3
"""
vw-credentials.py — Store credentials in Vaultwarden programmatically.

Handles the full Bitwarden protocol: user registration, authentication,
client-side encryption, and cipher creation.

Uses a deterministic service user derived from the admin token.
No manual interaction required.

Dependencies: Python 3.8+, cryptography (installed with Ansible)

Usage:
    python3 vw-credentials.py \
        --url http://127.0.0.1:8222 \
        --admin-token <token> \
        --action store \
        --name "My Credential" \
        --username "user" \
        --password "pass" \
        [--uri "https://..."] \
        [--notes "..."]

    python3 vw-credentials.py \
        --url http://127.0.0.1:8222 \
        --admin-token <token> \
        --action list
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives import padding as sym_padding
    from cryptography.hazmat.primitives.asymmetric import rsa, padding as asym_padding
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.backends import default_backend
except ImportError:
    print("ERROR: 'cryptography' library required. Install: pip3 install cryptography", file=sys.stderr)
    sys.exit(1)


# Service user credentials derived from admin token
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


def make_master_key(password: str, email: str) -> bytes:
    return pbkdf2(password.encode(), email.lower().encode(), KDF_ITERATIONS)


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
    padder = sym_padding.PKCS7(128).padder()
    padded = padder.update(data) + padder.finalize()
    cipher = Cipher(algorithms.AES(enc_key), modes.CBC(iv), backend=default_backend())
    enc = cipher.encryptor()
    ct = enc.update(padded) + enc.finalize()
    mac = hmac.new(mac_key, iv + ct, hashlib.sha256).digest()
    return "2.{}|{}|{}".format(
        base64.b64encode(iv).decode(),
        base64.b64encode(ct).decode(),
        base64.b64encode(mac).decode(),
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
    cipher = Cipher(algorithms.AES(enc_key), modes.CBC(iv), backend=default_backend())
    dec = cipher.decryptor()
    padded = dec.update(ct) + dec.finalize()
    unpadder = sym_padding.PKCS7(128).unpadder()
    return unpadder.update(padded) + unpadder.finalize()


def make_sym_key(master_key: bytes):
    sym_key = os.urandom(64)
    enc_key, mac_key = stretch_key(master_key)
    encrypted = encrypt_aes_cbc(sym_key, enc_key, mac_key)
    return sym_key, encrypted


def make_rsa_keys(sym_key: bytes):
    enc_key = sym_key[:32]
    mac_key = sym_key[32:]
    private_key = rsa.generate_private_key(
        public_exponent=65537, key_size=2048, backend=default_backend()
    )
    public_key = private_key.public_key()
    pub_der = public_key.public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    priv_der = private_key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    pub_b64 = base64.b64encode(pub_der).decode()
    priv_encrypted = encrypt_aes_cbc(priv_der, enc_key, mac_key)
    return pub_b64, priv_encrypted


def encrypt_string(text: str, sym_key: bytes) -> str:
    enc_key = sym_key[:32]
    mac_key = sym_key[32:]
    return encrypt_aes_cbc(text.encode(), enc_key, mac_key)


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
            if content:
                return json.loads(content)
            return None
        except urllib.error.HTTPError as e:
            content = e.read().decode() if e.fp else ""
            raise RuntimeError(f"HTTP {e.code} {method} {url}: {content}") from e

    def admin_login(self):
        url = f"{self.url}/admin"
        data = urllib.parse.urlencode({"token": self.admin_token}).encode()
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
        try:
            resp = urllib.request.urlopen(req)
            for header in resp.headers.get_all("Set-Cookie") or []:
                if "VW_ADMIN" in header:
                    self.admin_cookie = header.split(";")[0]
            return True
        except urllib.error.HTTPError as e:
            if e.code in (303, 302, 200):
                for header in e.headers.get_all("Set-Cookie") or []:
                    if "VW_ADMIN" in header:
                        self.admin_cookie = header.split(";")[0]
                return True
            raise

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
            return json.loads(content) if content else None
        except urllib.error.HTTPError as e:
            content = e.read().decode() if e.fp else ""
            if e.code == 409:
                return None
            raise RuntimeError(f"HTTP {e.code} admin {method} {path}: {content}") from e

    def ensure_service_user(self):
        self.admin_login()
        try:
            self.admin_request("POST", "invite", {"email": SERVICE_EMAIL})
        except RuntimeError as e:
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
        try:
            self._http("POST", "/api/accounts/register", reg_data)
        except RuntimeError as e:
            if "User already exists" in str(e) or "400" in str(e):
                pass
            else:
                raise

    def login(self):
        master_key = make_master_key(self.service_password, SERVICE_EMAIL)
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

    # Load parameters from JSON file if specified
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
        client.ensure_service_user()
        client.login()
        print(json.dumps({"status": "ok", "message": "Service user ready"}))

    elif args.action == "list":
        client.ensure_service_user()
        client.login()
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
        client.ensure_service_user()
        client.login()
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
