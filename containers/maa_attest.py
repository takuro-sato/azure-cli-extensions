import base64
import json
import os
import time
import urllib.error
import urllib.request


SKR_URL = "http://localhost:8080"


def wait_for_skr() -> None:
    for _ in range(60):
        try:
            with urllib.request.urlopen(f"{SKR_URL}/status", timeout=2):
                return
        except (OSError, urllib.error.URLError):
            time.sleep(2)
    raise TimeoutError("SKR did not become ready")


def main() -> None:
    attestation_endpoint = os.environ["ATTESTATION_ENDPOINT"]
    runtime_data = base64.urlsafe_b64encode(
        json.dumps(
            {
                "keys": [
                    {
                        "key_ops": ["encrypt"],
                        "kid": "example-key",
                        "kty": "oct-HSM",
                        "k": "example",
                    }
                ]
            }
        ).encode()
    ).decode()
    body = json.dumps(
        {"maa_endpoint": attestation_endpoint, "runtime_data": runtime_data}
    ).encode()
    request = urllib.request.Request(
        f"{SKR_URL}/attest/maa",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    wait_for_skr()
    with urllib.request.urlopen(request, timeout=120) as response:
        print(response.read().decode(), flush=True)

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
