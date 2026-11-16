"""Fail closed; only fixed addresses, actions and counts leave the raw plan."""
import json
import pathlib
import sys

ADDRESS = "azurerm_network_security_group.proposed"
DATA_ADDRESS = "data.azurerm_resource_group.lab"


def summarize(plan):
    if not isinstance(plan, dict) or plan.get("errored") is True:
        raise ValueError("Invalid plan")
    managed = []
    for item in plan.get("resource_changes", []):
        address = item.get("address")
        mode = item.get("mode")
        actions = item.get("change", {}).get("actions")
        if mode == "data" and address == DATA_ADDRESS and actions in (["read"], ["no-op"]):
            continue
        if mode != "managed" or address != ADDRESS or actions != ["create"]:
            raise ValueError("Unexpected change")
        managed.append(item)
    if len(managed) != 1 or plan.get("output_changes"):
        raise ValueError("Expected exactly one proposed create and no outputs")
    return ADDRESS + ": create\ncreate: 1\nupdate: 0\ndelete: 0\n"


def main():
    source, destination = map(pathlib.Path, sys.argv[1:])
    review = summarize(json.loads(source.read_text(encoding="utf-8")))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(review, encoding="utf-8")
    print(review, end="")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Plan review failed: expected one approved create and no other changes.", file=sys.stderr)
        sys.exit(1)
