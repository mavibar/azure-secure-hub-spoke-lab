# Days 48–49 — Prove private storage access

**November 24, 2026 · Personal Azure · PowerShell 7 · 60-minute practical lab · About 140 minutes altogether**

**Security question:** Can a private workload read a dummy blob while an external caller with a container data-reader assignment is blocked by the public network boundary?

Day 48 covers the private endpoint and DNS. Day 49 tests public-access prevention. They share one temporary environment and one cleanup. The assistant prepares and tests the infrastructure; you inspect the design, predict results, run the evidence test and write the security decision. No new pipeline or OIDC setup is required.

## Today's rhythm

- 30 minutes: focused prelesson below.
- 10 minutes: break and open the prepared lesson.
- 60 minutes: practical work, **including cleanup**.
- 15 minutes: eight original certification-style questions.
- 15 minutes: review explanations, concentrating on missed concepts.
- 10 minutes: write the final ticket conclusion. Total: 140 minutes.

Stop new testing at practical minute 45. A broken helper gets five minutes of triage, then returns to the assistant. Do not turn setup troubleshooting into an extra workday. Lesson numbers track objectives, not overdue calendar dates.

## Prelesson — 30 minutes

**Minutes 0–17 — two specific Microsoft Learn units.** Read [Define Private Link Service and private endpoint](https://learn.microsoft.com/en-us/training/modules/design-implement-private-access-to-azure-services/3-define-private-link-service-private-endpoint), then [Integrate private endpoint with Domain Name Service](https://learn.microsoft.com/en-us/training/modules/design-implement-private-access-to-azure-services/4-integrate-private-link-dns). Read these units only; do not deploy their example environment. Focus on endpoint versus service endpoint, and the role of the private DNS zone and VNet link.

**Minutes 17–27 — the briefing.**

Imagine an application stores internal reports in Blob Storage. Its managed identity has permission to read reports. That answers **who may read**, but it does not establish **which network path may reach the data**. A security review must assess both.

A **private endpoint** provides a private IP in a subnet for access to a specific service resource and subresource. Today that subresource is `blob`. It does not move the storage account into your VNet, and one Blob endpoint does not automatically cover Files, Queues, Tables or every storage account. A service endpoint instead identifies an authorized subnet to a service's public endpoint; it is not a private IP for that service. [Storage private endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)

The application continues using `ACCOUNT.blob.core.windows.net`. Inside our linked VNet, DNS resolves that name through the private-link name to the private endpoint's A record. Outside the VNet, the same application name can resolve publicly. The private zone is `privatelink.blob.core.windows.net`; its VNet link makes that zone available to our VM. The endpoint's DNS zone group manages the service's record. Registration is disabled on the VNet link because we are resolving an endpoint record, not automatically registering VM hostnames. [Private endpoint DNS](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)

Creating a private endpoint does **not** automatically turn off public network access. Our separate storage setting is `publicNetworkAccess=Disabled`. That distinction is the connection to your policy lesson: deployment intent and observed behavior need separate evidence. An approved endpoint alone is insufficient proof of public-access prevention. [Public network access setting](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-set-default-access)

A private IP is also not a permission grant. The VM uses its system-assigned managed identity to request a Storage access token. Its **Storage Blob Data Contributor** assignment is limited to this lesson's single container. Contributor is used because preparation writes one dummy blob; a production read-only consumer should instead be evaluated for **Storage Blob Data Reader**. Your existing signed-in user receives a temporary **Storage Blob Data Reader** assignment on that same dummy container for the external test. No new user is created. Both assignments are removed with the fixture. These are two identities; we verify their intended scopes and do not claim a same-identity comparison. [Blob roles and scopes](https://learn.microsoft.com/en-us/azure/storage/blobs/assign-azure-role-data-access)

The private request runs inside the VM. The external request runs on your host, outside the lesson VNet, using its existing Azure sign-in. Both use the same dummy blob and normal HTTPS hostname with certificate validation. During preparation, forcing a public destination from the associated VNet still returned 200, so that approach was rejected as an outside-access test. Microsoft documents that traffic from a VNet associated with a private endpoint remains allowed. The original result is retained privately; no firewall setting was relaxed. [Storage endpoint behavior](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)

There are four distinct evidence layers: configuration says what should happen; DNS shows where a name resolves; the authenticated request shows an operation's result; the security conclusion states what that evidence establishes. A DNS result alone proves no data access. A generic 403 alone proves no particular cause. A private 200 plus an external 403 with `AuthorizationFailure`, verified data-role assignments and disabled public access supports this bounded test. The external role assignment is read back, but we do not separately prove its effective data permission through a private route; retain that limit in the conclusion.

For RMF-style documentation, connect the scoped network restriction to boundary protection, the container role to least privilege, and the saved inventory to configuration evidence. These are useful inputs to assessment; this small lab is not an ATO or proof of comprehensive control compliance.

**Minutes 27–30 — predict before running anything.** Write your expected DNS result for your host and the VM. Predict the private and public HTTP outcomes. Then answer: would adding Owner to the VM identity be a sensible fix for failed private DNS? Explain why.

## Prepared environment and cost boundary

One fresh resource group contains a small Ubuntu VM, two-subnet VNet, inbound-deny NSG, outbound public IP, StorageV2 account, private container, Blob private endpoint, private DNS zone/link, two container-scoped role assignments and VM auto-shutdown. Terraform manages **17 resource addresses**; Azure also creates supporting objects such as the VM disk and endpoint NIC.

The VM has no permitted inbound SSH/RDP. Run Command uses the Azure VM agent. Its public IP supplies explicit outbound connectivity, for the VM agent; outbound access is not otherwise tightly filtered. This is a disposable test fixture, not the final enterprise egress design. Private-endpoint subnet network policies are disabled; do not attribute storage blocking to the VM's inbound NSG.

Use **your personal Azure subscription**, not Whizlabs. Preparation read approximately **$0.42 USD month-to-date** and the existing **$20 monthly budget**. Billing is delayed; this is a point-in-time reading, not a spending guarantee. Reserve **$1 for this session**, with full deletion today. The selected Linux VM's checked retail compute price is about $0.04/hour; endpoint, IP, disk, DNS and storage add smaller charges for this short exercise. The monthly ceiling remains $20. Budget alerts notify; they do not stop resources. [VM pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/), [Private Link pricing](https://azure.microsoft.com/en-us/pricing/details/private-link/), [Budget behavior](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets)

The private start card records the actual shutdown time. Auto-shutdown is a backup for compute cost; it does not delete disks, public IPs or endpoints. If you postpone the lesson, clean up now and ask for fresh preparation when ready. Do not leave the environment running for a future study day.

Source belongs in the existing GitHub repository on `feat/day46-49-governance-private-link`, under `lessons/day48-49`. Terraform state, saved plans, runtime IDs, role principal, raw output and evidence remain under your local AppData case folder, outside Git. Historical hub/spoke state is untouched. The public lesson's source push is not an Azure deployment: no new deployment workflow is added.

**Live preparation passed on November 24:** private DNS and HTTP 200 read; authenticated external-host HTTP 403 AuthorizationFailure; both exact data-role assignments; disabled public access; enabled auto-shutdown; 17-delete cleanup preview. Final teardown is due in Lab 6. These are preparation results, not your completed learner review.

**Navigation accuracy:** resource settings are checked through Azure APIs; the menu paths below follow current Microsoft documentation and known Portal structure, not a fresh visual inspection of every blade. The private card gives direct resource links. If a menu differs, expand the resource's left menu, use its menu search for the named item, and stop searching after two minutes. Never hunt through Help to find configuration.

## Lab 1 — Open the prepared context | minutes 0–5

**HOST → WINDOWS TERMINAL → tab dropdown → PowerShell 7.** Keep this window open throughout the lab. Paste:

```powershell
$caseFolder=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day48-49-20261124'
$pack=Join-Path $caseFolder 'lesson'
. "$pack/scripts/Connect-Lesson.ps1" -CaseFolder $caseFolder
Invoke-Item -LiteralPath "$caseFolder/START-HERE.html"
```

The leading dot loads the context checker into this session. `$c` contains the saved subscription and fixture names. `Invoke-LessonAz` checks the Azure CLI exit code; it adds no hidden subscription argument. `Invoke-Item` opens the private start card in your default browser.

**Success evidence:** verified personal account and ownership message; start card says live preparation checks passed. Check its shutdown time before continuing. **Stop:** missing group, wrong subscription, stale preparation, or an already-deallocated VM. Return to the assistant; do not recreate resources or generate new identifiers. **Recovery:** retain the case and state. If postponing, use Lab 6 cleanup.

## Lab 2 — Inspect the network boundary | minutes 5–15

**STAY IN BROWSER → private start card → Storage link.** Full path: Azure Portal top search → type **Storage accounts** → select the service → use list search for the exact account on the card → click its name → resource left menu → expand **Security + networking** → **Networking** → inspect **Public network access**. Expected: **Disabled**. If the summary only offers **Manage**, click Manage to inspect the setting, then **Cancel** or close the panel without saving. Do not select Enable. This is the documented [Networking path](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-set-default-access).

**STAY IN BROWSER → start card → Private endpoint link.** Full path: top search → **Private endpoints** → exact **pe-lesson-blob** in the saved group → **Overview**. Inspect connection status **Approved**, storage target and subresource **blob**. In its resource menu expand **Settings → DNS configuration**. Match the private IP to the card and look for the storage hostname. Do not reject, disconnect or delete the connection.

**STAY IN BROWSER → start card → Private DNS link.** Full path: top search → **Private DNS zones** → `privatelink.blob.core.windows.net` in the saved group → expand **DNS Management → Recordsets** → click the A record named for today's storage account. Expected: saved private IP. Close the record panel → same **DNS Management** section → **Virtual network links** → click **link-lesson-vnet**. Expected: today's VNet; auto-registration disabled. Some Portal layouts place the record table directly in Overview; use the resource-menu search for `Recordsets` if needed. Do not edit the record or link.

**Question:** Which object supplies the private address, which supplies name resolution, and which blocks the public endpoint? Write three separate answers. **Evidence:** record Approved/blob, A-record match, VNet-link match and disabled public access in your notes. **Stop:** wrong target, wrong group, public access enabled or mismatched private IP. **Recovery:** preserve settings; request correction or cleanup without weakening the boundary.

**NEXT: switch to VS Code for the short source review.**

## Lab 3 — Review the deployed intent | minutes 15–23

**VS CODE → File → Open Folder → paste the lesson source folder from the private start card → Select Folder.** This opens the prepared repository worktree. Ctrl+P → `lessons/day48-49/terraform/main.tf` → Enter. Ctrl+F, one at a time:

- `public_network_access_enabled`: false, independently of the private endpoint.
- `subresource_names`: blob only.
- `private_dns_zone_id`: links the DNS zone to the VNet.
- `role_definition_name`: data role; inspect the preceding `scope` for the single container.
- `DenyAllInbound`: applies to the tester NIC, not the storage service.

You are reading Terraform, not applying it. A `resource` block declares desired infrastructure. References such as `azurerm_storage_container.lesson.id` derive the real scope after creation. Variables supply per-session identifiers without hardcoding yesterday's account or state. Preparation first created 16 resources, then added only the external reader assignment through a reviewed one-create plan. The final source declares 17 resources. No older resources were changed.

**NOW BROWSER → GitHub repository → Code tab → branch dropdown → `feat/day46-49-governance-private-link` → lessons → day48-49 → terraform → main.tf.** This is the source record. Use the latest commit link to see the change description; do not open Actions expecting a deployment run for this lesson. The assistant applied the isolated Terraform plan locally using Azure CLI authentication.

**Question:** A developer suggests replacing the container role scope with the subscription “to avoid permission issues.” Accept or reject, and why? **Evidence:** source branch/commit from the card and your scope decision. **Stop:** source and card revision disagree. **Recovery:** resolve the revision before active tests; do not apply from another folder.

**NEXT: return to the same PowerShell window.**

## Lab 4 — Compare DNS and authenticated traffic | minutes 23–35

**POWERSHELL — first inspect the service's current configuration.**

```powershell
$storage=Invoke-LessonAz storage account show --name $c.Storage --resource-group $c.RG --subscription $c.Subscription -o json | ConvertFrom-Json -DateKind String
[pscustomobject]@{
  PublicNetworkAccess=$storage.publicNetworkAccess
  SharedKeyAllowed=$storage.allowSharedKeyAccess
  AnonymousBlobAllowed=$storage.allowBlobPublicAccess
  DefaultAction=$storage.networkRuleSet.defaultAction
} | Format-List
Resolve-DnsName "$($c.Storage).blob.core.windows.net" -Type A -DnsOnly |
  Select-Object Name,Type,IPAddress,NameHost
```

`show` reads a resource. `--resource-group` and `--subscription` select the exact scope. `-o json` requests structured output; `ConvertFrom-Json` turns it into PowerShell properties. `Resolve-DnsName -Type A` requests IPv4 resolution; `-DnsOnly` avoids other Windows name-resolution methods. Your host is outside this lesson VNet, so a public address is expected. Disabled public access does not mean public DNS must disappear.

**Then run the prepared traffic test once:**

```powershell
& "$pack/scripts/Test-PrivateAccess.ps1" -CaseFolder $caseFolder
```

The ampersand runs the script. It asks Azure Run Command to execute the private DNS/read probe inside the VM, then verifies your existing user and its exact container reader assignment before issuing an authenticated external read from the host. Each origin obtains its own token; tokens stay in memory, are not transferred between machines, and are never printed. Blob content is not displayed. Both connections retain hostname/TLS validation. The learner command does not write the blob; `-Seed` is reserved for assistant preparation.

Expected results: `private_vm.dns` contains the saved private IP; `private_vm.private.status=200`; `external_host.status=403`; `external_host.error_code=AuthorizationFailure`; `external_host.reader_assignment_verified=true`; `same_identity=false`; top-level `pass=true`. Run Command completing successfully alone is insufficient—both request results must match.

**Evidence:** `latest-test.xml` plus timestamped private probe results; note the two request IDs and statuses locally. **Stop:** timeout, private 403, wrong DNS or unexpected public success. Do not change firewall rules, grant Owner, add your home IP or disable TLS checks. **Recovery:** keep the exact case and return the failure to the assistant; finish with cleanup rather than repeated requests.

**NEXT: remain in PowerShell to read the same result, then write the review.**

## Lab 5 — Investigate and decide | minutes 35–45

```powershell
$result=Import-Clixml -LiteralPath "$caseFolder/latest-test.xml"
$result | ConvertTo-Json -Depth 10
```

`Import-Clixml` reloads the saved PowerShell evidence; `-Depth 10` keeps the nested result fields visible. This is a read of evidence, not another cloud test.

**Your review ticket:** “The application team claims that creating a private endpoint alone makes storage private. They also ask for subscription Owner on the VM identity if a future request fails.” Use your observed results and source to approve or reject those two claims. Explain the separate roles of DNS, public network access and data authorization.

**One short diagnostic scenario — hypothetical, not a defect secretly injected into your lab:** tomorrow the same VM resolves the storage name publicly and its request fails. The endpoint remains Approved and its private IP has not changed. Choose the first investigation: role assignment, private DNS VNet link/resolver path, or VM password. State the evidence that would support your choice. Do not delete the live DNS link to reproduce this scenario.

Write five lines: requirement; inspected configuration; observed traffic; scope/limitations; recommendation. Include that only this VM private read and this external host/user request were tested. They use different identities, and an assigned role is not independently demonstrated effective permission through a private route. On-premises DNS, other storage subresources, exfiltration controls and organization-wide compliance remain outside this demonstration.

**Success:** your conclusion is supported by both configuration and a positive/negative request pair. **Stop:** minute 45, even if the explanation needs more study. **Recovery:** preserve partial results and proceed to cleanup. Explanations can continue after resources are gone.

## Lab 6 — Verified cleanup | minutes 45–60

**SAME POWERSHELL WINDOW.** This removes today's fixture only. It reads ownership and inventory, builds a destroy plan against today's private state, checks its scope and asks for the exact group name before applying it.

```powershell
$c.RG
& "$pack/scripts/Remove-Lesson.ps1" -CaseFolder $caseFolder
```

Copy the displayed group name into the confirmation prompt. Expected: **CLEANUP VERIFIED**, the group absent and Terraform state empty. The script retains private evidence and source. Both container role assignments are deleted as part of the same teardown. VM, disk, IP, endpoint and DNS objects are not intentionally retained.

**BROWSER confirmation:** private card → Resource group link → Refresh. Expected: resource no longer found. Or top search → **Resource groups** → search the exact group → **Refresh** → no matching group. A stale browser tab is not a failed delete; use the CLI readback:

```powershell
az group exists --name $c.RG --subscription $c.Subscription -o tsv
if($LASTEXITCODE -ne 0){throw 'Cleanup verification query failed.'}
```

Expected `false`. **Stop:** destroy error, unexpected inventory, remaining group or nonempty state. **Recovery:** preserve the private folder and ask the assistant for exact cleanup recovery. To stop compute charges while recovery is pending, use only this saved VM:

```powershell
az vm deallocate --resource-group $c.RG --name $c.VM --subscription $c.Subscription --output none
if($LASTEXITCODE -ne 0){throw 'Deallocation failed or the VM may already be absent; request readback.'}
```

Deallocation is not full cleanup. Do not delete state, clear locks, remove a whole subscription, or recreate anything. If you hand cleanup to this work chat, say “clean up the recorded Days 48–49 fixture”; the assistant can perform it and report verification.

## Quiz — 15 minutes, closed notes

These are original practice questions, not copied exam items. Choose the best answer unless the question says otherwise.

**1.** A private endpoint is Approved. A client outside the VNet still successfully reads a blob using valid credentials. What is the first missing design control to investigate?

- A. Turn off private DNS auto-registration.
- B. The storage account's public network access/firewall configuration.
- C. Add another private endpoint with the same subresource.
- D. Give the client Reader at subscription scope.

**2.** Your VM resolves the usual storage name to the private IP, but an authenticated read returns 403. Which conclusion is justified?

- A. DNS is wrong because private addresses cannot return HTTP responses.
- B. The storage data role is definitely missing.
- C. Name resolution succeeded; inspect the specific error and authorization before choosing a cause.
- D. Disable public access again to repair the role assignment.

**3.** You must evaluate whether an external client is blocked while private access works. Which evidence set is strongest?

- A. Compare an anonymous request on your laptop with an administrator's Portal view.
- B. Ping the private IP and record a timeout.
- C. Observe a private read, verify the external caller's exact data-role assignment, and capture its public request result with configuration readback; document that the identities differ.
- D. Take a screenshot of the endpoint's Approved status.

**4. Choose TWO.** Which statements correctly describe today's DNS configuration?

- A. Applications should replace their normal hostname with the private IP in production connection strings.
- B. The VNet link makes the private zone available to the VNet's Azure-provided DNS resolution.
- C. A private A record grants Blob Data Reader to the VM.
- D. A DNS zone group associates the endpoint with the private DNS zone and manages its service record.

**5.** The requirement changes to allow Azure Files as well as Blob over private connectivity. What must the reviewer evaluate?

- A. Whether the Blob endpoint's role is Owner.
- B. A File service private endpoint and the corresponding DNS and service authorization design.
- C. Enabling public blob containers.
- D. Nothing; an account-level endpoint automatically covers every storage service.

**6.** The workload only needs to read an existing container. Which role/scope is the best starting proposal?

- A. Owner at subscription scope.
- B. Contributor at the storage account.
- C. Storage Blob Data Reader at the required container, with the network path separately permitted.
- D. No role, because a private endpoint replaces authentication.

**7.** The host still resolves the account publicly after public network access is disabled. The VM privately reads with 200 and the external host's authenticated request gets the expected 403. Which assessment is best?

- A. Failure: public DNS must cease to exist.
- B. Evidence supports private allow/public deny for the tested workload; public DNS resolution alone is not an access bypass.
- C. All access from every identity and network has been proven safe.
- D. The VM NSG's inbound rule is necessarily the cause of the storage 403.

**8.** Auto-shutdown ran, the VM is deallocated, and the monthly budget alert has not fired. Which closeout is appropriate?

- A. All charges have stopped and cleanup is complete.
- B. Delete today's recorded fixture and verify absence; noncompute resources can still bill, and budget alerts are not a hard spending cap.
- C. Delete only the local Terraform state.
- D. Remove the $20 budget to avoid notification delays.

## Answer review — 15 minutes

1. **B.** Endpoint creation and public-access restriction are separate. The valid external read means the public path needs review; DNS registration is unrelated to that permission.
2. **C.** Resolution is one layer. A specific 403 may involve data permissions, token context or another service restriction. Do not infer the cause from the status alone.
3. **C.** Configuration, verified assignment scope and observed request outcomes support a bounded conclusion. Different identities and untested effective external-role permission remain explicit limitations.
4. **B and D.** The VNet link controls zone availability; the zone group manages the endpoint's record. DNS neither grants data rights nor requires IP-based connection strings.
5. **B.** Endpoints target subresources. Files has its own connectivity, DNS and authorization requirements.
6. **C.** Read-only data permission at the smallest required scope. Management-plane Contributor is not the intended substitute for a Blob data role.
7. **B.** DNS can still return a public address that the service refuses to serve for this request. Do not generalize one test to every access path.
8. **B.** Verify teardown of all temporary resources. Budget delivery and billing lag are not shutdown controls.

If you miss two or more, spend the review block on those concepts instead of adding another lab. For Alan Rodrigues AZ-305, pin the lecture topic **private endpoints, service endpoints and name resolution**; match the title in your course edition rather than assuming a lecture number. It can replace part of today's review or be tomorrow's optional study.

## Compact results — final 10 minutes

Copy this into OneNote. Keep runtime names/IDs and request IDs in private notes only. A sanitized summary can be committed later; no `git add .` from an evidence folder.

- Execution date / duration:
- Day 48: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION.
- Day 48 evidence: exact Blob target/Approved; private A-record and VNet-link match; VM private resolution observed:
- Day 49: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION.
- Day 49 evidence: public access Disabled; VM private 200/host public 403; different identities and verified assignment scope; expected error code; UTC/request IDs recorded privately:
- Security decision and one limitation:
- Quiz score / concept to revisit:
- Cleanup: VERIFIED / INCOMPLETE; exact group absence and empty state:
- Cost: preparation snapshot about $0.42 month-to-date; today's final charge pending delayed billing. Budget $20/month unchanged.

**COMPLETE** means the day's required observed evidence exists. **PARTIAL** means some objectives remain unproven. **BLOCKED** means a prerequisite prevented the test. **FAILED EXPECTATION** means an executed test contradicted the expected behavior. Assistant preparation success does not automatically complete your learner review. Cleanup status is recorded independently.

Earlier monitoring/telemetry gaps and delayed subscription billing reviews remain separate carry-forward work. Today adds no logging connector, Sentinel rule or paid Defender plan. You do not need to repeat old cost or monitoring exercises to complete this lesson.
