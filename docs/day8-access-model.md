# Day 8 identity and access model

Status: **PROPOSED DESIGN — no identities or assignments created by this document.**
Prepared September 21, 2026. Record live observations separately in day8-results.md.

## Design goal and boundary

Let each human or workload perform a defined job at the smallest practical scope. The established hub/spoke baseline has 22 managed instances. Day 8 documents authorization; it does not change network topology or deploy identity objects.

The temporary Whizlabs account belongs to the sandbox provider's tenant. Its actual role, inherited assignments, conditions and restrictions must be observed. It is not automatically equivalent to any proposed enterprise persona below.

## Proposed role matrix

Suggested names are design labels, not existing groups or accounts.

| Persona / proposed label | Principal type | Job | Candidate role | Smallest practical scope for this job | Rationale / limit |
|---|---|---|---|---|---|
| Current Whizlabs student | Provider-issued user | Run permitted sandbox exercises | **Observe; do not assume** | Whatever Whizlabs actually granted | Record visible assignments and unknowns; do not alter provider grants. |
| lab-security-reviewers | Entra security group | Read network/resource configuration | Reader | Current lab RG | Read-only control-plane inventory; no resource edits. Not a blanket service-data reader. |
| lab-network-operators | Entra security group | Maintain the full hub/spoke network lifecycle | Network Contributor | Current lab RG | Covers network objects across both VNets. For a narrower maintenance job, choose only the required existing VNet/NSG scopes instead. Can change NSGs and traffic paths. |
| lab-network-iac | Future federated service principal | Deploy only the network baseline from reviewed automation | Network Contributor | Current lab RG | Separate from the human operator and access administrator. Current Terraform still authenticates through the student's CLI session; federation is future work. |
| Future full-stack deployer | Separate future automation identity | Create approved compute plus networking | Contributor, **only if the defined job requires it** | A dedicated deployment RG; this lab's current RG only where authorized | Broader than today's network-only need. Excludes ordinary RBAC assignment writes but still has broad resource power and indirect data exposure risk. |
| lab-access-admins | Separately controlled Entra group | Delegate approved Azure roles | Role Based Access Control Administrator | Current lab RG or narrower delegation scope | Privileged: can grant powerful access absent constraints. Plan approved role/principal conditions and time-limited activation where supported; not standing deployer access. |
| Future app workload | Managed identity attached to a future supported resource | Access one defined backend service | **No grant selected yet**; choose a service-specific role when target/actions are known | Exact target service/resource, or narrower supported data scope | No blanket Contributor. A subnet is not itself a workload identity; no running app exists yet. |
| Day 9 temporary test subject | Isolated authorized test principal | Prove a read works and a write is denied | Reader | One current-session Web NSG | Subject must not also inherit write permissions. Deployment/access administrator remains a separate session. |

Network Contributor is a candidate based on this network-only task, not proof that every future provider operation will succeed. If an operation is denied later, inspect the exact action and scope before widening access.

References: [Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader), [Network Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/networking#network-contributor), [privileged roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged).

## Authentication choices

- Humans: individual Entra accounts, with group-based role assignments in the enterprise design. Tenant-managed MFA/Conditional Access is future governance, not something to configure in Whizlabs today.
- Current Terraform: Azure CLI authentication under the temporary student account, with current subscription and tenant runtime inputs.
- Future network automation: workload identity federation/OIDC with narrowly restricted issuer, subject and audience, plus the scoped Azure role. No stored password is proposed.
- Future lab workload: prefer a system-assigned managed identity if its lifecycle should follow one disposable supported workload. Consider a user-assigned identity only if independent lifecycle/reuse is required and permitted. Neither type is created today.
- Authorization remains separate: creating an identity does not automatically give it access to the target service.

References: [managed identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview), [federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation).

## Scope decisions

Prefer a resource scope for a task on one existing object. The entire lab network spans both VNets, NSGs and child resources, so RG scope is a practical boundary for its lifecycle operator. Creating a new resource generally requires permission at an existing enclosing scope. Subscription-wide roles are not the default.

A Reader assignment on a child resource does not cancel inherited Contributor permissions. Role grants accumulate; deny assignments and applicable conditions also affect authorization. NotActions subtracts from one role's permission set; it is not an overriding deny. See [scope hierarchy](https://learn.microsoft.com/en-us/azure/role-based-access-control/scope-overview) and [role definitions](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-definitions).

**Role definition assignableScopes is where a role can be assigned, not proof of where your account has been assigned it.** An assignment's scope is the relevant field for that observed grant.

## Permission layers to keep separate

| Layer | Example | What it governs |
|---|---|---|
| Azure resource authorization | Network Contributor on lab RG | Whether a principal can call permitted ARM operations on resources |
| Entra directory administration | Managing tenant users/groups | Directory objects; an Azure RG role does not grant tenant administration |
| Network controls | Web/App/Data NSGs | Packet filtering between endpoints |
| Application/data authorization | Future data-service role/login | What a workload can do with the service's data |
| Metadata | owner = mark-lab | Ownership label only, no access grant |

Contributor and Network Contributor having no DataActions does not guarantee their management powers cannot expose data indirectly. Reader's read-only management permissions do not mean it can read every service's data. [Actions and DataActions](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-definitions).

## Day 9 test design — future execution only

| Item | Proposed test |
|---|---|
| Actor | Isolated test principal authorized by sandbox rules, with a valid sign-in method |
| Target | Web NSG obtained from that day's Azure/Terraform context; never yesterday's resource ID |
| Grant | Reader at that one NSG only |
| Positive test | Read that NSG by full resource ID; expected success |
| Negative test | Attempt a harmless tag update on that same NSG as the test actor; expected authorization denial |
| Isolation check | No inherited Contributor/Owner/Network Contributor, broad groups, other write role or privileged activation available to the actor |
| Control | Known authorized administrator can read the same existing target, ruling out a missing-resource test |
| Cleanup | Remove the exact temporary assignment; restore any unexpected tag mutation; remove only lab-created temporary identity resources if authorized |
| Evidence | Actor identity/scope verified, read result, write denial including action/scope, cleanup result; sensitive IDs stay local |
| If prerequisites unavailable | Record blocked; retain the design. Do not substitute the privileged student account and call it a restricted-principal test. |

An error caused by malformed syntax, expired login, missing target or network trouble is not proof of an RBAC denial. Recheck the error and actor context. Role propagation may take time; avoid interpreting an immediate result without that context.

No Day 9 grant, write attempt, principal creation, or permissions test runs as part of Day 8.

## Decisions to finish today

- [ ] Assign a named responsibility to each proposed persona.
- [ ] Justify each role and scope; narrow any broader-than-needed choice.
- [ ] Record which observed student privileges are known and which are unavailable.
- [ ] Keep desired enterprise groups/identities labeled proposed.
- [ ] Decide whether Day 9 has a permitted isolated test actor, grant authority, target, sign-in and cleanup path.
- [ ] Keep Data → Web live-traffic testing as a separate unfinished network requirement.

Completion here means **design reviewed**, not roles granted or permissions tested.

