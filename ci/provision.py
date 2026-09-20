"""Создать сертификат распространения и профиль, положить их на машину сборки.

Зачем это существует. Xcode умеет заводить подпись сам («облачная подпись»),
но только когда в него вошли живым человеком. Ключ App Store Connect такого
доступа не даёт, и ровно поэтому десять попыток подряд упирались в «профиль не
найден». Поэтому делаем то же самое руками, через служебный интерфейс Apple:

  1. создаём закрытый ключ и заявку на сертификат;
  2. просим Apple выдать по ней сертификат распространения;
  3. складываем ключ и сертификат в связку ключей машины;
  4. просим Apple выдать профиль для нашего приложения;
  5. кладём профиль туда, где Xcode его найдёт.

Скрипт печатает имя профиля — оно нужно сборке для экспорта.
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.kobiashvili.diary"
CERT_NAME = "Chronotheca CI"
PROFILE_NAME = "Chronotheca CI App Store"
WORK = "/tmp/signing"
P12_PASSWORD = "chronotheca-ci"
KEYCHAIN = os.path.expanduser("~/Library/Keychains/chronotheca-ci-db")
KEYCHAIN_PASSWORD = "chronotheca-ci"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        open(os.environ["KEY_PATH"]).read(),
        algorithm="ES256",
        headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})


def api(path, method="GET", body=None, tok=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API + path, data=data, method=method,
        headers={"Authorization": "Bearer " + tok,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        print(f"  {method} {path} → {e.code}\n  {detail[:800]}", file=sys.stderr)
        raise


def run(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw)


def main():
    tok = token()
    os.makedirs(WORK, exist_ok=True)

    # 1. Закрытый ключ и заявка на сертификат
    print("Готовлю заявку на сертификат…")
    run("openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
        "-keyout", f"{WORK}/key.pem", "-out", f"{WORK}/csr.pem",
        "-subj", "/CN=Chronotheca CI/C=GB")
    csr = open(f"{WORK}/csr.pem").read()

    # 2. Сертификат распространения
    print("Прошу у Apple сертификат распространения…")
    try:
        made = api("/v1/certificates", "POST", {
            "data": {"type": "certificates",
                     "attributes": {"certificateType": "DISTRIBUTION",
                                    "csrContent": csr}}}, tok)
    except urllib.error.HTTPError as e:
        if e.code == 409:
            print("::error::Apple отказала: исчерпан предел сертификатов "
                  "распространения. Отзовите лишние на developer.apple.com → "
                  "Certificates.")
        raise
    cert = made["data"]
    cert_id = cert["id"]
    print(f"  выдан сертификат {cert_id}")

    with open(f"{WORK}/cert.cer", "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))
    run("openssl", "x509", "-inform", "DER", "-in", f"{WORK}/cert.cer",
        "-out", f"{WORK}/cert.pem")

    # 3. Связка ключей машины
    print("Кладу ключ и сертификат в связку ключей…")
    p12 = [
        "openssl", "pkcs12", "-export",
        "-inkey", f"{WORK}/key.pem", "-in", f"{WORK}/cert.pem",
        "-out", f"{WORK}/cert.p12", "-passout", f"pass:{P12_PASSWORD}",
        "-name", CERT_NAME,
    ]
    try:
        run(*p12, "-legacy")
    except subprocess.CalledProcessError:
        run(*p12)

    subprocess.run(["security", "delete-keychain", KEYCHAIN],
                   capture_output=True, text=True)
    run("security", "create-keychain", "-p", KEYCHAIN_PASSWORD, KEYCHAIN)
    run("security", "set-keychain-settings", "-lut", "21600", KEYCHAIN)
    run("security", "unlock-keychain", "-p", KEYCHAIN_PASSWORD, KEYCHAIN)
    run("security", "import", f"{WORK}/cert.p12", "-k", KEYCHAIN,
        "-P", P12_PASSWORD, "-A", "-T", "/usr/bin/codesign",
        "-T", "/usr/bin/security")
    run("security", "set-key-partition-list", "-S",
        "apple-tool:,apple:,codesign:", "-s", "-k", KEYCHAIN_PASSWORD, KEYCHAIN)

    # Связка должна быть в списке поиска, иначе codesign её не увидит.
    existing = run("security", "list-keychains", "-d", "user").stdout.split()
    existing = [k.strip().strip('"') for k in existing]
    run("security", "list-keychains", "-d", "user", "-s", KEYCHAIN, *existing)
    print(run("security", "find-identity", "-v", "-p", "codesigning",
              KEYCHAIN).stdout.strip())

    # 4. Профиль
    found = api(f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}&limit=1", tok=tok)
    if not found.get("data"):
        print(f"::error::Опознавательный знак {BUNDLE_ID} не заведён в аккаунте.")
        sys.exit(1)
    bundle_ref = found["data"][0]["id"]

    for p in api("/v1/profiles?limit=200", tok=tok).get("data", []):
        if p["attributes"]["name"] == PROFILE_NAME:
            print(f"  убираю прежний профиль {p['id']}")
            api(f"/v1/profiles/{p['id']}", "DELETE", tok=tok)

    print("Прошу у Apple профиль для App Store…")
    profile = api("/v1/profiles", "POST", {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"id": bundle_ref, "type": "bundleIds"}},
                "certificates": {"data": [{"id": cert_id, "type": "certificates"}]},
            }}}, tok)["data"]

    # 5. Профиль — туда, где его ищет Xcode.
    #
    # Папок две: старая и новая. Начиная с Xcode 16 профили читаются из
    # UserData, а прежняя папка осталась для совместимости. Кладём в обе,
    # чтобы не зависеть от версии на машине сборки.
    blob = base64.b64decode(profile["attributes"]["profileContent"])

    raw = f"{WORK}/profile.mobileprovision"
    with open(raw, "wb") as f:
        f.write(blob)

    # Имя файла — внутренний UUID профиля: так их называет сам Xcode.
    plist = run("security", "cms", "-D", "-i", raw).stdout
    import plistlib
    uuid = plistlib.loads(plist.encode("utf-8", "surrogateescape"))["UUID"]

    for folder in (
        "~/Library/Developer/Xcode/UserData/Provisioning Profiles",
        "~/Library/MobileDevice/Provisioning Profiles",
    ):
        d = os.path.expanduser(folder)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, uuid + ".mobileprovision")
        with open(path, "wb") as f:
            f.write(blob)
        print(f"  профиль положен: {path}")

    with open(os.environ["GITHUB_ENV"], "a") as f:
        f.write(f"PROFILE_NAME={PROFILE_NAME}\n")
        f.write(f"SIGNING_KEYCHAIN={KEYCHAIN}\n")
    print(f"Готово. Профиль «{PROFILE_NAME}».")


if __name__ == "__main__":
    main()
