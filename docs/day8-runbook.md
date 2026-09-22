# Day 8 — Plan identity and least-privilege access

Prepared September 21, 2026. Read alongside DAY-8-PROFESSOR-NOTES.md.
**Finish line:** inspect the access information Whizlabs permits you to see, distinguish observed privileges from a proposed enterprise design, complete the access model, and prepare a scoped Day 9 test.

**Today's Azure work is read-only.** You will not create identities, grant/revoke roles, edit NSGs, deploy resources or apply Terraform. Your durable outputs are the access design and its supporting evidence.

## 1. What Day 7 actually completed

Saved evidence confirms Web NSG owner drift was repaired from day7-drift-demo to mark-lab, the final plan exited 0, and 22 managed instances remained. Both peering states, three subnet/NSG links, four Management/Web/App/Data outbound flags and five owner tags were captured successfully. State serial advanced 23 → 25 with the same lineage.

The inspected Day 7 branch tracks its origin branch but still points to Day 6 commit ad7c68f, with no Day 7 documents in docs. The supplied DAY-7-RECONCILED-RESULTS.md closes that documentation gap in the next reviewed commit. You do not need to repeat the drift exercise.

Data → Web remains untested with real traffic. Day 7 cost visibility and exact session-end time were not found in saved evidence.

## 2. Today's schedule and sandbox choice

| Part | Budget | Result |
|---|---:|---|
| Checkpoint, files and startup | 10–15 min | Correct working context |
| Read existing access/role definitions | 15–20 min | Observed facts and limitations |
| Complete access design | 20–25 min | Principal + role + scope decisions |
| Day 9 readiness and documentation | 15 min | Test plan and Git checkpoint |

Allow about 60–75 minutes. A fresh Whizlabs session provides an existing resource group, which is sufficient for today's RG-level reads. **Do not rebuild the 22-resource network just to inspect access.** The diagram's network is the established design, last verified on Day 7, not a claim it exists in today's new subscription/RG.

If sandbox access is unavailable, complete section 3, skip live steps 4–8, and complete sections 9–12 with inspection marked unavailable. Do not invent observed assignments. You can still prepare a useful design, with the inspection limitation recorded.

## 3. Create the Day 8 branch and locate the pack

Use PowerShell and copy plain code blocks without PS prompt markers or HTML. Native CLI commands are kept on one line.

~~~powershell
$Repo = 'C:\git\azure-secure-hub-spoke-lab'
$TfRoot = Join-Path $Repo 'infra\terraform'
$Pack = 'C:\Users\Mark\.codex\.chatgpt-projects\g-p-6aa9a64566988191bf43c7cb9228820b\day8'
Set-Location $Repo
git status --short --branch
git log -3 --oneline
Get-ChildItem docs -File | Select-Object Name
~~~

If you extracted the ZIP elsewhere, set $Pack to the extracted Day-8-Lab-Pack folder containing docs and scripts.

Expected inspected starting point: clean feat/day7-state-drift at ad7c68f. If your checkout now contains newer work, preserve it and use its actual checkpoint.

First run:

~~~powershell
git switch -c feat/day8-identity-access
if ($LASTEXITCODE -ne 0) { throw 'Branch creation failed. If resuming, select the existing Day 8 branch.' }
~~~

On a resumed session, use git switch feat/day8-identity-access instead. Keep the existing Terraform source unchanged.

## 4. Use a consistent startup sequence

The included Initialize-LabContext.ps1 addresses Day 7's setup issues: it sets the CLI cache before login, validates the expected account and RG, then sets runtime inputs only after successful checks. It **does not select/create a Terraform workspace**.

Read it first:

~~~powershell
Get-Content -LiteralPath (Join-Path $Pack 'scripts\Initialize-LabContext.ps1')
~~~

Enter values from the **current** Whizlabs session:

~~~powershell
$CurrentSubscriptionId = (Read-Host 'Current Whizlabs subscription ID').Trim()
$CurrentResourceGroup = (Read-Host 'Current Whizlabs resource group name').Trim()
$CurrentWhizlabsUser = (Read-Host 'Current Whizlabs sign-in username').Trim()
$CurrentOwnerAlias = (Read-Host 'Non-secret owner alias (previously mark-lab)').Trim()
$LabContextReady = $false
. (Join-Path $Pack 'scripts\Initialize-LabContext.ps1') -SubscriptionId $CurrentSubscriptionId -ResourceGroupName $CurrentResourceGroup -ExpectedUsername $CurrentWhizlabsUser -OwnerAlias $CurrentOwnerAlias
if (-not $LabContextReady) { throw 'Lab context is not verified.' }
~~~

The leading **dot and space** run the script in this terminal, so $Account, $LabGroup and $LabScope remain available for subsequent commands. Enter passwords only on the Microsoft sign-in page. The script does not request a password argument or put a login username/password in Terraform.

The output must show today's user, subscription, tenant and RG, with ContextReady true. If the cached login is expired or wrong, rerun the complete startup block, including $LabContextReady = $false, with -ForceLogin appended to the helper invocation. Verify the supplied current values first.

The script sets the established runtime Terraform inputs for continuity, including enable_test_hosts=false, but Day 8 does not invoke Terraform. Existing tfvars or other provider overrides would still need review before a later Terraform run.

**Important:** your selected Terraform workspace may still describe the expired Day 7 sandbox. That is expected when doing only today's Azure RBAC reads. Do not use old terraform output IDs as today's scope and do not run plan/apply against that old state. Day 9 will select the matching current state and rebuild only what its test needs.

## 5. Create private evidence storage

~~~powershell
if (-not $LabContextReady -or [string]::IsNullOrWhiteSpace($LabScope)) { throw 'Run the startup step in this terminal first.' }
$EvidenceDir = Join-Path $Repo ('local-evidence\day8-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$EvidenceProbe = 'local-evidence/' + (Split-Path $EvidenceDir -Leaf) + '/ignore-check.txt'
git -C $Repo check-ignore --quiet -- $EvidenceProbe
if ($LASTEXITCODE -ne 0) { throw 'Evidence folder is not ignored. Add /local-evidence/ to .gitignore and review that edit first.' }
New-Item -ItemType Directory -Force -Path $EvidenceDir -ErrorAction Stop | Out-Null
$ContextRecord = [pscustomobject]@{ObservedAt=(Get-Date).ToString('o'); User=$Account.user.name; Subscription=$Account.id; Tenant=$Account.tenantId; ResourceGroup=$LabGroup.name; Scope=$LabScope}
$ContextRecord | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'session-context.json') -Encoding UTF8
~~~

Raw identity IDs, scopes and role-assignment JSON stay in ignored evidence. Commit a sanitized results summary using labels such as “current sandbox RG” and “student user.”

## 6. Read assignments visible at the RG and its parents

Before running this, predict what you expect to learn: **which principals have which listed role at which assignment scope**. You are not yet calculating every permission your user can exercise.

~~~powershell
$Assignments = @()
$AssignmentStatus = 'Unavailable'
$AssignmentJson = az role assignment list --scope $LabScope --include-inherited --fill-principal-name false --subscription $Account.id --only-show-errors --output json
$AssignmentExit = $LASTEXITCODE
if ($AssignmentExit -eq 0) {
    $Assignments = @($AssignmentJson | ConvertFrom-Json -ErrorAction Stop)
    $AssignmentJson | Set-Content -LiteralPath (Join-Path $EvidenceDir 'rg-and-parent-role-assignments.json') -Encoding UTF8
    $AssignmentStatus = 'Observed'
    $Assignments | Select-Object roleDefinitionName, principalType, principalId, scope, condition, conditionVersion | Format-Table -Wrap
} else {
    "Role-assignment inventory unavailable; exit $AssignmentExit" | Set-Content -LiteralPath (Join-Path $EvidenceDir 'role-assignment-read-status.txt')
    Write-Warning 'Record the displayed error. Continue with role research/design; do not interpret this as zero assignments.'
}
~~~

--include-inherited includes parent-scope assignments in the returned view. --fill-principal-name false avoids a Microsoft Graph name-lookup dependency; principal IDs may remain unlabeled. A GUID is an identifier, not a readable role name or evidence of an error.

For each observed assignment, identify:

- Principal type and ID: who received this grant.
- Role definition/name: what permission set it references.
- Assignment scope: where it applies, and whether inherited from above the RG.
- Condition: whether a restriction is recorded.

If no role name is filled, retain its roleDefinitionId locally rather than guessing. This RG/parent query is not an inventory of every possible child-resource assignment. [CLI assignment reference](https://learn.microsoft.com/en-us/cli/azure/role/assignment?view=azure-cli-latest#az-role-assignment-list).

## 7. Optionally identify the current user object

This read uses Microsoft Graph and may be unavailable in the sandbox. It is useful but not required to complete the design.

~~~powershell
$UserObjectId = $null
$UserLookupStatus = 'Unavailable'
if ($Account.user.type -eq 'user') {
    $UserObjectIdText = az ad signed-in-user show --query id --output tsv --only-show-errors
    $UserLookupExit = $LASTEXITCODE
    if ($UserLookupExit -eq 0 -and -not [string]::IsNullOrWhiteSpace(($UserObjectIdText -join ''))) {
        $UserObjectId = ($UserObjectIdText -join '').Trim()
        $UserLookupStatus = 'Observed'
        $UserObjectId | Set-Content -LiteralPath (Join-Path $EvidenceDir 'signed-in-user-object-id.txt')
        if ($AssignmentStatus -eq 'Observed') {
            $DirectUserAssignments = @($Assignments | Where-Object principalId -EQ $UserObjectId)
            $DirectUserAssignments | Select-Object roleDefinitionName, scope, condition | Format-Table -Wrap
            "Direct-user rows in captured view: $($DirectUserAssignments.Count)"
        }
    } else {
        Write-Warning 'User object lookup unavailable. Keep principal IDs unresolved and document this limitation.'
    }
}
~~~

A zero-row direct-user match does not mean the user has no access. Access can come through groups or other assignment scopes, and this query does not resolve those paths. Do not decode or paste access tokens to work around a Graph restriction.

Optional portal corroboration: current RG → Access control (IAM) → View my access / Role assignments. Read Deny assignments if allowed. Record the displayed scope and whether a grant is inherited. If PIM eligibility/activation or group membership is unavailable, mark it unknown; do not activate a privileged role just to complete this inventory.

**Evidence limit:** assignments plus roles are not a complete effective-access calculation. Group membership, active/eligible privileged access, deny assignments, conditions, other scopes and service-specific authorization can matter. A permission test is a separate step, planned for Day 9. [List assignments](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-list-cli).

## 8. Inspect four built-in role definitions

These are permission sets available for assignment, not evidence that your account holds them.

~~~powershell
$RoleNames = @('Reader', 'Network Contributor', 'Contributor', 'Role Based Access Control Administrator')
$RoleLookupResults = foreach ($RoleName in $RoleNames) {
    $RoleJson = az role definition list --name $RoleName --scope $LabScope --subscription $Account.id --only-show-errors --output json
    $RoleExit = $LASTEXITCODE
    if ($RoleExit -eq 0) {
        $Definitions = @($RoleJson | ConvertFrom-Json -ErrorAction Stop)
        if ($Definitions.Count -gt 0) {
            $RoleFileName = ($RoleName.ToLowerInvariant() -replace '[^a-z0-9]+', '-') + '.json'
            $RoleJson | Set-Content -LiteralPath (Join-Path $EvidenceDir $RoleFileName) -Encoding UTF8
            foreach ($Definition in $Definitions) {
                $Definition | Select-Object roleName, description | Format-List | Out-Host
                $Definition.permissions | ConvertTo-Json -Depth 20 | Out-Host
            }
            [pscustomobject]@{Role=$RoleName;Status='Observed';ExitCode=$RoleExit}
        } else {
            [pscustomobject]@{Role=$RoleName;Status='No definition returned; verify lookup';ExitCode=$RoleExit}
        }
    } else {
        [pscustomobject]@{Role=$RoleName;Status='Unavailable; consult official definition';ExitCode=$RoleExit}
    }
}
$RoleLookupResults | Format-Table -AutoSize
$RoleLookupResults | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $EvidenceDir 'role-definition-read-status.csv')
~~~

Use these questions to read the permissions object:

| Field | Question |
|---|---|
| Actions | Which management operations does this role allow? |
| NotActions | Which operations are removed from that role's wildcard allowance? |
| DataActions | Which service-data operations are allowed? |
| NotDataActions | Which are removed from that role's data allowance? |

NotActions is not an overriding deny against another role. A role's assignableScopes field describes where that role may be assigned; it is not your assignment scope. [Role definitions](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-definitions), [definition CLI](https://learn.microsoft.com/en-us/cli/azure/role/definition?view=azure-cli-latest#az-role-definition-list).

Use the official linked definitions in DAY-8-ACCESS-MODEL.md if reads fail. Record “researched definition; live lookup unavailable,” not “observed permission.”

## 9. Complete the proposed access model

Open **DAY-8-ACCESS-MODEL.md** and walk through every row. It is prefilled with a proposed design, so you can start by evaluating concrete choices.

For each persona, write:

1. What job must it perform?
2. Which principal type fits: human group, automation service principal, or workload managed identity?
3. Which role allows that job?
4. Why is the selected scope sufficient, and could it be smaller?
5. Which powers are deliberately absent?
6. What evidence would prove that the eventual assignment works?

Key decisions:

- Reader at the RG for configuration reviewers.
- Network Contributor at the RG for operators/automation responsible for the **full network lifecycle**; individual resource scopes for smaller maintenance jobs.
- Contributor only if a future broader provisioning job genuinely needs compute and other resource types.
- A separate, controlled access administrator for role delegation; no routine Owner assignment.
- Future workload identities receive service-specific permissions at their target, once that target and actions are defined.
- Today's temporary student account is observed separately from these future enterprise personas.

Reader at a child NSG will not restrict someone who already inherits Contributor. A group's display name is not proof it exists. Tags, NSGs, Azure RBAC roles and Entra directory roles serve different purposes. [RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview).

No Azure permissions are granted by editing this Markdown table.

## 10. Prepare the Day 9 permission test

Calendar Day 9 is scoped RBAC practice; Day 10 introduces a managed identity. Today only document readiness:

| Prerequisite | Record today |
|---|---|
| Test subject | Is an isolated, authorized principal available or permitted to be created later? Record type/alias, not secrets. |
| Authenticating as that subject | Supported sign-in method that fits sandbox constraints; no assumed ability to create credentials. |
| Grant authority | Observed evidence/unknown for role-assignment authority at target scope. A role-name guess is insufficient. |
| Target | One Web NSG in that day's sandbox; may need a baseline rebuild on Day 9. |
| Proposed grant | Reader at that NSG only. |
| Positive test | Read the target by its full current resource ID. |
| Negative test | Harmless tag-write attempt as the test subject should receive an authorization denial. |
| Isolation | No inherited write roles, broad group privileges or active elevated role on the test subject. |
| Cleanup | Authorized removal of the exact temporary assignment; restore any unexpected write and remove only lab-created identity objects where permitted. |

Do not perform the grant or denied-write test today. If identity creation or assignment authority is blocked, record that as a Day 9 constraint. We can choose a permitted test path from the actual evidence; using a privileged account does not prove Reader restrictions.

A future Reader grant does not itself give an identity a login credential, and a successful login does not establish resource authorization.

## 11. Record honest outcomes and save the materials

~~~powershell
Set-Location $Repo
$DocsDir = Join-Path $Repo 'docs'
$ScriptsDir = Join-Path $Repo 'scripts'
New-Item -ItemType Directory -Force -Path $ScriptsDir -ErrorAction Stop | Out-Null
$Day8Files = @{
    'DAY-8-RUNBOOK.md' = 'day8-runbook.md'
    'DAY-8-PROFESSOR-NOTES.md' = 'day8-identity-access-notes.md'
    'DAY-8-ACCESS-MODEL.md' = 'day8-access-model.md'
    'DAY-8-DIAGRAM-CHANGES.md' = 'day8-diagram-changes.md'
    'day8-architecture.png' = 'day8-architecture.png'
}
foreach ($SourceFile in $Day8Files.Keys) {
    $DestinationFile = Join-Path $DocsDir $Day8Files[$SourceFile]
    if (-not (Test-Path -LiteralPath $DestinationFile)) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $Pack 'docs') $SourceFile) -Destination $DestinationFile
    } else {
        Write-Host "Keeping existing file: $DestinationFile"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $DocsDir 'day8-results.md'))) {
    Copy-Item -LiteralPath (Join-Path $Pack 'docs\DAY-8-RESULTS-TEMPLATE.md') -Destination (Join-Path $DocsDir 'day8-results.md')
}
if (-not (Test-Path -LiteralPath (Join-Path $DocsDir 'day7-results.md'))) {
    Copy-Item -LiteralPath (Join-Path $Pack 'docs\DAY-7-RECONCILED-RESULTS.md') -Destination (Join-Path $DocsDir 'day7-results.md')
}
$StartupDestination = Join-Path $ScriptsDir 'Initialize-LabContext.ps1'
if (-not (Test-Path -LiteralPath $StartupDestination)) {
    Copy-Item -LiteralPath (Join-Path $Pack 'scripts\Initialize-LabContext.ps1') -Destination $StartupDestination
} else {
    Write-Host 'Existing startup helper retained; compare it with this pack before reusing it.'
}
git diff -- infra/terraform
git status --short
~~~

Edit the repository's day8-access-model.md with your decisions and day8-results.md with actual observations. The .tf diff should be empty for this lesson.

Use three explicit labels:

- **Observed:** returned by a successful read, with date/scope and local evidence.
- **Proposed:** desired future design, not implemented.
- **Unavailable/unknown:** blocked or insufficient evidence; not the same as “no access.”

If the current RG contains no lab network, record that accurately. Do not report today's 22-resource deployment or a clean Terraform plan: neither was required nor run by this lesson.

## 12. Review, commit and push

~~~powershell
git add -- docs/day7-results.md docs/day8-runbook.md docs/day8-identity-access-notes.md docs/day8-access-model.md docs/day8-diagram-changes.md docs/day8-architecture.png docs/day8-results.md scripts/Initialize-LabContext.ps1
git diff --cached --stat
git diff --cached -- docs/day7-results.md docs/day8-runbook.md docs/day8-identity-access-notes.md docs/day8-access-model.md docs/day8-diagram-changes.md docs/day8-results.md scripts/Initialize-LabContext.ps1
~~~

Review for accidental credential/identity/evidence inclusion and for proposed roles described as if already deployed. Stage only the intended files. If you already have a customized helper at that path, ensure any changes belong in this commit.

~~~powershell
git commit -m "docs: design scoped identity and access for the lab"
if ($LASTEXITCODE -ne 0) { throw 'Commit failed or there are no new changes; inspect Git status.' }
git push -u origin feat/day8-identity-access
if ($LASTEXITCODE -ne 0) { throw 'Push failed; local work remains. Record push as pending.' }
git status --short --branch
git log -2 --oneline
~~~

Report the returned commit and push outcome in your outbrief. This commit can include Day 7's missing written closeout alongside Day 8 design; it does not invent an earlier Day 7 commit or merge into main.

End the Whizlabs session through its normal controls when finished. No cloud resources or grants were created by the prescribed Day 8 steps, so there is no Day 8-created object to remove.

## Completion checklist

- [ ] Current login/RG verified, or live inspection explicitly unavailable.
- [ ] Visible assignment inventory and its limitations recorded.
- [ ] Four roles compared from live definitions and/or official documentation.
- [ ] Access model reviewed with a job/role/scope rationale for each persona.
- [ ] Existing student access kept separate from proposed enterprise groups/workloads.
- [ ] Day 9 isolated-test prerequisites marked ready, unavailable or unknown.
- [ ] Day 7 closeout and Day 8 design/results reviewed and committed; push outcome recorded.
- [ ] No claim that identities were created, roles granted, or permission tests executed today.

Use DAY-8-HANDOFF.md when asking another chat about one step. Bring back the completed results so Day 9 can follow the actual sandbox permissions.
