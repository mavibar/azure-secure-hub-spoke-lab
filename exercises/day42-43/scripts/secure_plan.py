"""Keep Azure responses, Terraform logs, state and plans in runner-local storage."""
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

from summarize_plan import summarize


def paths():
    base = Path(os.environ["RUNNER_TEMP"]).resolve()
    return base, base / "day42-43-private", base / "day42-43-review"


def cleanup():
    base, private, review = paths()
    try:
        subprocess.run(["az", "logout"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass
    for target in (private, review, base / "day42-43-azure"):
        # Delete only these three fixed runner-local child directories.
        if target.resolve().parent != base:
            raise ValueError("Unexpected cleanup path")
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
    print("Runner-local session and plan cleanup finished; Azure resources are unchanged.", flush=True)


def main():
    os.umask(0o077)
    _, private, review = paths()
    private.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("TF_LOG", "TF_CLI_ARGS", "AZURE_STORAGE_")):
            env.pop(key)
    needed = ("ARM_CLIENT_ID", "ARM_TENANT_ID", "ARM_SUBSCRIPTION_ID", "LAB_RESOURCE_GROUP",
              "TFSTATE_STORAGE_ACCOUNT", "TFSTATE_CONTAINER", "TFSTATE_RESOURCE_GROUP")
    if not all(env.get(key) for key in needed):
        raise ValueError("Missing configuration")
    env.update(ARM_USE_OIDC="true", ARM_USE_AZUREAD="true", ARM_USE_CLI="false", TF_WORKSPACE="default",
               ARM_RESOURCE_PROVIDER_REGISTRATIONS="none", TF_DATA_DIR=str(private / "terraform-data"),
               TF_VAR_lab_resource_group=env["LAB_RESOURCE_GROUP"])
    source = Path(__file__).resolve().parents[1] / "terraform"
    if not (source / ".terraform.lock.hcl").is_file():
        raise ValueError("Missing reviewed provider lockfile")
    root = private / "terraform-root"
    root.mkdir()
    for name in ("main.tf", ".terraform.lock.hcl"):
        shutil.copy2(source / name, root / name)

    def run(args, label, timeout=120):
        out = private / (label + ".out")
        with out.open("wb") as stdout, (private / (label + ".err")).open("wb") as stderr:
            code = subprocess.run(args, env=env, stdout=stdout, stderr=stderr,
                                  timeout=timeout, check=False).returncode
        return code, out

    def require(args, label, timeout=120):
        print("Checking stage: " + label, flush=True)
        code, out = run(args, label, timeout)
        if code:
            raise ValueError("Command failed")
        return out

    account = json.loads(require(["az", "account", "show", "--output", "json"], "account").read_text())
    if account.get("id", "").lower() != env["ARM_SUBSCRIPTION_ID"].lower() or account.get("tenantId", "").lower() != env["ARM_TENANT_ID"].lower():
        raise ValueError("Wrong Azure context")
    if account.get("user", {}).get("type", "").lower() != "serviceprincipal" or account.get("user", {}).get("name", "").lower() != env["ARM_CLIENT_ID"].lower():
        raise ValueError("Wrong workload principal")
    group_id = "/subscriptions/" + env["ARM_SUBSCRIPTION_ID"] + "/resourceGroups/" + env["LAB_RESOURCE_GROUP"]
    url = "https://management.azure.com" + urllib.parse.quote(group_id, safe="/") + "?api-version=2021-04-01"
    group = json.loads(require(["az", "rest", "--method", "get", "--url", url, "--output", "json"], "group").read_text())
    if group.get("id", "").lower() != group_id.lower():
        raise ValueError("Wrong resource group")
    print("PASS: intended subscription/tenant selected and resource-group GET authorized.", flush=True)

    probe = ["az", "storage", "blob", "list", "--account-name", env["TFSTATE_STORAGE_ACCOUNT"],
             "--container-name", env["TFSTATE_CONTAINER"], "--auth-mode", "login", "--num-results", "1", "--output", "json", "--only-show-errors"]
    code, _ = run(probe, "network-baseline", timeout=40)
    print("Checking stage: runner public IP lookup", flush=True)

    with urllib.request.urlopen("https://api.ipify.org?format=json", timeout=20) as response:
        first = json.load(response)["ip"]

    print("First public IPv4 source: " + first, flush=True)

    with urllib.request.urlopen("https://checkip.amazonaws.com", timeout=20) as response:
        second = response.read(128).decode("ascii").strip()

    print("Second public IPv4 source: " + second, flush=True)

    public_ip = ipaddress.ip_address(first)
    if first != second or public_ip.version != 4 or not public_ip.is_global:
        raise ValueError("Public IP check failed")

    print("Runner public IPv4 (two services agree): " + str(public_ip), flush=True)
    print("Waiting up to ten minutes for the host administrator to allow this single IP on the existing state account.", flush=True)
    deadline = time.monotonic() + 600
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError("Network access window expired")
        try:
            code, _ = run(probe, "network-probe", timeout=min(40, remaining))
        except subprocess.TimeoutExpired:
            code = 1
        if code == 0:
            break
        if time.monotonic() >= deadline:
            raise ValueError("Network access window expired")
        time.sleep(min(15, max(0, deadline - time.monotonic())))
    print("PASS: existing backend container is reachable with Entra authentication.", flush=True)
    backend = {
        "storage_account_name": env["TFSTATE_STORAGE_ACCOUNT"],
        "container_name": env["TFSTATE_CONTAINER"],
        "resource_group_name": env["TFSTATE_RESOURCE_GROUP"],
        "key": "day42-43.tfstate",
        "tenant_id": env["ARM_TENANT_ID"],
        "subscription_id": env["ARM_SUBSCRIPTION_ID"],
        "client_id": env["ARM_CLIENT_ID"],
        "use_oidc": True, "use_azuread_auth": True,
        "use_cli": False, "lookup_blob_endpoint": False,
    }
    config = private / "backend.hcl"
    config.write_text("".join(key + " = " + json.dumps(value) + "\n" for key, value in backend.items()), encoding="utf-8")
    terraform = ["terraform", "-chdir=" + str(root)]
    require(terraform + ["init", "-input=false", "-no-color", "-lockfile=readonly", "-backend-config=" + str(config)], "init", 300)
    require(terraform + ["validate", "-no-color"], "validate")
    plan = private / "review.tfplan"
    print("Checking stage: plan", flush=True)
    code, _ = run(terraform + ["plan", "-input=false", "-no-color", "-detailed-exitcode", "-lock-timeout=30s", "-out=" + str(plan)], "plan", 300)
    if code not in (0, 2):
        raise ValueError("Terraform planning failed")
    if code != 2:
        raise ValueError("Expected a proposed create")
    raw = require(terraform + ["show", "-json", str(plan)], "plan-json")
    safe = summarize(json.loads(raw.read_text(encoding="utf-8")))
    lease = json.loads(require(["az", "storage", "blob", "show", "--account-name", env["TFSTATE_STORAGE_ACCOUNT"],
        "--container-name", env["TFSTATE_CONTAINER"], "--name", "day42-43.tfstate", "--auth-mode", "login", "--output", "json"], "lease-readback").read_text())
    if lease.get("properties", {}).get("lease", {}).get("status") != "unlocked":
        raise ValueError("State lease not verified unlocked")
    print("PASS: separate backend state lease is unlocked after plan.", flush=True)
    review.mkdir(parents=True, exist_ok=True)
    (review / "review.txt").write_text(safe, encoding="utf-8")
    print(safe, end="", flush=True)
    with open(env["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
        summary.write("## Reviewed plan\n\n```text\n" + safe + "```\n\nState lease: unlocked. No apply ran.\n")


if __name__ == "__main__":
    try:
        cleanup() if sys.argv[1:] == ["--cleanup"] else main()
    except Exception:
        print("Exercise stopped safely. Check exact identity, role scopes, runner IP and lockfile using the private host runbook. Raw logs and plans are not published.", file=sys.stderr)
        sys.exit(1)
