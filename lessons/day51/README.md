# Day 51 — Azure recovery evidence

One combined lesson covers backup design, a real Azure Disk Backup job, alternate-location restore and file-integrity validation. Preserve the approved 30-minute prelesson / 60-minute practical / original quiz and AZ-305 reinforcement format. The student has passed AZ-104 and has substantial Commvault experience.

`DAY-51-RUNBOOK-ONENOTE.html` and the Markdown edition contain the same commands. The private start card supplies live resource names and preparation status; it is not published here. No student completion is inferred from assistant preparation.

Terraform 1.16.2 and AzureRM 5.4.0 define 19 managed addresses: three dedicated groups, small Ubuntu verification VM and network, source disk, Backup vault/policy/instance and three exact scoped service-role assignments. The VM has no inbound access, no password login, and a backup shutdown schedule. The explicit egress public IP remains billable after deallocation until deleted. The disk is platform-key encrypted; no Key Vault/CMK deployment is part of this exercise.

Azure Disk Backup is operational-tier snapshot protection, not a vault-stored copy or application-consistent VM backup. Soft delete stays On. The restored filesystem is mounted read-only; the dummy file is checked against its original hash. This is a scoped recovery demonstration, not an application acceptance or ATO.

## Engineering entry points

- `Recovery-Lesson.ps1`: Review, Backup, Status, Change, Restore, Verify, RemoveRestore; Seed and the Preparation switch are reserved for assistant preflight. Uses existing Azure CLI authentication and checked ARM operations; no stored access tokens or Azure CLI extension is required.
- `guest.sh`: bounded source/restore disk checks and one harmless file. Never apply this initialization to an existing workload disk.
- `Close-Lesson.ps1`: preview by default; Execute records intent, deallocates compute, stops protection, removes only exact disposable snapshots/restore targets, then verifies active-resource teardown. An unrecognized resource, job or service retention constraint stops cleanup for assistant review. It does not disable soft delete.
- `terraform/`: parameterized source and provider lock. Real values/state/plans live in the private case directory. Do not use old hub/spoke state.

Preparation must save exact subscription/tenant, group/resource IDs, pre-generated role-assignment GUIDs and ownership identifier before applying. Check current costs, SKU/quota/provider availability, exact plan and role scope first. The helper is tied to that saved context; it is not a generic subscription deletion tool. Rebuilds require a new reviewed preparation case, not changing the default path and guessing IDs.

The lesson's last section maps the revised remaining queue. It explicitly retains the original JSON/REST, secretless SDK, scoped inventory API and agentic security objectives. Calendar dates are not an overdue-task backlog. Existing unrelated Azure monitoring/cost carry-forwards remain separate.

## Validation record

Observed November 27, 2026: Terraform applied all19 managed addresses; protection state ProtectionConfigured; soft delete On; all three exact role assignments matched the vault identity. The real Initial Backup and Restore jobs both completed. The restored file's SHA256 matched the original harmless content. The preparation restored disk was detached/deleted, leaving the source unchanged for the learner. Preparation did not exercise the learner's change-after-backup step or complete final teardown.

PowerShell syntax passed and all seven OneNote code blocks match Markdown. Cleanup preview is not cleanup execution; actual final teardown and any service-retention constraint remain to be observed after the lesson. Runtime identifiers, state, plans, raw API responses, cost-account records and private evidence stay outside Git.
