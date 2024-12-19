from azure.kusto.data import KustoClient, KustoConnectionStringBuilder
import os
from datetime import datetime
import json


def get_env_or_die(env_name):
    value = os.environ.get(env_name)
    if value is None:
        raise ValueError(f"Environment variable {env_name} is not set")
    return value


KUSTO_CONNECTION_STRING = get_env_or_die("KUSTO_CONNECTION_STRING")
conn = KustoConnectionStringBuilder.with_az_cli_authentication(KUSTO_CONNECTION_STRING)
KUSTO_DATABASE = get_env_or_die("KUSTO_DATABASE")
KUSTO_TABLE = get_env_or_die("KUSTO_TABLE")

STATE_FILE = os.path.join(os.getenv("HOME", "/"), ".cacitesting-tracing-state.json")


def read_state():
    if not os.path.exists(STATE_FILE):
        raise Exception(f"State file {STATE_FILE} does not exist")
    with open(STATE_FILE, "rt") as f:
        return json.loads(f.read())

def write_state(state: dict):
    with open(STATE_FILE, "wt") as f:
        f.write(json.dumps(state))

STATUS_STARTED = "Started"
STATUS_COMPLETED = "Completed"

def trace_step(
    run_info: dict,
    step_name: str,
    status: str,
    error: str = None,
    output: dict = None,
):
    trace_obj = {
        **run_info,
        "Timestamp": datetime.now().isoformat(),
        "StepName": step_name,
        "Status": status,
        "Error": error,
        "Output": output,
    }

    client = KustoClient(conn)
    query_str = f".ingest inline into table {KUSTO_TABLE} with (format='json') <|\n  "
    query_str += json.dumps(trace_obj)
    query_str += "\n"
    client.execute(KUSTO_DATABASE, query_str)

    print(
        f"Traced {trace_obj['DeploymentName']}/{trace_obj['StepName']} @ {trace_obj['Timestamp']}: {trace_obj['Status']}" +
        (f" with error '{trace_obj['Error']}'" if trace_obj['Error'] else "")
    )
