# Day 8 professor notes — plan identity and access

Use these notes with `DAY-8-RUNBOOK.md`. Today's deliverable is an access design supported by a read-only inventory of the current Whizlabs resource group. Creating identities or role assignments is a later exercise.

## Start with four separate questions

| Control | Question it answers | Example in this lab |
|---|---|---|
| Microsoft Entra identity | Who is signing in or requesting access? | The temporary Whizlabs user; a future automation identity. |
| Azure RBAC | Which resource-management operations may that identity perform, and where? | Read an NSG; change an NSG; assign another identity a role. |
| Network security group | Which network connections may cross the subnet's policy? | Permit App → Data on TCP1433. |
| Resource tag | How is the resource labelled? | `owner=mark-lab`. |

Microsoft Entra **directory roles** administer directory objects such as users and groups. Azure roles administer Azure resources. They are separate permission systems; an Azure resource role does not by itself grant permission to create Entra users or groups. See Microsoft's [role comparison](https://learn.microsoft.com/en-us/azure/role-based-access-control/rbac-and-directory-admin-roles).

The built-in Azure **Owner** role is a powerful access grant. The lowercase `owner` tag is a metadata label. Changing that tag on Day 7 did not grant or revoke a role, and an NSG allow rule does not give a person permission to edit Azure resources.

Azure RBAC also supports data access for services integrated with it through DataActions. Today's four comparison roles focus on management permissions; service-data permissions must be selected separately when a workload target is known. Management powers can also expose data indirectly, so an empty DataActions list does not make a powerful deployer harmless.

## A role assignment has three parts

**Principal + role + scope** means **who + permitted operations + where**. For example, a proposed reader group with Reader on today's resource group would be able to read control-plane information within that scope. It would not acquire every data-access permission for services in that group. See the [RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview).

Scope matters as much as the role name. A resource-group grant reaches resources beneath that group. A grant on one NSG is narrower. Resource-group scope is appropriate for an operator responsible for the full network lifecycle; an operator who maintains only one NSG should receive a narrower scope or role suited to that job.

## Proposed identities — none created today

| Future principal | Proposed role and scope | Reason and boundary |
|---|---|---|
| Reader group | Reader on the lab RG | Review resource configuration. No management writes are added by this role. |
| Network-operator group | Network Contributor on the lab RG, only for full network lifecycle responsibility | Manage VNets, subnets, peering, and NSGs. This role is broader than editing one rule. |
| Network Terraform automation identity | Network Contributor on the lab RG; future federated service principal | Separate automation from the temporary human login. Limit it to the network workload. |
| Future full lab/VM provisioner | Contributor on the lab RG, only when that broader deployment is actually needed | Network Contributor does not cover VM deployment. Reassess exact workload permissions before introducing this broader identity. |
| Separate access administrator | Role Based Access Control Administrator on the lab RG, future conditional and short-lived use | Keep role assignment separate from ordinary infrastructure changes. |
| Future application workload | Managed identity; no grant proposed until the target service and operation are known | Choose the relevant service/data role and the smallest useful target scope later. |

Reader supplies control-plane reads. Network Contributor supplies network management, but does not grant VM deployment. See [Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader) and [Network Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/networking#network-contributor).

Contributor is broad resource-management access and does not itself permit Azure RBAC role assignment. Role Based Access Control Administrator can assign roles, so an unconstrained holder can grant powerful access within its scope. Treat that identity as privileged: propose conditions limiting roles/principals, time limits where supported, and a separate administrator workflow. These controls remain designs until the sandbox's capabilities and permissions are confirmed. See [privileged built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged).

Federation is a future way for automation to use a trusted external token instead of maintaining an application password. It does not choose the role or make an overbroad role safe. See [workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation).

## What today's inventory can establish

Save the returned role, principal type/ID, scope, and any visible condition. Label each result:

- **Observed:** returned by a successful command for the checked current scope.
- **Proposed:** a design decision; it is not deployed.
- **Unavailable:** the command or necessary directory lookup was blocked, unsupported, or inconclusive.

A list of assignments is not a complete calculation of effective access. Inheritance and group membership matter; PIM eligibility/activation, deny assignments, assignment conditions, and visibility limits can change the interpretation. Azure roles add permissions: adding Reader to an identity that already has Contributor does not restrict it to read-only access. See [RBAC evaluation](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview).

Microsoft's CLI guide explains inherited and transitive-group listing options. A successful scoped list, an empty list, and an authorization error are three different observations. A failed directory name lookup does not establish that a principal has no access; retain the returned object IDs when available. See [listing role assignments](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-list-cli).

## Why the startup checks still matter

Set `AZURE_CONFIG_DIR` before logging in so this lab session uses the intended CLI credential cache. Then verify the actual subscription and RG before using them to form a scope. Do not construct names or scopes from blank variables: a value such as `whiz--` signals missing inputs, not a valid workspace choice.

The 22-resource network baseline is historical evidence from Day 7. Day 8 can read the current Whizlabs RG's role assignments even if that network has expired. No network rebuild is needed just to complete the identity inventory and design. Never use an old Terraform output as proof of today's deployed resource ID.

## Designing the Day 9 permission test

Propose a separate test identity with **Reader at the Web NSG resource scope**, provided the sandbox permits the required setup. Under that identity, an NSG read should succeed and an attempted tag write should be denied. No assignment or write test is performed on Day 8.

The identity must lack other grants that permit the attempted write; reusing the provisioning account would not demonstrate Reader's boundary. A denied test should show an authorization failure for the intended action. Wrong subscription, missing resource, an expired login, or command syntax errors are not evidence that RBAC enforced the boundary. If the sandbox cannot support the isolated identity, record the test as unavailable rather than claim a successful negative test.

## Explain it back

1. Why did changing the `owner` tag leave access permissions unchanged?
2. Why does a full network operator need a different role from a read-only reviewer?
3. Why is role assignment authority separated from network deployment?
4. Why does an empty or incomplete assignment list not prove zero access?
5. Why would adding Reader to the current provisioning account be an invalid read-only test?
