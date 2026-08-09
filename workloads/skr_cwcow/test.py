# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# Confidential WCOW equivalent of workloads/skr/test.py.
#
# The container group is deployed by the workflow (single confidential Windows
# skr image serving HTTP on the public IP, port 8000 — no proxy, so no gRPC
# endpoints). This test does NOT deploy or regenerate the policy: it looks up
# the already-deployed group's public IP and exercises the HTTP interface
# directly, mirroring workloads/skr-fixed-policy/test.py.
#
# attestation.py / key.py are shared with the Linux workload (workloads/skr).

import argparse
import binascii
import hashlib
import re
import struct
import subprocess
import sys
import os
import unittest
import base64
import json
import random
import requests

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "skr")))
from attestation import SNP_REPORT_STRUCTURE
from key import generate_oct_key, deploy_key, generate_release_policy

from c_aci_testing.args.parameters.location import parse_location
from c_aci_testing.args.parameters.managed_identity import \
    parse_managed_identity
from c_aci_testing.args.parameters.registry import parse_registry
from c_aci_testing.args.parameters.repository import parse_repository
from c_aci_testing.args.parameters.resource_group import parse_resource_group
from c_aci_testing.args.parameters.subscription import parse_subscription
from c_aci_testing.tools.aci_get_ips import aci_get_ips

# The deployed CCE policy is this file loaded verbatim (see
# skr_cwcow.bicepparam), so its sha256 is the SEV-SNP host_data the key-release
# policies must bind to. We never regenerate it — it stays allow_all.
POLICY_FILENAME = "policy_skr_cwcow.rego"


def check_report_data(report: str, expected_report_data: bytes):

    # Report data isn't returned as Hex, so we unhex around it
    skr_report = struct.unpack_from(
        f"<{SNP_REPORT_STRUCTURE}",
        (
            binascii.unhexlify(report[:160])
            + report[160:224].encode()  # Report Data
            + binascii.unhexlify(report[224:])
        ),
        0,
    )

    # SKR decodes the base64 string and then hashes it before providing it to
    # the SNP attestation.
    seen_report_data = skr_report[10].rstrip(b"\x00").decode()
    expected_report_data = hashlib.sha256(expected_report_data).hexdigest()
    print(f"Checking seen report data: {seen_report_data}")
    print(f"Matches provided report data: {expected_report_data}")
    assert seen_report_data == expected_report_data


class SkrCwcowTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.target_dir = os.path.realpath(os.path.dirname(__file__))
        cls.id = os.environ["DEPLOYMENT_NAME"]
        cls.key_name_prefix = re.sub("_", "-", cls.id) + "-" + "".join(
            random.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(8)
        )
        cls.tag = os.getenv("TAG") or "latest"
        cls.attestation_endpoint = os.environ["ATTESTATION_ENDPOINT"]
        cls.hsm_endpoint = os.environ["HSM_ENDPOINT"]

        parser = argparse.ArgumentParser()
        parse_subscription(parser)
        parse_resource_group(parser)
        parse_registry(parser)
        parse_repository(parser)
        parse_location(parser)
        parse_managed_identity(parser)
        args, _ = parser.parse_known_args()

        cls.skr_ip = aci_get_ips(
            deployment_name=cls.id,
            subscription=args.subscription,
            resource_group=args.resource_group,
        )[0]
        cls.http_port = 8000

    def test_skr_http_status(self):
        status_response = requests.get(
            f"http://{self.skr_ip}:{self.http_port}/status",
        )
        print(f"Response from status check: {status_response.content}")
        assert status_response.status_code == 200

    def test_skr_http_attest_raw(self):
        input_report_data = b"EXAMPLE"
        attestation_resp = requests.post(
            url=f"http://{self.skr_ip}:{self.http_port}/attest/raw",
            headers={"Content-Type": "application/json"},
            data=json.dumps(
                {
                    "runtime_data": base64.urlsafe_b64encode(
                        input_report_data
                    ).decode(),
                }
            ),
        )
        print(f"Response from attestation check: {attestation_resp.content}")
        assert attestation_resp.status_code == 200, attestation_resp.content.decode()
        # "report" here is a hex encoded version of the whole SNP report.
        check_report_data(
            report=json.loads(attestation_resp.content.decode())["report"],
            expected_report_data=input_report_data,
        )

    def test_skr_http_attest_combined(self):
        input_report_data = b"EXAMPLE_COMBINED"
        attestation_resp = requests.post(
            url=f"http://{self.skr_ip}:{self.http_port}/attest/combined",
            headers={"Content-Type": "application/json"},
            data=json.dumps(
                {
                    "runtime_data": base64.urlsafe_b64encode(
                        input_report_data
                    ).decode(),
                }
            ),
        )
        print(f"Response from combined check: {attestation_resp.content}")
        assert attestation_resp.status_code == 200, attestation_resp.content.decode()

        # "evidence" here is a base64 encoded version of the whole SNP report,
        # which needs to be made into hex to suit check_report_data.
        response_combined = json.loads(attestation_resp.content.decode())
        report_b64 = response_combined["evidence"]
        report_hex = base64.b64decode(report_b64).hex()
        check_report_data(
            report=report_hex,
            expected_report_data=input_report_data,
        )

    def test_skr_http_attest_maa(self):
        if self.attestation_endpoint == "":
            print("\nSkipping MAA test as no endpoint provided.\n")
            return

        test_key = json.dumps(
            {
                "keys": [
                    {
                        "key_ops": ["encrypt"],
                        "kid": "test-key",
                        "kty": "oct-HSM",
                        "k": "example",
                    }
                ]
            }
        )
        maa_response = requests.post(
            url=f"http://{self.skr_ip}:{self.http_port}/attest/maa",
            headers={"Content-Type": "application/json"},
            data=json.dumps(
                {
                    "maa_endpoint": self.attestation_endpoint,
                    "runtime_data": base64.urlsafe_b64encode(test_key.encode()).decode(),
                }
            ),
        )
        assert maa_response.status_code == 200, maa_response.content.decode()
        assert json.loads(maa_response.content.decode())["token"] != ""

    def test_skr_http_oct_key_release(self):
        if self.attestation_endpoint == "" or self.hsm_endpoint == "":
            print("\nSkipping Key Release test as MAA/mHSM endpoints not provided.\n")
            return

        key_id = self.key_name_prefix + "-key"
        with open(os.path.join(self.target_dir, POLICY_FILENAME)) as f:
            deploy_key(
                key_id=key_id,
                kty="oct-HSM",
                key_ops=["encrypt", "decrypt", "wrapKey", "unwrapKey"],
                attestation_endpoint=self.attestation_endpoint,
                hsm_endpoint=self.hsm_endpoint,
                key_data=generate_oct_key(),
                security_policy=f.read(),
            )
        self._run_key_release_test(
            key_id=key_id,
            key_ops=["encrypt", "decrypt", "wrapKey", "unwrapKey"],
        )

    def test_skr_http_ec_key_release(self):
        if self.attestation_endpoint == "" or self.hsm_endpoint == "":
            print("\nSkipping Key Release test as MAA/mHSM endpoints not provided.\n")
            return

        key_id = self.key_name_prefix + "-ec-key"
        with open(os.path.join(self.target_dir, POLICY_FILENAME)) as f:
            security_policy = generate_release_policy(
                attestation_endpoint=self.attestation_endpoint,
                host_data=hashlib.sha256(f.read().encode()).hexdigest(),
            )
            subprocess.check_call([
                "az", "keyvault", "key", "create",
                "--id", f"https://{self.hsm_endpoint}/keys/{key_id}",
                "--ops", "sign", "verify",
                "--kty", "EC-HSM", "--curve", "P-256", "--exportable",
                "--policy", security_policy])
        self._run_key_release_test(
            key_id=key_id,
            key_ops=["sign", "verify"],
        )

    def _run_key_release_test(self, key_id, key_ops):
        skr_response = requests.post(
            url=f"http://{self.skr_ip}:{self.http_port}/key/release",
            headers={"Content-Type": "application/json"},
            data=json.dumps(
                {
                    "maa_endpoint": self.attestation_endpoint,
                    "akv_endpoint": self.hsm_endpoint,
                    "kid": key_id,
                }
            ),
        )
        key = json.loads(json.loads(skr_response.content.decode())["key"])
        assert skr_response.status_code == 200, skr_response.content.decode()
        assert key["k"] != "" if "oct" in key["kty"] else key["x"] != "" and key["y"] != ""
        assert set(key["key_ops"]) == set(key_ops)


if __name__ == "__main__":
    unittest.main()
