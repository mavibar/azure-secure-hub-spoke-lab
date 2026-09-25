# Days 11 + 12 — grant, verify, revoke, clean up

Prepared September 25, 2026. **Fresh Whizlabs sandbox; maximum 120 minutes.** Follow this document in order, one PowerShell block at a time. Commands run on your Windows computer; the helper runs a small Python probe inside Azure. No local Python or Docker is needed.

**Day 10 is complete and fully cleaned**, committed/pushed as `3b41920` on `feat/day10-managed-identity`. Its ACI, identity, NSG and Reader grant are gone. This guide creates its own minimal fixtures and does not rerun Day 10.

## What the two days teach

**Day 11:** a new workload initially receives `403 Forbidden / ForbiddenByRbac` for a dummy secret. Assign only **Key Vault Secrets User** at this new vault. The same workload must then receive `200`, verify the exact secret version and match its hash, without printing the value.

**Day 12:** the original calendar says “Review identity controls”: examine sign-in protection and privileged access, test available controls, and remove temporary access. In Whizlabs we perform a read-only availability review of security defaults, Conditional Access and your directory-role PIM eligibility. We then test the control we can change safely: remove the exact workload grant and observe the **same running identity** return to an RBAC denial. Human MFA/Conditional Access/PIM enforcement is a separate, unperformed test; this lab does not substitute workload RBAC for it.

**Honest completion:** Day 11 can be COMPLETE. Day 12's workload revocation can pass, while the broader Day 12 lesson remains PARTIAL because provider-owned human controls were not live-tested. A blocked tenant feature is a documented boundary, not permission to create users, activate privilege, consent to new Graph permissions or change policies.

### Three files

- `DAY-11-12-RUNBOOK.md` — this guide, recovery procedure, results and tutor prompt.
- `Session-Day11-12.ps1` — readable helper functions and embedded workload probe.
- `DAY-11-12-DIAGRAM.png` — planned architecture and changes.

### Reuse and scope

| Fixture | Decision |
|---|---|
| Provider-issued resource group and current operator login | Reuse for both days; never delete the resource group. |
| One **new** Linux ACI + system-assigned identity | Run continuously across both days. No restart, redeployment or identity replacement. |
| One **new** RBAC Key Vault + one dummy secret version | Reuse unchanged for the revocation test. |
| Operator seed permission | Temporary **Key Vault Secrets Officer**, vault scope only; remove before Day 12 review. |
| Workload permission | Temporary **Key Vault Secrets User**, vault scope only; remove during Day 12, or cleanup if Day 12 is skipped. |
| Evidence, branch and recovery record | One of each for the session. Runtime values stay under ignored `local-evidence/`. |
| Historical Terraform network/state | Unchanged; not applied, imported, refreshed, destroyed or rebuilt. |

ACI has no configured public ingress, subnet attachment or hub/spoke role. Its outbound HTTPS reaches an authenticated public Key Vault endpoint. This deliberately isolates authorization, not private-network enforcement. A policy rejection ends the attempt; do not weaken an existing vault or switch to access policies. The new vault has RBAC enabled, purge protection and seven-day soft-delete retention. **Cleanup removes the active vault; its protected deleted copy remains. No purge is attempted.** [Key Vault access planes](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide), [soft deletion](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview).

### Clock and stop rules

| Elapsed time | Target |
|---|---|
| Before starting sandbox | Read guide, inspect helper and diagram, prepare local branch. |
| 0–10 | Current login, scope, providers, private recovery record. |
| 10–50 | Day 11 vault, seed, ACI, deny → grant → allow. |
| 50–95 | Day 12 review and allow → remove grant → deny. Finishing early means cleaning up early. |
| 95–115 | Shared cleanup and verification. |
| 115–120 | Cleanup buffer only. |
| After expiry | Sanitized results and Git. |

**If Day 11 proof is incomplete at minute 55, skip Day 12. Begin cleanup at minute 95; never later than minute 100.** Do not sacrifice cleanup to finish a probe. Set a visible external timer for minutes 50, 55 and 95. Helper checks prevent new experimental operations after its cutoff, but cannot preempt an Azure CLI command stuck in a network call. If a command hangs for about two minutes, press **Ctrl+C**, keep its recovery record, and inspect the exact attempt. Cancellation is not proof that Azure cancelled the operation.

Enter the **actual minutes remaining** when initialization starts, at most 120. The helper shortens its work window to reserve 25 minutes for cleanup when less time remains. Below 90 minutes, this combined workflow refuses initialization; do not pretend that a fresh two-hour budget remains.

## Phase 0 — local preparation, before the sandbox timer

**Purpose:** create one documentation branch and load helpers without creating Azure resources.

```powershell
$Repo = 'C:\git\azure-secure-hub-spoke-lab'
$Pack = 'C:\Users\Mark\.codex\.chatgpt-projects\g-p-6aa9a64566988191bf43c7cb9228820b\day11-day12'
# If you moved the three files, change only $Pack to that folder.
Set-Location $Repo
git status --short --branch
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
if (git status --porcelain) { throw 'Resolve existing work before switching branches; do not discard it.' }
git merge-base --is-ancestor 3b41920 HEAD
if ($LASTEXITCODE -ne 0) { throw 'Start from the completed Day 10 history; do not reset or overwrite another branch.' }
git switch -c feat/day11-12-identity-controls
if ($LASTEXITCODE -ne 0) { throw 'If this branch already exists, inspect it and use git switch feat/day11-12-identity-controls to resume.' }
if (git ls-files -- local-evidence) { throw 'Private evidence is already tracked. Resolve before running this lab.' }
Get-Content -LiteralPath (Join-Path $Pack 'Session-Day11-12.ps1') -TotalCount 65
. (Join-Path $Pack 'Session-Day11-12.ps1')
```

**Success evidence:** branch selected; helper functions loaded; no Azure deployment. The leading dot keeps functions and session variables available in this terminal. `--` separates Git options from paths; `$LASTEXITCODE` checks the previous native command.

**Stop:** wrong history, uncommitted work, missing helper/startup script, or tracked private evidence.

**Cleanup/recovery consequence:** no cloud resources exist from this phase. On a reopened terminal, load the helper again and use Phase R; do not initialize another run to recover this one.

## Phase 1 — verify today's identity and scope, minutes 0–10

**Purpose:** use current provider-issued values, isolate CLI login, and save recovery targets before any create.

```powershell
$SubscriptionId = (Read-Host 'CURRENT Whizlabs subscription ID').Trim()
$ResourceGroupName = (Read-Host 'CURRENT Whizlabs resource group').Trim()
$ExpectedUsername = (Read-Host 'CURRENT Whizlabs username').Trim()
$OwnerAlias = (Read-Host 'Non-secret owner alias, e.g. mark-lab').Trim()
$MinutesRemaining = [int](Read-Host 'Actual sandbox minutes LEFT, 90 through 120')
Initialize-Day1112 -Repo $Repo -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName -ExpectedUsername $ExpectedUsername `
    -OwnerAlias $OwnerAlias -MinutesRemaining $MinutesRemaining
Show-LabClock
Get-ChildItem -LiteralPath $Evidence -Filter 'operator-role-*.json' | ForEach-Object {
    (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).permissions |
        ConvertTo-Json -Depth 8
}
```

The helper dot-sources your existing `scripts\Initialize-LabContext.ps1`; it sets the private CLI cache before sign-in and validates username, subscription, tenant and exact RG. Enter credentials only on Microsoft's sign-in page. Compare the returned tenant with the provider's tenant when supplied. It never selects Terraform state.

It then calls **directly**, with explicit exit checking:

```powershell
# Reference only: already performed by Initialize-Day1112.
# $SelfRaw = az ad signed-in-user show --only-show-errors -o json
# if ($LASTEXITCODE -ne 0) { throw 'Cannot verify signed-in operator.' }
```

Do not pass this Entra command through `Invoke-LabAz`: that helper adds `--subscription`, which the directory command does not accept. [CLI reference](https://learn.microsoft.com/en-us/cli/azure/ad/signed-in-user?view=azure-cli-latest).

**Success evidence:** Microsoft.ContainerInstance and Microsoft.KeyVault are Registered; context matches the current sandbox; private `recovery.json` exists; current own role definitions are available for review. Verify scope/conditions and Actions covering ACI create/read/delete, vault create/read/delete and role-assignment create/read/delete. Wildcards can cover operations; NotActions, conditions, deny assignments and policy may still restrict them. Historical Day 8 privileges are not today's proof. If no own direct role is listed, use current RG → Access control (IAM) → View my access; do not infer another principal's permissions are yours.

**Stop:** context/provider mismatch, missing current permissions/visibility, or initialization past the preflight budget. Do not register providers or grant yourself broader roles to proceed.

**Cleanup/recovery consequence:** record contains exact intended resource IDs, current operator, location and deadlines, but no create has run. An unresolved active record blocks new initialization. All records and CLI errors remain local and private.

## Phase 2 — create one owned vault, minutes 10–18

**Purpose:** establish a fresh RBAC secret target without adopting any preexisting vault.

```powershell
New-Day11Vault
Show-LabClock
```

The helper inventories **vaults explicitly** (`az keyvault list --resource-type vault`), saves pre-create absence, then calls the Key Vault **REST checkNameAvailability** operation for `Microsoft.KeyVault/vaults`. This avoids the earlier CLI `check-name`/HSM confusion. It saves the attempt before `az keyvault create --no-wait`, then checks exact ID, tenant, owner/run tags, RBAC, purge protection, network configuration and retention. [Name-check API](https://learn.microsoft.com/en-us/rest/api/keyvault/keyvault/vaults/check-name-availability?view=rest-keyvault-keyvault-2024-11-01).

**Success evidence:** `VAULT VERIFIED`; metadata saved privately; new vault belongs to this recorded attempt. Name availability is a precheck, not ownership evidence.

**Stop:** unavailable name, denied name-check, ownership mismatch, policy error, or no verified vault within the four-minute polling budget. **No automatic renaming, recovery, adoption or repeated creates.**

**Cleanup/recovery consequence:** go to Phase R to inspect exact active/deleted state. If another resource occupies the name, never grant access to or delete it. This time-bounded run stops instead of gambling on replacement names. An uncertain asynchronous create remains unresolved even if one inventory is empty.

## Phase 3 — seed only a dummy secret, minutes 18–28

**Purpose:** give the operator temporary secret-management access to this one new vault, then create one harmless fixture.

```powershell
Initialize-DummySecret
Show-LabClock
```

The helper resolves **Key Vault Secrets Officer** at runtime, saves the precise assignment GUID/principal/role/scope **before** its create, and allows up to six minutes of **read-only metadata checks** for propagation. It sets the secret once, using `--query id` so the normal returned secret value is suppressed. It records the exact version URI and a SHA-256 hash; the value is `TRAINING-ONLY-` plus this run's random marker. Never replace it with a password, token or API key.

**Success evidence:** `DUMMY SECRET SEEDED`; one exact version and expected hash saved privately; no value printed. The operator grant is vault-scoped, not RG/subscription-scoped.

**Stop:** secret metadata unexpectedly already exists, non-RBAC readiness error, propagation timeout, uncertain secret-set result or role-creation failure. Do not repeatedly set the secret: each successful set creates a new version.

**Cleanup/recovery consequence:** both the operator grant and vault are already in recovery records. An uncertain set can be handled by deleting this owned vault during cleanup; no need to discover or print the value. Keep the exact failed grant ID; do not create another GUID to bypass the failure.

## Phase 4 — start the fresh workload and prove denial, minutes 28–40

**Purpose:** prove the new workload identity cannot initially read the secret.

```powershell
Start-Day11Workload
Wait-Day11Denial
Show-LabClock
```

The ACI definition uses one Linux container, 1 CPU/1.5 GiB, a system-assigned identity, `restartPolicy: Never`, no public ingress and no subnet. It obtains a Key Vault token from the ACI managed-identity endpoint and calls the **exact secret version**. No operator token or password enters the container. The principal does not exist until creation: Azure's returned principal ID is saved, then compared with the workload's reported token identity. Claims inspection is a consistency check; Key Vault validates the actual token. [ACI managed identity](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-managed-identity).

**Success evidence:** matching principal and tenant; `HTTP 403 Forbidden / ForbiddenByRbac BEFORE grant`. The probe prints safe status, identity and match fields; tokens and secret bodies remain in memory. Raw logs are private.

**Stop:** initial 200 = **FAILED EXPECTATION**; 401, 404, firewall 403, DNS failure or mismatched identity is not RBAC-denial proof. Image/capacity/policy/startup errors end the attempt. ACI startup polling is capped at eight minutes and denial polling at four, always bounded by the overall Day 11 deadline.

**Cleanup/recovery consequence:** ACI's exact intended ID was saved before create. Keep the container unchanged across both days. A terminated/stopped container is not permission to recreate an identity silently. The running probe stops its own requests at the work cutoff, but **does not delete ACI**.

## Phase 5 — grant minimum read access and verify, minutes 40–50

**Purpose:** demonstrate that secret DataActions, rather than management Actions, authorize the read.

```powershell
Grant-Day11Read
(Get-Content -LiteralPath (Join-Path $Evidence 'workload-read-role.json') -Raw |
    ConvertFrom-Json).permissions | ConvertTo-Json -Depth 8
Show-LabClock
```

This creates only **Key Vault Secrets User** at this disposable vault and waits at most eight minutes. Its DataActions permit secret contents to be read. Your operator's vault management Actions allow resource administration; they do not by themselves grant secret retrieval. **Key Vault Reader** is not a substitute for Secrets User. Vault scope is appropriate here because the entire vault contains only this app's dummy fixture; it is not a claim that the role is limited to one version. [Roles and access planes](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide).

**Success evidence:** `DAY 11 PROOF PASSED`; same principal; HTTP 200; `exactVersionMatch=true`; `valueMatch=true`; no value printed. Record Actions versus DataActions in your own words.

**Stop:** any mismatch, unexpected pregrant access or deadline. At minute 55 without complete proof, skip Day 12 and run Phase 8. Do not regrant with another GUID or broaden the role.

**Cleanup/recovery consequence:** Day 11 is **proof complete, cleanup pending**. Its final status becomes COMPLETE only after cleanup is verified. Do not delete ACI or vault now if proceeding to Day 12; do remove them in Phase 8 if skipping.

## Phase 6 — Day 12 gate and identity-control review, minutes 50–65

**Purpose:** inspect the available human controls and remove the operator's temporary seed privilege.

```powershell
Show-LabClock
Start-Day12Review
Show-LabClock
```

The gate requires Day 11 proof completed before minute 55 and at least 35 minutes before the cleanup cutoff. It removes and verifies absence of the **exact operator-seed assignment**, then uses existing CLI authentication for three read-only Graph requests. No new consent is requested.

| Read | What it tells you | What it cannot prove |
|---|---|---|
| Security defaults `isEnabled` | Visible tenant configuration. | Whether this particular login satisfied MFA. |
| Conditional Access policy sample | At most one visible policy; state/name recorded privately. | Complete policy coverage, effective user targeting, or enforcement. |
| Your direct directory-role PIM eligibility | Eligibility records returned for this operator. | Azure-resource PIM, group-derived eligibility, activation, or “no privilege anywhere.” |

Take five minutes to record: **MFA** strengthens human sign-in; **Conditional Access** evaluates sign-in conditions; **PIM** can make privilege eligible/time-limited; **RBAC** controls resource operations. A managed identity authenticates a workload without a stored application password. These solve different problems.

**Success evidence:** operator-seed grant absent; each Graph request recorded READABLE or UNAVAILABLE with its error preserved. A 403/consent/license error means **visibility unavailable**, not “feature disabled.” Empty results are not proof that no policy/eligibility exists. No live MFA, CA or PIM test is claimed, even if configuration reads succeed.

**Stop:** Day 12 time gate fails → cleanup. Permission-denied Graph reads do **not** block the workload revocation exercise; record them and continue. Do not add scopes, activate roles, change security defaults, enroll authentication methods or modify the provider tenant. If prompted for extra consent, cancel.

**Cleanup/recovery consequence:** no new resources or grants are introduced; one existing grant is removed. The workload-read grant remains only until Phase 7. See Microsoft's [security-defaults GET](https://learn.microsoft.com/en-us/graph/api/identitysecuritydefaultsenforcementpolicy-get?view=graph-rest-1.0), [CA list](https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies?view=graph-rest-1.0), and [directory PIM eligibility list](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleeligibilityscheduleinstances?view=graph-rest-1.0) for the permissions/visibility limits.

## Phase 7 — remove workload access and observe, minutes 65–90

**Purpose:** distinguish “role assignment deleted” from “data-plane access actually denied.”

```powershell
Test-Day12Revocation
Show-LabClock
```

The helper requires a successful read from the last 60 seconds, saves its sequence, deletes only the recorded Secrets User assignment using `az role assignment delete --ids`, and verifies that exact assignment is absent. It then waits up to **12 minutes** for a later `403 Forbidden / ForbiddenByRbac` from the unchanged workload. The later event must occur after absence was verified, not be an old Day 11 denial.

**Success evidence:** same ACI/principal, same secret version and vault; exact grant absent; fresh post-removal RBAC denial while the vault remains active. Do not delete/disable the secret or change network settings to manufacture failure.

**Stop:** continued 200 until the deadline = **PARTIAL: assignment absent; data-plane denial not observed within window**. Do not label that immediate enforcement or automatically label it FAILED EXPECTATION. Azure documents propagation delays; repeatedly requesting a managed-identity token does not guarantee a freshly evaluated authorization cache. A wrong identity, changed fixture or wrong-value result invalidates the expectation. [RBAC propagation](https://learn.microsoft.com/en-us/azure/role-based-access-control/troubleshooting).

**Cleanup/recovery consequence:** the workload grant should already be absent. Cleanup still verifies it and removes the host/vault. If the removal command was interrupted, use Phase R to inspect the saved ID. Never create another role assignment to restart the experiment. Finish early → clean up early; do not idle until minute 95.

## Phase 8 — shared cleanup, start by minute 95

**Purpose:** verify removal of every active fixture and exact temporary grant, preserving only private evidence and the protected deleted vault.

```powershell
Invoke-LabCleanup
Show-LabClock
```

Order: exact operator/workload grant IDs → owned ACI → owned active vault → fresh absence checks. No RG deletion, broad assignee deletion, Terraform destroy or vault purge. ACI deletion removes its system-assigned identity with its host.

**Success evidence:** `ExactGrantsAbsent=True`, `AciAbsent=True`, `ActiveVaultAbsent=True`, `CleanupVerified=True`. Active-resource absence requires successful current inventory reads. The Key Vault list explicitly requests vaults to avoid ambiguity with HSM inventory. A failed read never means absent. Protected soft-deleted-vault metadata is recorded when visible; access denied to `show-deleted` is an explicit evidence limitation, not permanent deletion.

**Stop:** cleanup does not stop just because a proof deadline passed. If anything remains unresolved, use the recovery block below and retry **the same recorded cleanup targets** before expiry. Each cleanup polling pass is capped at five minutes. Never let a cloud error or stale success flag become a cleanup success claim.

**Cleanup/recovery consequence:** an uncertain create that has never been observed/deleted stays unresolved even when one inventory is empty. Cleanup polls for its appearance, verifies tags, and deletes it if found. A grant attempt never observed in Azure also remains unresolved; preserve its exact GUID/error. If exact grants cannot be verified absent, the helper deletes the owned ACI for containment but retains the vault for targeted grant recovery. Unresolved ownership is never permission to delete someone else's fixture.

## Phase R — interrupted command, collision, or cleanup recovery

**Purpose:** restore the original recovery record and inspect exact state without creating anything new. Use at any failure; do not rerun Phase 1.

```powershell
$Repo = 'C:\git\azure-secure-hub-spoke-lab'
$Pack = 'C:\Users\Mark\.codex\.chatgpt-projects\g-p-6aa9a64566988191bf43c7cb9228820b\day11-day12'
. (Join-Path $Pack 'Session-Day11-12.ps1')
Resume-Day1112 -Repo $Repo
Inspect-LabRecovery
Show-LabClock
Invoke-LabCleanup
```

If the same sandbox login expired, restore it without changing targets, then rerun the recovery block:

```powershell
# After Resume-Day1112 has loaded R, use only this run's saved tenant/cache.
az login --tenant $R.tenant --use-device-code --output none
if ($LASTEXITCODE -ne 0) { throw 'Login failed; preserve records and report cleanup unverified.' }
az account set --subscription $R.subscription
if ($LASTEXITCODE -ne 0) { throw 'Recorded sandbox subscription unavailable.' }
Assert-LabOperator
```

**Success evidence:** same subscription/tenant/operator; original run ID and exact resource/grant IDs loaded; fresh active-vault/container/grant and deleted-vault inspection results. For a deleted vault, compare `properties.vaultId` with the original resource ID; its top-level deleted-proxy ID differs. [Deleted-vault response](https://learn.microsoft.com/en-us/rest/api/keyvault/keyvault/vaults/get-deleted?view=rest-keyvault-keyvault-2024-11-01).

**Stop:** a different sandbox, different owner tags, unknown deleted state or ambiguous create response blocks any new create/adoption. No automated retry with a new name/GUID is provided. A preflight name collision with no create attempt creates no ownership claim; an after-create collision still requires inspecting this exact attempt. Save the failure and end this run if ownership cannot be established.

**Cleanup/recovery consequence:** keep the private record even after expiry. If verification cannot finish, record **CLEANUP UNVERIFIED** and contact the provider with the exact private resource/grant IDs through its support channel. Do not claim expiry proves deletion, and do not put those identifiers in Git. Preparing this guide has not sent any support message.

## Phase 9 — results and Git, after cloud cleanup

**Purpose:** preserve learning and reproducible instructions without committing runtime data.

```powershell
Set-Location $Repo
Copy-Item -LiteralPath (Join-Path $Pack 'DAY-11-12-RUNBOOK.md') -Destination 'docs\day11-12-runbook.md'
Copy-Item -LiteralPath (Join-Path $Pack 'DAY-11-12-DIAGRAM.png') -Destination 'docs\day11-12-diagram.png'
Copy-Item -LiteralPath (Join-Path $Pack 'Session-Day11-12.ps1') -Destination 'scripts\Session-Day11-12.ps1'
notepad (Join-Path $Repo 'docs\day11-12-results.md')
# Paste and fill the template at the end of this guide; save it, then continue.
git diff -- infra/terraform
git add -- docs/day11-12-runbook.md docs/day11-12-diagram.png scripts/Session-Day11-12.ps1 docs/day11-12-results.md
if ($LASTEXITCODE -ne 0) { throw 'Staging failed.' }
git diff --cached --name-only
git diff --cached --check
git --no-pager diff --cached -- docs/day11-12-results.md
# Review: ONLY the four named public files; no runtime identifiers, values or raw logs.
git commit -m "docs: record Key Vault access and identity control review"
if ($LASTEXITCODE -ne 0) { throw 'Commit failed.' }
git push -u origin feat/day11-12-identity-controls
if ($LASTEXITCODE -ne 0) { throw 'Push failed; local commit remains.' }
git status --short --branch
```

**Success evidence:** Terraform diff empty; only the four intended files staged; sanitized results committed/pushed. The public helper generates IDs at runtime and embeds no live values. Do not copy `recovery.json`, ACI specification, Graph results, CLI cache, runtime IDs, raw logs, secret URI/hash/value or token contents into public docs. Never use `git add .` for this closeout.

**Stop:** unexpected staged files, runtime data in the result, Terraform changes, or no honest cleanup status. Remove unintended files from staging with `git restore --staged -- <exact-path>` after reviewing them; do not delete evidence.

**Cleanup/recovery consequence:** this phase needs no live sandbox. Describe cleanup gaps truthfully rather than waiting for a new sandbox to manufacture a pass.

## Short tutor prompt — copy into your command-help chat

> Walk me through DAY-11-12-RUNBOOK.md one phase at a time. Day 10 is complete and fully cleaned at 3b41920; never recreate its NSG experiment. Today uses one fresh ACI identity, one dummy-secret RBAC vault, direct-user/operator context and exact private recovery records. Preserve the 120-minute clock: skip Day 12 if Day 11 is incomplete by minute 55; cleanup at 95, no later than 100. Explain each PowerShell function and the Azure CLI operation it wraps. Do not print secrets/tokens or ask me to paste raw private evidence. Day 12 is identity-control review plus measured workload-access revocation; Graph visibility is not MFA/CA/PIM enforcement. Do not broaden roles, change tenant controls, recreate identities, adopt collided vaults or retry uncertain creates with new IDs. On errors, inspect the saved exact attempt and prioritize verified cleanup. Help fill the final results honestly.

## Preparation validation and limits

PowerShell syntax and offline mocked behavior are checked during preparation. Live Whizlabs permissions, Azure Policy, regional capacity, image pull, directory visibility and propagation are determined by your run; the preparing assistant has not deployed these resources. The image shows the planned lifecycle, not observed results. It was produced with the built-in image generator using the specification: “Azure-style landscape diagram; one new ACI/system identity and one new RBAC dummy-secret vault in current RG; Day11 403 → exact Secrets User grant → 200 version/hash match; Day12 same identity → exact grant removal → bounded 403 observation; read-only Entra CA/PIM review; temporary operator Secrets Officer removed; Day10 fully cleaned; historical Terraform unchanged; 120-minute schedule and cleanup gates.”

## Final results template — sanitized, both days

Choose **COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION** per day. COMPLETE means all claimed objectives and active cleanup were evidenced. PARTIAL means some proof exists but an objective or verification remains. BLOCKED means prerequisites prevented the objective. FAILED EXPECTATION means an observed result contradicted an expected security boundary, such as pregrant secret access. A later cleanup success does not erase a failed expectation.

```text
Session date:
Branch: feat/day11-12-identity-controls
Starting checkpoint: Day10 COMPLETE/CLEANED, 3b41920

DAY 11 status: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION
Fresh ACI/system identity; workload principal matched Azure principal: YES / NO
Before grant: HTTP ___ ; outer error ___ ; inner error ___
Grant: Key Vault Secrets User, disposable vault scope only
After grant: HTTP ___ ; exact version matched ___ ; dummy hash matched ___
Secret value/token printed: NO / INCIDENT (describe without including contents)
Actions versus DataActions, in one sentence:
Missing evidence or blocker:

DAY 12 status: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION
Security-defaults review: READABLE / UNAVAILABLE ; finding or limitation:
Conditional Access sample: READABLE / UNAVAILABLE ; finding or limitation:
Own direct directory-role PIM eligibility: READABLE / UNAVAILABLE ; limitation:
Human MFA / CA / PIM enforcement tested: NO in this Whizlabs workflow
Workload revocation subtest: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION
Fresh successful read immediately before removal: YES / NO
Exact workload assignment verified absent: YES / NO
Same principal + active unchanged vault + later 403 ForbiddenByRbac: YES / NO
Denial observed after approximately ___ minutes / NOT OBSERVED WITHIN WINDOW
Overall Day12 remains PARTIAL when human-control testing remains unperformed.

SHARED CLEANUP: VERIFIED / UNVERIFIED
Exact operator seed grant absent: YES / NO / NOT ATTEMPTED
Exact workload grant absent: YES / NO / NOT ATTEMPTED
ACI absent (system identity lifecycle ends with host): YES / NO / NOT ATTEMPTED
Active vault absent: YES / NO / NOT ATTEMPTED
Soft-deleted vault: MATCHING RECORD RETAINED / DETAILS UNVERIFIED / NOT CREATED
Purge performed: NO
Unresolved attempted creates/grants: NONE / describe without runtime identifiers
Cleanup started at minute ___ ; verified at minute ___
Terraform baseline unchanged; no old state applied: YES / NO
Private evidence retained outside Git: YES / NO
One lesson / one follow-up:
Commit/push: see Git history (or PENDING)
```
