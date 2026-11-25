# Day 50 — Governance evidence and security closeout

**November 25, 2026 · Personal Azure · PowerShell 7 · 60-minute practical lab · About 140 minutes altogether**

**Day 50 should stand alone.** The current curriculum lists governance closeout after Days 46–49. Today you turn the tagging, location and private-access experiments into a defensible security review. Combining another deployment topic would crowd out the investigation and explanation you wanted to practice.

**Your assignment:** Decide whether the narrowly scoped governance lab can be closed, correct an inaccurate assessment draft, and identify what the evidence does not establish. The assistant has prepared the evidence and tested both inventory queries. Your job is the review and decision.

## Today's rhythm

- 30 minutes: targeted Microsoft Learn and the briefing below.
- 10 minutes: break and open the prepared materials.
- 60 minutes: guided practical review, including closeout.
- 15 minutes: eight original certification-style questions.
- 15 minutes: explanations and targeted revision.
- 10 minutes: final learning note. Total: 140 minutes.

The practical timer starts at Lab 1. At minute50, stop adding investigations and finish the decision. A setup failure gets five minutes, then returns to the assistant. Do not recreate yesterday's resources to make a screenshot possible.

## Prelesson — 30 minutes

**Minutes 0–8: two AZ-305 units.** Read [Design for governance](https://learn.microsoft.com/en-us/training/modules/design-governance/2-design-for-governance) and [Design for role-based access control](https://learn.microsoft.com/en-us/training/modules/design-governance/8-design-for-role-based-access-control). Focus on organizational requirements, responsibility and assignment scope. Skip the rest of the module today.

**Minutes 8–20: read this briefing and explain each example aloud.**

A security reviewer does more than confirm that a command succeeded. Start with a requirement, identify its implementation and scope, then ask what observed evidence supports your conclusion. “The cloud is secure” cannot be tested as one claim. “The specified NSG creation in the disallowed region was rejected by this exact policy assignment” can.

Use four evidence layers. **Intent** is the Terraform definition or approved design. **Configuration** is the setting or assignment read back from Azure. **Behavior** is the actual operation and result. **Assessment** is your bounded judgment about that evidence. Source code alone does not prove deployment; a successful apply does not establish every security outcome.

You already have a good example: Audit allowed a missing Owner tag to exist, then you restored the tag manually. Later compliance results can confirm the resource satisfied the assigned rule. They do not change Audit into an automatic repair mechanism. The Deny experiment has a different claim: a specific request was rejected with `RequestDisallowedByPolicy` naming the expected assignment. The distinction changes what you can recommend for an enterprise requirement.

**Time matters.** A saved Policy export can include several evaluations of the same resource under the same assignment. Count the latest record for each assignment/resource pair when describing the latest saved assessment. Keep its evaluation timestamp. The result remains a historical observation after the resource is deleted; it is not today's live compliance state. Policy evaluations are asynchronous, so a corrected configuration and a displayed compliance result can reflect different times. [Policy evaluation and compliance data](https://learn.microsoft.com/en-us/azure/governance/policy/how-to/get-compliance-data)

**Scope matters just as much.** Both training policies were assigned to one disposable group and selected NSGs. The private endpoint targeted Blob Storage, not every storage service. The VM and external user had different container-scoped data roles. Yesterday's private200/external403 result supports the observed requests, but it is not a same-identity experiment. The external role assignment was verified; its effective permission was not independently exercised through a private route. Good reporting preserves that distinction rather than hiding it under a green PASS.

Today you will use KQL in **Azure Resource Graph Explorer**. Its `Resources` table describes resource inventory; `ResourceContainers` includes resource groups and subscriptions. This is a different query service from Log Analytics, where you previously used `AzureActivity` for collected events. Knowing the query language does not make the tables interchangeable. Resource Graph can lag changes and shows resources you are authorized to read. An empty query needs a scope and filter check before interpretation. [Resource Graph overview](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview)

For closeout, separate a **known failed requirement** from an **evidence limitation**. A proven unauthorized successful request is a finding. A network path you never tested is an unassessed area; it is not automatically a demonstrated vulnerability. Both can need follow-up, but their wording and priority differ. Give follow-up work a responsible role, a target date or next review point, and the evidence needed to close it.

Your recommendation is also separate from formal risk acceptance. An assessor describes results and limitations; an authorized decision-maker accepts risk under the organization's process. In RMF terms, implementation, assessment and authorization are distinct activities. A small lab report can practice the structure of assessment evidence without pretending to grant an ATO. [NIST SP800-37 Rev.2](https://csrc.nist.gov/pubs/sp/800/37/r2/final)

This is also a useful preparation for agentic security operations: an automated summary is a claim to verify. A convincing sentence should not receive more trust than its underlying scope, timestamps and observations justify. Today's deliberately flawed draft is a training scenario, not an actual agent's production output.

**Minutes 20–30: commit to three predictions.** Can a resource be corrected now while an older evaluation remains noncompliant in an export? Can an empty retired-group query coexist with seven other resources in the subscription? Can you close a bounded lab while recording untested enterprise scenarios? Write one sentence explaining each answer before looking at the quiz explanations.

## Prepared materials and boundaries

Use **your personal Azure subscription**, not Whizlabs. The private start card supplies its exact ID and the saved evidence locations. Day 50 performs Azure reads and writes only local evidence/notes. No new cloud infrastructure or role grants are needed. The existing monthly ceiling remains $20; the earlier billing and monitoring follow-ups stay separate from this lesson.

Preparation verified that both Days 46–47 and Days 48–49 groups are absent, their local Terraform states contain zero addresses, and both custom Day 46 policy definitions are absent. Yesterday's learner test was recorded November24 at16:07UTC, with private200 and external403 AuthorizationFailure. The Day 48 cleanup record is November24 at16:33UTC. You reported Days 48–49 completed; these observations corroborate the technical test and cleanup.

The source and sanitized closeout notes are on GitHub branch `feat/day50-governance-review`. Historical Terraform state is unchanged. Runtime IDs, raw JSON, state, detailed evidence and your draft review stay in your local AppData case folder. The private card is the starting point, not a public portfolio attachment.

**GUI accuracy:** the paths follow Microsoft documentation; today's current resource-menu layout was not visually re-inspected. Use the stated menu search or the exact-scope PowerShell fallback after two minutes. An empty screen for a retired resource is expected.

## Lab 1 — Open the review context | minutes 0–5

**HOST → Windows Terminal → tab dropdown → PowerShell 7.** Keep this window open.

```powershell
$caseFolder=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day50-20261125'
$pack=Join-Path $caseFolder 'lesson'
. "$pack/scripts/Connect-Review.ps1" -CaseFolder $caseFolder
Invoke-Item -LiteralPath "$caseFolder/START-HERE.html"
$review=Import-Clixml -LiteralPath "$caseFolder/latest-review.xml"
$review.Cleanup | Format-Table Case,GroupExists,StateAddressCount,Verified
```

The leading dot loads the small context checker into this session. `$d46` and `$d48` refer to the saved cases; `$review` is today's collected evidence. `Import-Clixml` reads saved PowerShell data. `Format-Table` changes its display, not Azure.

**Expected:** personal-context confirmation; both group-existence values False, both state counts0, both Verified values True. **Question:** why is a deleted group the expected starting condition today? **Evidence:** checked time on the private card. **Stop:** wrong context, missing evidence or a live retired group. **Recovery:** keep the case and request investigation; do not delete an unexpected resource or rerun a preparation script.

**NEXT: stay in this PowerShell window.**

## Lab 2 — Reconcile the Policy history | minutes 5–18

**Purpose:** distinguish older failures, correction evidence and the latest saved evaluation. First inspect the simple facts:

```powershell
[pscustomobject]@{
  BeforeHadOwner=$review.TagBeforeHasOwner
  AfterOwner=$review.TagAfterOwner
  AllowedProbe=$review.AllowedProbeState
  AllowedRegion=$review.AllowedProbeLocation
  ExactAllowedResource=$review.AllowedProbeExact
  ExactPolicyDenial=$review.ExactPolicyDenial
  SavedPolicyRows=$review.SavedPolicyRows
} | Format-List
```

Expected: Owner absent before and restored afterward; the exact eastus probe succeeded; the negative probe named the correct deny assignment;20 saved Policy rows. A large export is not20 different resources.

Now perform the selection yourself, using the original export:

```powershell
$states=Import-Clixml -LiteralPath "$($c.Day46)/student-policy-states.xml"
$scoped=$states | Where-Object {
  $_.policyAssignmentId -in @($d46.OwnerAssignment,$d46.LocationAssignment) -and
  $_.resourceId -in @($d46.ReferenceId,$d46.DriftId)
}
$latest=$scoped | Group-Object policyAssignmentId,resourceId | ForEach-Object {
  $_.Group | Sort-Object {[DateTimeOffset]$_.timestamp} -Descending | Select-Object -First 1
}
$latest | Select-Object policyAssignmentName,complianceState,timestamp,
  @{Name='Resource';Expression={($_.resourceId -split '/')[-1]}} | Format-Table -AutoSize
```

`Where-Object` filters records; `$_` means the current record. `-in` restricts this review to the exact saved assignments and two NSGs. `Group-Object` makes one group per assignment/resource pair. `Sort-Object -Descending` puts the newest timestamp first; `Select-Object -First 1` takes that record. The final display extracts the resource name from the end of its ID.

**Expected:** four rows, all Compliant, evaluated on November23 around16:39UTC. That resolves the earlier ambiguity in the mixed export. **Question:** rewrite “four noncompliant entries mean four current failures” into a statement supported by these results. Also state who repaired the tag: you or the Audit effect.

**Evidence:** record the four latest saved results and their timestamps as E01; the before/after and exact allow/deny tests as E02. **Stop:** missing rows or different assignment/resource scope. **Recovery:** mark the comparison PARTIAL and keep the original export; do not launch another Policy scan against deleted resources.

**NEXT: switch to your browser for the live inventory exercise.**

## Lab 3 — Query current resources with KQL | minutes 18–30

**BROWSER → Azure Portal → top search box → type Resource Graph Explorer → select the Resource Graph Explorer service.** At the top, click the scope control, initially often **Directory** → locate your personal subscription → select only the exact subscription from the private card → confirm using the picker's **Apply** or **Select** button. If the names are duplicated, compare IDs; do not guess by display name. Then click inside **Query 1**, select its existing text, and paste the KQL below. Click **Run query** → **Results**. For errors, click **Messages**. This follows Microsoft's [Resource Graph Portal quickstart](https://learn.microsoft.com/en-us/azure/governance/resource-graph/first-query-portal).

**KQL — paste directly into Resource Graph Explorer. No PowerShell variables or substitutions.**

```kusto
Resources
| summarize ResourceCount=count() by subscriptionId, type
| order by type asc
```

`Resources` selects inventory. `summarize` groups it; `count()` counts each resource type. `order by` makes the display predictable. Check the returned subscription ID against the card. Preparation found seven resources across seven types. These are retained resources, not a list of cleanup failures; counts may change after preparation.

**STAY IN THE SAME QUERY EDITOR.** Replace the entire query with this second block, then **Run query → Results**:

```kusto
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions/resourcegroups'
| where name startswith 'rg-csl-policy-d46-' or name startswith 'rg-csl-private-d48-'
| project name, location, subscriptionId
| order by name asc
```

`=~` is case-insensitive equality. `where` filters; `project` chooses the displayed columns. The name prefixes select this lesson family's groups without runtime values in the query. Expected: zero rows. This is a prefix-based inventory check, not proof that a historical policy test passed or that the whole subscription is empty. The exact ARM group checks in Lab 1 are the stronger closeout readback for those two groups.

**If the scope picker or query UI blocks you for two minutes, switch to PowerShell and use this tested fallback.** It executes the same two saved queries with the exact subscription in the request body:

```powershell
& "$pack/scripts/Refresh-Review.ps1" -CaseFolder $caseFolder
$review=Import-Clixml -LiteralPath "$caseFolder/latest-review.xml"
$review.CurrentInventory | Format-Table subscriptionId,type,ResourceCount
'Retired lesson groups found: '+@($review.RetiredLessonGroups).Count
```

The helper uses `az rest` with Resource Graph's query API. Its HTTP POST submits a read-only query; it does not deploy or modify resources. Request files and results remain private. No CLI extension installation is required. [Resource Graph REST quickstart](https://learn.microsoft.com/en-us/azure/governance/resource-graph/first-query-rest-api)

**Question:** why can “seven resources remain” and “both training groups are gone” both be true? **Evidence:** note query scope, run time and counts as E03; keep any exported CSV private. **Stop:** unexpected subscription, truncated results, errors or a returned retired group. **Recovery:** preserve the result and ask for readback; do not delete the seven retained resources or broaden permissions. With a UI error, use the fallback and record the GUI exercise as PARTIAL rather than inventing success.

**NEXT: switch to VS Code for the scope review.**

## Lab 4 — Trace the claims back to source | minutes 30–40

**VS CODE → File → Open Folder → paste the repository worktree path on the private card → Select Folder.** Ctrl+P → `lessons/day46-47/terraform/main.tf` → Enter. Ctrl+F → `effect = "Audit"` → inspect the condition; then find `effect = "Deny"`; then `resource_group_id`. Confirm the type selector is NSGs and the assignments target the lesson group.

**STAY IN VS CODE.** Ctrl+P → `lessons/day48-49/terraform/main.tf` → Enter. Ctrl+F → `resource "azurerm_role_assignment" "dummy_writer"`; inspect `principal_id` and `scope`. Then search `external_reader` and compare. The VM's managed identity and your existing user are different principals. Both roles target the dummy container; neither is subscription Owner. The source records intent; yesterday's saved execution evidence records the actual results.

**NOW SWITCH TO POWERSHELL** to inspect the recorded network facts without issuing another storage request:

```powershell
[pscustomobject]@{
  RecordedUtc=$review.NetworkTestUtc
  PrivateHttp=$review.PrivateHttp
  ExternalHttp=$review.ExternalHttp
  ExternalCode=$review.ExternalCode
  SameIdentity=$review.SameIdentity
  ReaderAssignmentVerified=$review.ExternalReaderAssignmentVerified
  PublicNetworkAccess=$review.PublicNetworkAccess
} | Format-List
```

**Expected:** private200, external403 AuthorizationFailure, SameIdentity False, assignment verification True, public access Disabled. **Question:** what should replace “the same managed identity was allowed privately and denied publicly”? **Evidence:** source revision from the card plus these bounded facts as E04. **Stop:** source/evidence contradicts the stated scope. **Recovery:** record the discrepancy; preserve evidence and request review. No live identity, role or network edits belong in this phase.

**NEXT: switch to OneNote or open the prepared private decision file.**

## Lab 5 — Correct the assessment and decide | minutes 40–50

**Purpose:** practice the judgment that belongs to you as the security reviewer. This is a **deliberately flawed training draft**, not a description of a deployed enterprise:

“Azure Policy automatically repaired Owner. The export contains20 independent resources with four continuing violations. The location rule protects the whole subscription. The same managed identity passed the private request and failed the public request. Resource Graph shows no resources, so there are no further charges. Approve enterprise rollout and mark every related control fully satisfied.”

Annotate each sentence as **SUPPORTED / REWRITE / MORE EVIDENCE NEEDED**. Cite E01–E04 and the source where relevant. Do not replace an overclaim with a new one.

You can write in OneNote, or **PowerShell → run this command → switch to the Notepad window it opens**:

```powershell
notepad "$caseFolder/REVIEW-DECISION.txt"
```

Complete the prepared fields: requirement and boundary; evidence/time; corrections; remaining uncertainties; decision; follow-up owner and next review point. Recommended decision vocabulary: **CLOSE THE BOUNDED LAB**, **PARTIAL—SPECIFY MISSING EVIDENCE**, or **BLOCKED—SPECIFY PREREQUISITE**. Evaluate a request for enterprise rollout separately; this exercise is not sufficient evidence to authorize it.

At least one follow-up should name the evidence needed, not merely say “investigate more.” Example: “Before an enterprise storage rollout, the network/security owner must validate the required on-premises DNS and access path; retain DNS results and authenticated positive/negative requests for that approved scope.” This is a proposed future test, not work to execute today.

**Success:** six draft statements assessed, a bounded decision, and one actionable follow-up. **Stop:** minute50. **Recovery:** save an unfinished review as PARTIAL and keep its next step. Your next lesson does not require pretending every enterprise risk has been assessed.

## Lab 6 — Close the review and preserve evidence | minutes 50–60

**POWERSHELL — inspect cleanup evidence already collected today:**

```powershell
'Checked UTC: '+$review.CheckedUtc
$review.Cleanup | Format-Table Case,GroupExists,StateAddressCount,Verified
$review.DefinitionAbsence | Format-Table Name,Absent
git -C $c.SourceRepo status --short --branch
if($LASTEXITCODE -ne 0){throw 'Could not read repository status.'}
```

Expected: both groups absent, both states empty, both custom definitions absent. Git should show the Day 50 branch with no uncommitted lesson changes. If another program or chat changed a file, inspect it; do not reset or delete it. No new Day 50 cloud resources require teardown.

**BROWSER → GitHub repository → Code tab → branch dropdown → `feat/day50-governance-review` → lessons → day50 → README.md.** Review the sanitized technical closeout; it records preparation and prior-day evidence, not your still-unsubmitted Day 50 decision. Do not look for an Actions deployment run—none was created today.

Save your decision privately using **Notepad → File → Save**, or finish the OneNote page. Send its sanitized conclusion back to this work chat when done; I can reconcile it into the repository. Do not run `git add .` against your AppData evidence folder. Raw IDs, JSON, state, account details and private notes stay out of Git.

**Stop/recovery:** unexpected cleanup state is an operations item for exact recovery. An absent resource or retired Policy assignment is not a reason to recreate it. Existing cost/budget and monitoring carry-forwards remain open until their own evidence closes them; today's inventory is not a billing report.

## Quiz — 15 minutes, closed notes

These are original practice questions, not actual certification exam items. Select the best answer unless instructed otherwise.

**1.** A Policy export contains older noncompliant and newer compliant evaluations for the same resource and assignment. Which report is strongest?

- A. Count every row as a different current resource.
- B. Select the latest record per exact assignment/resource pair and report its timestamp and scope.
- C. Delete the older rows from the original evidence.
- D. Treat every historical failure as an open current finding.

**2.** Terraform declares public network access disabled. What additional evidence most directly establishes observed access behavior?

- A. The filename contains “secure.”
- B. A successful source commit.
- C. Configuration readback plus appropriately scoped authenticated request outcomes.
- D. The assigned Owner tag.

**3. Choose TWO.** Which conclusions follow from yesterday's records?

- A. The VM's private request returned200.
- B. The external request used the same managed identity.
- C. The external user had the recorded container reader assignment and its request returned403.
- D. Every possible storage access path has been verified.

**4.** Resource Graph returns no matching retired lesson groups. What should an assessor conclude?

- A. The entire subscription is empty and cannot bill further.
- B. No groups matching that query were visible at the selected scope/time; confirm exact retirement through direct readback and state evidence.
- C. The previous deny policy has been proven effective again.
- D. The deleted groups must be recreated for evidence.

**5.** A requirement says resources without the correct Owner tag must not be created. Your implemented effect is Audit. What is the best recommendation?

- A. Declare prevention satisfied because the resource is later noncompliant.
- B. Identify the effect/requirement mismatch and propose a scoped preventative policy design for review and testing.
- C. Give all developers Owner.
- D. Remove the requirement from the report.

**6.** The lab's planned tests and teardown are evidenced, but on-premises DNS was outside scope. Which closeout is most defensible?

- A. Claim enterprise connectivity and security are fully assessed.
- B. Close the bounded lab with the unassessed path and required future evidence recorded separately.
- C. Label the untested path a confirmed critical vulnerability.
- D. Leave every objective permanently incomplete.

**7.** An automated report recommends risk acceptance because its compliance percentage is100%. What belongs to the security review?

- A. Accept its recommendation without checking denominators or scope.
- B. Verify evidence coverage, timing and limitations; route any risk-acceptance decision to the authorized role.
- C. Change failing policy assignments to exclusions until the score rises.
- D. Treat the report as an ATO.

**8.** You paste `Resources | summarize count()` into the workspace's Log Analytics Logs editor and it fails. What is the first correction?

- A. Grant subscription Owner.
- B. Reinstall Terraform.
- C. Use Resource Graph Explorer for the inventory query; a common query language does not imply common tables.
- D. Enable a paid connector.

## Answers and explanation review — 15 minutes

1. **B.** Preserve the original export. Select the relevant scope and latest pairwise evaluation, retaining time; do not relabel a historical snapshot as current live compliance.
2. **C.** Intent, configuration and behavior answer different questions. A commit or successful plan is not a traffic result.
3. **A and C.** The origins and principals differed. The verified assignment is narrower evidence than an independently successful private read by the external user.
4. **B.** Query scope, permissions, filters and indexing affect visibility. Billing also has its own timeline.
5. **B.** Audit records a violation without implementing the requested prevention. A design correction needs its own scope review and validation.
6. **B.** Completion is assessed against the defined objective. Untested requirements remain explicit, neither silently approved nor falsely reported as proven vulnerabilities.
7. **B.** A percentage is relative to its evaluated population and rules. Assessment evidence informs a decision; it does not replace the responsible decision-maker.
8. **C.** Resource Graph inventory and Log Analytics event data are different services and tables.

For the six draft sentences: Owner was repaired manually;20 rows are evaluations rather than20 current resources; the latest four exact saved pairs were compliant; the location assignment targeted one lesson group and NSGs; the network tests used two identities; zero matching retired groups does not mean zero resources or zero charges; enterprise rollout is not justified by this bounded evidence. Explain these corrections in your own words rather than copying the answer key.

If you miss two or more questions, use the review block on those concepts. For Alan Rodrigues AZ-305, pin the section on **governance scope, Azure Policy versus RBAC and resource organization**. Use its title in your course edition; lecture numbering has not been verified. A short matching segment can replace part of the review time, rather than extend the day.

## Final learning note — 10 minutes

- Day 50 status: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION.
- Exact review boundary and execution date:
- One claim corrected using Policy scope/time:
- One claim corrected using network/identity evidence:
- Resource Graph scope/counts and interpretation:
- Lab closeout decision; enterprise approval assessed separately:
- Follow-up owner, next review point and required evidence:
- Cleanup readback and source revision recorded:
- Quiz score; one concept to revisit:

COMPLETE means you performed the review, corrected the claims, ran or inspected the scoped query evidence and saved a reasoned conclusion. PARTIAL names an unfinished objective. BLOCKED names a missing prerequisite. FAILED EXPECTATION records an executed check that contradicted the expected result. A carefully bounded conclusion can be complete while explicitly carrying forward an unassessed enterprise scenario.

Today finishes this governance block. No additional deployment is required to catch up. Resume the next original topic at your next chosen study session; keep the planned holiday break free.
