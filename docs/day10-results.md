# Day 10 results

Status: COMPLETED

Session date: September 24, 2026
Branch: feat/day10-managed-identity

Day 8 checkpoint: 86ee88a
Day 9 human-user test: BLOCKED because Whizlabs provides one user.

## Context and prerequisites

- Microsoft.ContainerInstance: Registered
- Microsoft.Network: Registered
- Current sandbox permissions allowed the required temporary resource and RBAC operations.

## Managed identity experiment

ACI + system-assigned identity created:
- Yes.
- Azure assigned a new workload identity to the container.
- No human username, password, or application secret was created.

Logged workload principal matched Azure container principal:
- Yes.

NSG read:
- HTTP 200
- Result: ALLOW

NSG tag write:
- HTTP 403
- Error: AuthorizationFailed
- Denied action: Microsoft.Network/networkSecurityGroups/write
- Scope: temporary Day 10 NSG

This demonstrated that the managed identity could authenticate successfully while Azure RBAC separately limited what that authenticated identity was authorized to do.

## Cleanup

Owner tag unchanged/restored:
- Verified.

Exact temporary Reader assignment absent:
- Verified.

Temporary ACI container absent:
- Verified.

Temporary NSG absent:
- Verified.

Cleanup result:
- Exact grant and both temporary resource IDs verified absent.

## Learning

Managed identity answers:
- Who is this workload?

Azure RBAC answers:
- What is this workload allowed to do?
- At what scope?

The workload's Reader assignment on the temporary NSG allowed configuration reads but did not permit Microsoft.Network/networkSecurityGroups/write.

A system-assigned managed identity follows the lifecycle of its Azure host resource.

## Evidence

Raw runtime evidence remains under local-evidence and is excluded from Git.

Day 11:
- NOT COMPLETED.
- Key Vault work will be resumed in a separate lab session.

Commit / push:
- See Git history and remote branch.

