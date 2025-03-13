#!/usr/bin/env python3
import sys
import os
import subprocess
import time
import json
import yaml


def run_cmd(cmd):
    print(f"Running command: {' '.join(cmd)}", flush=True)
    return subprocess.run(
        cmd, stdout=subprocess.PIPE, text=True, check=True
    ).stdout.strip()


def main():
    TEST_OUTPUT_FILE = "test_output.json"
    if len(sys.argv) != 2:
        print(
            f"Usage: {sys.argv[0]} <yaml-file>",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(1)

    yaml_file = sys.argv[1]
    with open(yaml_file, "r") as f:
        yaml_content = f.read()
    yaml_data = yaml.safe_load(yaml_content)
    deployment_name = yaml_data["metadata"]["name"]
    if not deployment_name:
        print(f"Failed to get deployment name from {yaml_file}", flush=True)
        sys.exit(1)
    label_selector_obj = yaml_data["spec"]["selector"]["matchLabels"]
    label_selector = ",".join([f"{k}={v}" for k, v in label_selector_obj.items()])
    replicas = yaml_data["spec"].get("replicas")
    if not replicas:
        print(f"Failed to get number of replicas from {yaml_file}", flush=True)
        sys.exit(1)
    print(f"Deployment name: {deployment_name}", flush=True)
    print(f"Label selector: {label_selector}", flush=True)
    print(f"Number of replicas: {replicas}", flush=True)

    # Deploy the deployment from the YAML template
    run_cmd(["kubectl", "apply", "-f", yaml_file])

    # Wait for all pods of the deployment to be in Running state (max 3 minutes)
    print("Waiting for pods to be in Running state...", flush=True)
    timeout = time.time() + 900

    seen_container_ids_for_pod = {}
    failed_container_ids = set()
    all_container_ids = set()

    def check_pod_containers(pod):

        # We check that the container IDs have not "flipped", which could
        # indicate a failure followed by a restart.  We do this by keeping track
        # of the IDs seen in the last round of checking in
        # seen_container_ids_for_pod.
        nonlocal seen_container_ids_for_pod
        nonlocal failed_container_ids
        nonlocal all_container_ids

        pod_name = pod["metadata"]["name"]
        pod_container_ids = set()
        has_issue = False
        for container in pod.get("status", {}).get("containerStatuses", []):
            container_id = container.get("containerID")
            container_name = container.get("name", "???")
            image_id = container.get("imageID", "???")
            restart_count = container.get("restartCount", 0)
            if not container_id:
                print(
                    f"  !: Container ID not found for container {container_name} in pod {pod_name}. Pod being restarted?"
                )
                # has_issue = True
                # If this pod has yet to be restarted, we let a later check fail
                # instead of this one, to give more information (i.e. what is
                # the restarted instance)
                continue
            pod_container_ids.add(container_id)
            all_container_ids.add(container_id)
            print(f"  Container {container_name}:", flush=True)
            print(f"    ID: {container_id}", flush=True)
            print(f"    Image ID: {image_id}", flush=True)
            print(f"    Restart Count: {restart_count}", flush=True)
            if restart_count > 0:
                print(
                    f"    !: Container {container_name} has restarted {restart_count} times!"
                )
                has_issue = True
        if pod_name in seen_container_ids_for_pod:
            for container_id in seen_container_ids_for_pod[pod_name]:
                if container_id not in pod_container_ids:
                    print(
                        f"    !: Container ID {container_id}, which appeared in a previous check of pod {pod_name}, has now disappeared"
                    )
                    failed_container_ids.add(container_id)
        if pod_container_ids:
            seen_container_ids_for_pod[pod_name] = pod_container_ids
        return has_issue

    nb_pods_running = 0
    nb_bad_pod = 0
    nb_good_pod = 0
    deployment_start_time = time.time()
    deployment_end_time = None

    # Don't bother printing errors to stderr as GitHub Actions messes up the order.

    def write_test_output(err_str: str = None):
        if deployment_end_time:
            deployment_time = deployment_end_time - deployment_start_time
        else:
            deployment_time = time.time() - deployment_start_time
        with open(TEST_OUTPUT_FILE, "wt") as f:
            json.dump(
                {
                    "err_str": err_str,
                    "replicas": replicas,
                    "failed_containers": list(failed_container_ids),
                    "success_containers": list(
                        all_container_ids.difference(failed_container_ids)
                    ),
                    "nb_bad_pod": nb_bad_pod,
                    "nb_good_pod": nb_good_pod,
                    "deployment_time_secs": deployment_time,
                },
                f,
                indent=4,
            )
            f.write("\n")
        if err_str:
            print(f"\x1b[31;1m{err_str}\x1b[0m", flush=True)

    while time.time() < timeout:
        pods_json = run_cmd(
            ["kubectl", "get", "pods", "-l", label_selector, "-o", "json"]
        )
        pods_data = json.loads(pods_json)
        if not pods_data.get("items"):
            print("No pods created yet.", flush=True)
            time.sleep(5)
            continue

        has_issue = False
        nb_pods_running = 0
        nb_bad_pod = 0
        nb_good_pod = 0
        for pod in pods_data["items"]:
            print(
                f"Pod {pod['metadata']['name']} status: {pod['status']['phase']}",
                flush=True,
            )
            if pod.get("status", {}).get("phase") == "Running":
                nb_pods_running += 1
                if check_pod_containers(pod):
                    print(
                        f"\x1b[31;1mERROR: Issue detected for pod {pod['metadata']['name']}. Pod info dump follows:\x1b[0m",
                        flush=True,
                    )
                    subprocess.run(
                        ["kubectl", "describe", "pod", pod["metadata"]["name"]],
                        check=True,
                    )
                    has_issue = True
                    nb_bad_pod += 1
                else:
                    nb_good_pod += 1
        if has_issue:
            write_test_output(f"Exiting due to issues detected during startup.")
            sys.exit(1)
        if nb_pods_running == replicas:
            print("\x1b[32;1mAll pods are running now.\x1b[0m", flush=True)
            break
        if nb_pods_running > replicas:
            write_test_output(
                f"AssertionError: More pods running ({nb_pods_running}) than expected ({replicas})."
            )
            sys.exit(1)

        print("Waiting for all pods to be running...", flush=True)
        time.sleep(5)

    if nb_pods_running < replicas:
        write_test_output("Timeout reached: not all pods are Running.")
        sys.exit(1)

    deployment_end_time = time.time()

    def check_pod_breakage():
        nonlocal seen_container_ids_for_pod, nb_good_pod, nb_bad_pod
        pods_json = run_cmd(
            ["kubectl", "get", "pods", "-l", label_selector, "-o", "json"]
        )
        pods_data = json.loads(pods_json)
        has_issue = False
        nb_good_pod = 0
        nb_bad_pod = 0
        for pod in pods_data.get("items", []):
            pod_has_issue = False
            pod_name = pod["metadata"]["name"]
            status = pod.get("status", {}).get("phase", "Unknown")
            conditions = pod.get("status", {}).get("conditions", [])
            all_condition_types = [
                condition.get("type", "???")
                for condition in sorted(
                    conditions, key=lambda x: x.get("lastTransitionTime")
                )
            ]
            start_time = pod.get("status", {}).get("startTime", "???")
            print(
                f"Pod {pod_name} - Status: {status}, Start Time: {start_time}",
                flush=True,
            )
            print(f"  Conditions: {', '.join(all_condition_types)}", flush=True)
            if status != "Running":
                print(f"  !: Status is not running!")
                pod_has_issue = True
            else:
                if check_pod_containers(pod):
                    pod_has_issue = True
            if pod_has_issue:
                print(
                    f"\x1b[31;1mERROR: Issue detected for pod {pod_name}. Pod info dump follows:\x1b[0m",
                    flush=True,
                )
                subprocess.run(["kubectl", "describe", "pod", pod_name], check=True)
                has_issue = True
                nb_bad_pod += 1
            else:
                nb_good_pod += 1
        return has_issue

    print("Monitoring pods for 1 hour...", flush=True)
    monitor_start = time.time()
    while time.time() < monitor_start + 3600:
        if check_pod_breakage():
            write_test_output("Pod breakage detected. Exiting with error.")
            sys.exit(1)
        print("", flush=True)
        time.sleep(10)

    if failed_container_ids:
        print(
            "\x1b[31;1mERROR: No restart count > 0 on any pods, but we have observed container IDs that have disappeared.\x1b[0m",
            flush=True,
        )
        for container_id in failed_container_ids:
            print(f"  Container ID: {container_id}", flush=True)
        print("Search in earlier logs for more information.", flush=True)
        write_test_output(
            "ERROR: No restart count > 0 on any pods, but we have observed container IDs that have disappeared."
        )
        sys.exit(1)

    print(f"VN2 deployment test passed (template={yaml_file})", flush=True)
    write_test_output()


if __name__ == "__main__":
    main()
