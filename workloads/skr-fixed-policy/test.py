# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

import argparse
import binascii
import hashlib
import re
import struct
import subprocess
import sys
import tempfile
import requests
import os
import unittest
import base64
import json
import random

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

POLICY_FILENAME = "policy_skr_fixed_policy.rego"


def get_grpc_response(raw_response: bytes):
    return json.loads(
        re.findall(
            r"Response contents:\s*(\{.*?\})",
            raw_response.decode(),
            re.DOTALL,
        )[0]
    )


def check_report_data(report: str, expected_report_data: str):
    skr_report = struct.unpack_from(
        f"<{SNP_REPORT_STRUCTURE}",
        (
            binascii.unhexlify(report[:160])
            + report[160:224].encode()
            + binascii.unhexlify(report[224:])
        ),
        0,
    )
    seen_report_data = skr_report[10].rstrip(b"\x00").decode()
    expected_report_data = hashlib.sha256(expected_report_data).hexdigest()
    print(f"Checking seen report data: {seen_report_data}")
    print(f"Matches provided report data: {expected_report_data}")
    assert seen_report_data == expected_report_data


class SkrFixedPolicyTest(unittest.TestCase):

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
        assert attestation_resp.status_code == 200, attestation_resp.content.decode()
        check_report_data(
            report=json.loads(attestation_resp.content.decode())["report"],
            expected_report_data=input_report_data,
        )

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
        assert key["k"] != ""
        assert set(key["key_ops"]) == {"encrypt", "decrypt", "wrapKey", "unwrapKey"}


if __name__ == "__main__":
    unittest.main()
