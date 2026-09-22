# Day 8 outbrief — identity and access planning

Status: **NOT RUN — replace pending values with actual evidence.**

## Session and continuity

- Date/time and timezone:
- Current Whizlabs session: existing / newly issued:
- Intended CLI configuration directory set before login: pending
- Signed-in subscription and current RG checked successfully: pending
- Role inventory scope checked against current RG: pending
- Starting Git branch and commit:
- Day 7 documentation closeout completed: pending
- Day 7 closeout commit/push, if actually completed:
- Private local evidence folder:
- Current network deployment: observed present / observed absent / not checked:

Day 7's historical 22-resource baseline is not automatically today's live deployment. Day 8 requires no network rebuild for RG-level role inventory. Keep credentials, tokens, full account identifiers, and raw inventory local; commit a sanitized summary.

## Read-only observations

| Evidence item | Observed / unavailable / not attempted | Actual result and local evidence filename |
|---|---|---|
| Current RG read | Pending | |
| Current RG role assignments | Pending | |
| Inherited assignment visibility | Pending | |
| Principal-name or group lookup visibility | Pending | |
| Visible assignment conditions | Pending | |
| Role definitions reviewed | Pending | |
| PIM eligibility/activation visibility | Not attempted unless separately observed | |
| Deny-assignment visibility | Not attempted unless separately observed | |

### Sanitized observed-assignment summary

| Principal description/type | Role | Scope level | Direct/inherited if known | Visible condition | Evidence status |
|---|---|---|---|---|---|
| Fill from actual output | | | | | |

- Exact command failures or visibility limitations:
- Meaning of any empty result:
- What this inventory does **not** establish about effective access:

Do not copy proposed groups into this table as if they existed. A role-list failure is “unavailable,” not “no assignments.” A condition or group-membership relationship not returned by the query is “not established,” not “absent.”

## Proposed access model

Mark every row **proposed** until a later implementation is authorized, performed, and verified.

| Future principal | Proposed role | Proposed scope | Justification/refinement | Status |
|---|---|---|---|---|
| Reader group | Reader | Lab RG | Review configuration | Proposed |
| Network-operator group | Network Contributor | Lab RG only for full network lifecycle | Narrow scope if duties are narrower | Proposed |
| Network Terraform federated identity | Network Contributor | Lab RG | Network automation only | Proposed |
| Full lab/VM provisioner, only if needed | Contributor | Lab RG | Reassess for future VM deployment | Proposed |
| Separate access administrator | Role Based Access Control Administrator | Lab RG | Privileged; constrained and short-lived where supported | Proposed |
| Application managed identity | Undecided | Undecided target service | No grant before service/action requirements exist | Proposed |

- Changes to the proposed design and why:
- Directory creation/assignment capabilities that remain unverified:
- Proposed separation between infrastructure deployment and role assignment:
- No `.tf` or live access changes made during Day 8: pending confirmation

## Future Day 9 test plan

- Isolated test identity available/permitted: unknown / yes / no; evidence:
- Proposed target: current Web NSG, verified in that future session
- Proposed role/scope: Reader at that NSG only
- Other direct/inherited/group grants that could invalidate the test: not yet established
- Expected read result: allowed
- Expected tag-write result: authorization denied
- Identity, command, error code, and unchanged-resource evidence to capture:
- If setup is unavailable, how the limitation will be recorded:
- Any actual Day 9 execution today: **none** (change only if separately performed and documented)

## Completion and handoff

- Overall result: completed / partially completed / blocked:
- Observed evidence collected:
- Proposed design completed:
- Remaining unavailable checks:
- Data → Web live traffic remains untested: yes / separately evidenced result:
- Cost visibility: not checked / unavailable / observed; details:
- Whizlabs session disposition and time:
- Sanitized Day 8 document commit:
- Push result:

## What I learned

1. An Entra identity, Azure role, NSG rule, and resource tag differ because: They all restrict access in different ways. 
2. The smallest useful scope for the planned read-only test is:
3. I cannot infer complete effective permissions from today's inventory because:


## Day 8 Results

### Observed

- Current Whizlabs sandbox identity successfully authenticated and current subscription/resource-group context was verified.
- Signed-in student user object ID was successfully resolved.
- The student user has a direct custom-role assignment at the current sandbox resource-group scope.
- Assigned custom role: `role_328971_1790107351130`.
- The custom role permits broad Azure resource management within its intended sandbox scopes, including networking, compute, storage, SQL, containers, Web, Key Vault, monitoring, and Azure Authorization operations.
- The custom role has no DataActions.
- The custom role contains NotActions that remove selected operations from its broad management permissions.
- Parent-scope role assignments were visible during the RG-scoped inherited-assignment inventory. Those assignments belong to multiple users and service principals and must not be interpreted as roles assigned to the student account.
- Reader, Network Contributor, Contributor, and Role Based Access Control Administrator role definitions were successfully inspected.

### Role comparison

- Reader: read Azure resources without modifying them.
- Network Contributor: manage network resources without becoming a general-purpose resource administrator.
- Contributor: broadly manage resources but cannot normally create/delete Azure RBAC role assignments.
- Role Based Access Control Administrator: manage Azure RBAC role assignments without becoming a general resource administrator.

### Proposed access design

- Configuration reviewers: Reader at the resource-group scope.
- Network operators/automation responsible for the full network lifecycle: Network Contributor at the resource-group scope.
- Smaller network maintenance jobs should use narrower individual-resource scopes where practical.
- Broader provisioning automation should receive Contributor only when its job genuinely requires multiple resource types.
- RBAC delegation should use a separate controlled access-administration identity rather than routine Owner assignments.
- Future workload identities should receive service-specific permissions scoped to their actual target resources.

### Day 9 readiness

- Test target: one Web NSG in the current Day 9 sandbox.
- Proposed temporary test grant: Reader scoped only to the target NSG.
- Positive test: test principal can read the target NSG.
- Negative test: harmless tag-write attempt should fail with an authorization error.
- Test principal must not inherit another write-capable role that would invalidate the test.
- Role creation/assignment and denied-write testing were not performed on Day 8.

### Limitations

- Role-assignment inventory does not by itself prove complete effective access.
- Group membership, deny assignments, PIM state, conditions and other authorization paths can affect effective permissions.
- No Terraform plan/apply, identity creation, role assignment, or permission test was performed on Day 8.

