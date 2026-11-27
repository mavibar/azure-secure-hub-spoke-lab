# Day 51 — Prove an Azure restore

**Combined lesson: recovery design, Azure Backup operation, alternate-disk restore and evidence review. Prepared November 27, 2026. Personal Azure; not Whizlabs.**

You already passed AZ-104. Today is applied retrieval practice, not a repeat of the entire administrator syllabus. Your Commvault experience supplies the backup concepts; this lesson concentrates on Azure's identity, storage and recovery boundaries.

**Time:** 30-minute prelesson → 60-minute lab including closeout → 20-minute quiz/review → 20-minute matching AZ-305 lecture → 10-minute notes/break. About 140 minutes. Stop starting new operations at lab minute 45. Azure jobs can exceed this window; that produces PARTIAL progress, not a longer study day. Hand unresolved execution to the assistant.

**One question:** What evidence makes this particular restore trustworthy, and what would we still need before approving recovery for a real application?

## Before opening Azure

Open the private **START-HERE.html** card in `C:/Users/Mark/AppData/Local/CloudSecurityLab/day51-20261127`. It contains exact names, direct Azure resource links, preparation results and the shutdown time. The card's current result governs whether this is ready for live execution. Do not infer readiness from this runbook alone. If it says preparation incomplete, use the prelesson and ask the assistant to finish; do not repair its scripts yourself.

The source is tracked in the existing cloud-security repository on branch **feat/day51-azure-recovery**, under **lessons/day51**. Terraform created the dedicated infrastructure. Azure CLI/ARM operations execute backups and guest checks. Private Terraform state, recovery IDs and raw evidence stay outside Git. No historical hub/spoke state is used. Day 50 learner completion has not been reported and is not silently marked complete.

**Cost boundary:** $20/month maximum; reserve approximately $1 for this short session, not a guaranteed quote. Preparation checked month-to-date actual cost at about $0.69 before deployment; billing is delayed. VM auto-shutdown does not remove disks, snapshots or the public IP. Finish cleanup today. No paid connectors, Defender plan or extra Key Vault is added.

## Prelesson — 30 minutes

**Minutes 0–8: Which vault does what?** A Recovery Services vault is used for workloads such as Azure VM backup. A Backup vault supports newer data-protection workloads including Azure Disk Backup. Key Vault manages secrets, keys and certificates; it is not the place your disk backup is stored. Today uses a Backup vault and platform-managed disk encryption. Distinguish the services before discussing retention or access. Read the workload comparison in [Azure Backup overview](https://learn.microsoft.com/en-us/azure/backup/backup-overview), then explain those three roles aloud.

**Minutes 8–16: Where are the bytes?** The source is one small data disk attached to a temporary Linux VM. Azure Disk Backup creates incremental snapshots in a separate resource group. These are operational-tier backups inside your subscription; they are not a separate vaulted copy. The policy automates snapshot creation and retention. A completed disk backup does not establish coordinated database or multi-disk application consistency. Read the opening and limitations in [Azure Disk Backup overview](https://learn.microsoft.com/en-us/azure/backup/disk-backup-overview). Draw the flow in your notes: source disk → service-managed snapshot → new restored disk → read-only verification.

**Minutes 16–23: Who can recover it?** The Backup vault's system-assigned identity needs Disk Backup Reader on the source disk, Disk Snapshot Contributor on the snapshot group and Disk Restore Operator on the restore group. These are service permissions, distinct from your own administrator access. A managed identity removes the stored password; RBAC still defines its authority. The prepared roles use these exact scopes. Review permissions in [Configure disk backup](https://learn.microsoft.com/en-us/azure/backup/backup-managed-disks). Ask: which grant would I remove after a one-time restore? Answer: the restore-target grant, once recovery operations are complete; today's full cleanup removes all three.

**Minutes 23–30: What can break an otherwise good backup?** A recovery point can exist while the restore identity lacks access. A customer-managed encryption key can also become unavailable; a backup does not eliminate the need to preserve the required key and permissions. Today's disk uses platform-managed keys, so we discuss that dependency without adding another key-management experiment. Review CMK requirements in the [support matrix](https://learn.microsoft.com/en-us/azure/backup/disk-backup-support-matrix). Soft delete and immutability are different controls. Operational snapshots can still be deleted directly; do not describe today's lab as immutable ransomware protection. See [Backup security overview](https://learn.microsoft.com/en-us/azure/backup/security-overview).

**Prediction before the lab:** Write three sentences: where the recovery bytes live; which identity creates the restored disk; why matching a file hash still does not prove application recovery.

## Lab 1 — Open the prepared case and review access, minutes 0–10

**Purpose:** establish the exact boundary before changing anything.

**POWERSHELL 7:** open Windows Terminal → tab dropdown → your PowerShell 7 profile. Paste:

```powershell
$Case = "$env:LOCALAPPDATA/CloudSecurityLab/day51-20261127"
$Lesson = Join-Path $Case 'lesson'
$c = Import-Clixml (Join-Path $Case 'context.xml')
$env:AZURE_CONFIG_DIR = $c.CliConfig
& "$Lesson/Recovery-Lesson.ps1" -Action Review
```

`Join-Path` constructs a path; `Import-Clixml` reads our private saved context. `&` runs the named script; `-Action` selects one bounded operation. The helper verifies subscription, tenant and ownership tags, then checks each saved role assignment against the vault identity. It does not create replacement resources when something is missing.

**Expected:** protection configured, soft delete On, three role-principal matches. Record the state actually returned. A provisioning or unhealthy state is not ready.

**NOW SWITCH TO AZURE PORTAL.** Click the top search box → type **Resource groups** → click the Resource groups service → click the exact recovery group on the private card → **Overview** → click **disk-source-data** → left menu **Access control (IAM)** → top **Role assignments** tab → search/filter **Disk Backup Reader**. Inspect its assigned identity and scope. Repeat from Resource groups for the exact snapshot group (Disk Snapshot Contributor) and restore group (Disk Restore Operator). Do not click Add role assignment.

**UI accuracy:** paths follow current Microsoft documentation and known Portal navigation, but were not freshly screen-verified in this preparation. Menu search is the fallback: use the search box above the resource's left menu, type the named blade, click that result. The private card also links directly to each resource. Stop hunting after two minutes and use the tested readback. No implied click into an unrelated Help or Support blade.

**Question/evidence:** which scope permits disk creation, and why is subscription-wide Contributor unnecessary? Keep a private note of the three scopes, not a public screenshot with identifiers. **Stop:** identity/scope mismatch or missing fixture. **Recovery:** no writes yet; ask the assistant, do not grant broader access. **Next:** PowerShell.

## Lab 2 — Trigger and verify one backup, minutes 10–20

**Purpose:** distinguish a submitted request from a completed recovery point.

```powershell
& "$Lesson/Recovery-Lesson.ps1" -Action Backup
& "$Lesson/Recovery-Lesson.ps1" -Action Status
```

Run Backup **once**. The helper records the request time and preexisting recovery points before submitting. `Status` is safe to repeat; it reads jobs and recovery points and saves private evidence. Repeat Status manually after about one minute while reviewing the Portal. Do not rerun Backup after a timeout or invent another target name.

**PORTAL:** top search → **Backup vaults** service → exact **bv-disk-lesson** from the private card → left menu search **Backup jobs** → click **Backup jobs** → select today's Backup job → inspect **Status**, start/end times and protected item. Use the resource menu search because the placement can vary with the Resiliency rollout. Remain in this vault; search **Backup instances** → click it → set datasource type **Azure Disks** if needed → click the source disk instance → inspect its recovery points. The helper's private instance/recovery-point records disambiguate similar display names.

**Success:** the matching Backup job is Completed and a new recovery point exists for this source. A 202/accepted response or a green deployment is insufficient. **Question:** what proves data protection rather than merely configured protection? Save job status and recovery-point time. **Stop:** Failed, unknown state, ambiguous recovery point or still pending at minute 20. Use the remaining time to review prepared evidence; assistant handles completion/cleanup. **Recovery:** preserve intent and snapshots; no duplicate write. **Next:** PowerShell only after success.

## Lab 3 — Change the dummy file and request an alternate-disk restore, minutes 20–30

**Purpose:** make the restore prove an earlier version was recovered.

```powershell
& "$Lesson/Recovery-Lesson.ps1" -Action Change
& "$Lesson/Recovery-Lesson.ps1" -Action Restore
& "$Lesson/Recovery-Lesson.ps1" -Action Status
```

Change overwrites only the harmless `payload.txt` in the recorded source data disk. It reports the original and changed SHA-256 hashes. Restore uses the saved recovery point, the separate restore group and fixed name **disk-restored-data**, with **FailIfExists**. It preserves the source disk. The helper refuses a second uncertain request or an already-existing target. This implements alternate-location recovery, not an overwrite of the source. [Microsoft's restore procedure](https://learn.microsoft.com/en-us/azure/backup/restore-managed-disks).

**PORTAL familiarization, read-only:** from the same vault's **Backup instances** → selected disk instance → **Restore**. Inspect the tabs **Basics**, **Restore point**, **Restore parameters**, **Review + restore** as available. Select the recovery point only if needed to view parameters. Recognize target subscription, target group and restored disk name. **Close/cancel this wizard without submitting**: PowerShell already sent the request. Return to **Backup jobs**, open the Restore job and inspect status. Do not use a Grant Permissions shortcut; permissions were prepared narrowly.

**Success:** changed-file hash differs; matching Restore job Completed. **Question:** why is restoring to a new disk safer than altering production immediately? **Evidence:** exact target and job recorded privately. **Stop:** any role error, existing-name collision or incomplete job at minute 35. **Recovery:** keep the same recorded operation; do not retry under a new identity or broaden access. **Next:** PowerShell after completion.

## Lab 4 — Prove the restored bytes and make a security decision, minutes 30–45

```powershell
& "$Lesson/Recovery-Lesson.ps1" -Action Verify
```

The helper checks the source's exact Azure disk ID at LUN 0, attaches only the recorded restored disk at LUN 1, mounts that restored filesystem **read-only**, compares its file hash with the original known harmless content, and unmounts it. `ro,noload` prevents writes and journal replay on the restored ext4 filesystem. The source file must still show the changed version. These Linux mount flags are supporting mechanics, not a new Linux administration curriculum.

**Success:** `CSL_verify_PASS`, original/restored hash match and source/restore hash difference. A completed restore job without this read test is weaker evidence. If verification fails, stop; do not format, repair or write to the restored disk.

**NOW SWITCH TO VS CODE:** File → Open Folder → `C:/git/azure-secure-hub-spoke-lab-d51` → Select Folder. Press Ctrl+P → enter `lessons/day51/terraform/main.tf` → Enter. Ctrl+F → search `azurerm_role_assignment`; review the three scopes. Search `soft_delete` and `default_retention_duration`. Then Ctrl+P → `lessons/day51/Recovery-Lesson.ps1` → search `FailIfExists`. You are reviewing scope and behavior, not being asked to recreate the code.

**Decision ticket:** A proposal states, “The successful disk restore proves the production application's database is consistent, offsite protected and ransomware immutable; approve migration.” Reject or amend it in three sentences. Identify the evidence that is valid, two unsupported claims and the next workload-specific recovery test. This is a personal lab review, not organizational approval or an ATO. Relate the artifact to NIST SP 800-53 CP-9/CP-10 evidence without claiming full control compliance.

**Next:** PowerShell for cleanup. Do not start another experiment after minute 45.

## Lab 5 — Close the temporary environment, minutes 45–60

**Purpose:** remove this lesson's active billable resources while preserving exact private evidence. Cleanup deliberately discards the dummy operational snapshots; never apply that action to business backups.

```powershell
& "$Lesson/Close-Lesson.ps1"
notepad (Join-Path $Case 'cleanup-plan.log')
```

The default action is a preview. Inspect the planned deletes: only the three recorded Day 51 groups, their temporary infrastructure and exact roles. No historical workspace, Sentinel resource, Key Vault, lab network or earlier lesson belongs in this plan. A service-created restored disk/snapshot is handled separately by exact private identity and source checks.

```powershell
& "$Lesson/Close-Lesson.ps1" -Execute
```

`-Execute` authorizes this prepared closeout. It records intent, deallocates the VM first, refuses active/unknown backup jobs, removes protection before snapshot permissions, verifies snapshot source IDs, deletes only recorded restore targets, and applies a freshly checked Terraform destroy plan. Soft delete remains enabled. Metadata retained by the service is distinct from active resource cleanup; no claim is made that every service tombstone was purged. [Operational soft-delete limitations](https://learn.microsoft.com/en-us/azure/backup/backup-azure-enhanced-soft-delete-about).

**Expected:** `ACTIVE RESOURCE CLEANUP VERIFIED; SERVICE SOFT-DELETE RETENTION MAY REMAIN`, all three groups absent and private local Terraform state empty. Check Portal → Resource groups → Refresh → search the exact names; they should be absent. The raw cleanup logs stay in the case directory.

**If cleanup stops:** do not disable soft delete, remove locks, delete broad groups, or abandon state. The VM is deallocated early to limit compute cost; snapshots/disks/IP may remain billable. Give the assistant the exact error and case path, and label cleanup PARTIAL. The assistant owns repair. Do not turn cleanup into another multi-hour learner exercise. A service job or retention constraint can require later operational completion; that is explicitly open work.

## Eight original practice questions — 20 minutes including review

Answer before reading the key. These are original scenario questions, not copied certification items.

1. A disk backup policy and vault deployed successfully. Which is the strongest next proof of protection? A: Terraform exit 0. B: completed Backup job plus a matching recovery point. C: Reader on the vault. D: an NSG deny rule.
2. Restore fails authorization while the backup succeeded. The restore goes to a new group. First inspect: A: the human's password. B: vault identity's Disk Restore Operator role on that group. C: VM inbound SSH. D: subscription-wide Owner.
3. A vault displays a redundancy setting. What does it establish for today's operational disk backups? A: a second vaulted copy. B: cross-region recovery. C: neither; inspect operational snapshot storage separately. D: database consistency.
4. Choose TWO necessary observations in today's integrity test. A: source changed after backup. B: restored hash equals original. C: source disk deleted. D: public SSH enabled.
5. The file hash matches after recovery. Can you approve a multi-disk SQL application's consistency? A: yes. B: only with a larger disk. C: no, workload-aware recovery evidence is still required. D: yes if the vault has an identity.
6. A team uses customer-managed disk encryption. Its recovery point remains, but the required key is unavailable. Best response: A: backup guarantees key independence. B: review key availability and required identity permissions as recovery dependencies. C: turn off NSGs. D: grant the VM subscription Owner.
7. The restore API returns Accepted. The request times out locally. Next: A: new disk name and retry. B: remove the helper's recovery intent. C: inspect the existing recorded job and target. D: call the operation complete.
8. You deallocate the VM after the lab. Which statement is accurate? A: all charges stop. B: attached disks, snapshots and IP may still incur cost. C: retention is now zero. D: every recovery point is deleted.

**Answer key:** 1 B, 2 B, 3 C, 4 A+B, 5 C, 6 B, 7 C, 8 B. Explain the rejected alternative in each: configuration ≠ recovery; service scope ≠ human authority; operational ≠ vaulted copy; recovered content ≠ application consistency; encryption has dependencies; accepted ≠ complete; deallocation ≠ resource deletion. Aim for 6/8 with explanations. Review only missed concepts for ten minutes; do not restart the lab.

## AZ-305 reinforcement and completion note

Use 20 minutes of Alan Rodrigues' section covering backup/recovery service selection or business continuity. Match the topic by title; lecture numbering has not been verified for your course edition. Focus on choosing Azure VM backup, disk-level recovery or workload-native database recovery. Skip elementary RPO/RTO definitions you already understand. The current [AZ-305 study guide](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-305) supplies the design-objective checklist.

Save these lines in OneNote or a private text file:

```text
Day 51 learner status: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION
Backup job and recovery point verified:
Source changed after backup:
Restore job and exact new disk verified:
Original/restored hash match; changed source differs:
Unsupported application-recovery claims identified:
Cleanup: VERIFIED / PARTIAL; remaining resources or service retention:
Quiz: __/8; one concept to revisit:
```

COMPLETE requires your actual backup, restore, content validation and review; preparation is separate. PARTIAL means some objectives remain. BLOCKED means a prerequisite or service constraint prevented the exercise. FAILED EXPECTATION means an observed result contradicted the predicted behavior; preserve it rather than relabeling it.

## Remaining queue — combine objectives, remove calendar pressure

Today's design/backup/restore/evidence work is one lesson. It is an added recovery block; it does not erase the former AI foundations assigned to Days 51–53. Old calendar numbers are superseded; there is no December 11 catch-up deadline.

- **Days 52–53:** one application migration storyline across two short labs: landing-zone/workload requirements, then prepared application/data deployment and recovery/security review. Combine setup and reuse the application; do not cram both investigations into an hour.
- **Day 54:** combine the former Python JSON/REST, secretless SDK and read-only inventory API foundations. Assistant supplies working infrastructure/code; you trace one request, inspect identity scope and modify one small example.
- **Days 55–56:** keep agentic security as two investigations using the same application: recommendation-only agent and bounded identity/tools first; prompt injection, untrusted data and reliability/abuse evaluation second. The DragonWatch/SMB design objective becomes the scenario, not a separate deployment day.
- **Day 57:** human approval, observability, secrets and cost controls in one change-review scenario. Reuse the prepared agent; retain independent checks for failed authorization and unsafe recommendations.
- **Days 58–59:** combine rebuild/integration with technical acceptance, then final red-team findings/demo/portfolio review. Split if evidence needs repair; do not declare acceptance from a demo alone.

Thus setup is shared while application recovery, identity boundaries, hostile-input handling, approval and acceptance evidence stay explicit. Azure cost/monitoring carry-forward items remain a separate operations list. Two regular lab sessions weekly plus short AZ-305 study periods are enough; the remaining queue moves with your schedule.
