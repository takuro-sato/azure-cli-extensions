#!/usr/bin/env python3

import os
import glob
import sys
import base64
import json
import jsonschema
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--reference-payload", type=str, required=True)
parser.add_argument("--require-host-amd-cert", action="store_true", default=False)
args = parser.parse_args()
ref_payload_file = args.reference_payload
require_host_amd_cert = args.require_host_amd_cert

scriptdir = os.path.dirname(os.path.abspath(__file__))
security_context_dir = glob.glob("/security-context-*")
if len(security_context_dir) != 1:
    print("ERROR: Expected exactly one /security-context-* directory, found:", security_context_dir)
    sys.exit(1)

has_err = False

def validate_schema(schema_filename: str, json_filename: str, is_base64: bool, skip_if_not_exist: bool):
    global has_err

    print(f"Validating {json_filename} against schema {schema_filename}")
    schema_file = os.path.join(scriptdir, schema_filename)
    json_file = os.path.join(security_context_dir[0], json_filename)
    if not os.path.exists(json_file):
        if not skip_if_not_exist:
            print(f"ERROR: {json_file} not found")
            has_err = True
            return
        else:
            print(f"Skip checking {json_file} (does not exist)")
            return
    try:
        with open(json_file, "rt") as f:
            if not is_base64:
                content = f.read()
            else:
                content = base64.b64decode(f.read())
            parsed = json.loads(content)
            with open(schema_file, "rt") as sf:
                schema_parsed = json.load(sf)
            try:
                jsonschema.validate(instance=parsed, schema=schema_parsed)
            except jsonschema.ValidationError as ve:
                print(f"ERROR: {json_file} does not conform to schema {schema_filename}: {ve}")
                has_err = True
                return
            except jsonschema.SchemaError as se:
                print(f"ERROR: Schema {schema_filename} is invalid: {se}")
                has_err = True
                return
    except Exception as e:
        print(f"ERROR: Failed to read json from {json_file}: {e}")
        has_err = True
        return

validate_schema("reference-info.schema.json", ref_payload_file, is_base64=False, skip_if_not_exist=False)
validate_schema("host-amd-cert.schema.json", "host-amd-cert-base64", is_base64=True, skip_if_not_exist=not require_host_amd_cert)

if has_err:
    sys.exit(1)
