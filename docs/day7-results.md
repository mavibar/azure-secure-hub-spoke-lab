# Day 7 reconciled closeout — Terraform state and drift

Reconciled September 21, 2026 from “Explain Day 7 Refresh Changes,” saved local evidence, and the current repository. This is historical evidence, not a fresh Azure inventory.

## Confirmed technical outcome

| Item | Evidence |
|---|---|
| Fresh sandbox baseline | User-supplied apply output: 22 added, 0 changed, 0 destroyed |
| Deliberate drift | Web NSG owner: mark-lab → day7-drift-demo |
| Repair | Saved plan/recorded apply: 0 add / 1 change / 0 destroy |
| Restored owner | Saved Web NSG after snapshot: mark-lab |
| Final plan | Saved final-plan-result.txt: exit code 0 |
| Final managed count | Saved after-state: 22 managed instances |
| State continuity | Serial 23 → 25, same lineage |
| Peerings | Both saved peering records show Connected |
| Subnet NSGs | Web/App/Data saved subnet records link to their corresponding NSGs |
| Outbound setting | Management/Web/App/Data saved records show defaultOutboundAccess false |
| Tags | Five resources in owner-tags-after.csv show mark-lab and retained project/environment/managedBy values |
| Resource inventory | Two VNets and three NSGs returned at top-level; no test VM, disk, NIC, NAT or public IP listed |
| Raw evidence | local-evidence/day7-20260918-161918 in the working repository; excluded from Git |

Firewall/Gateway reserved subnets show defaultOutboundAccess true in the saved records. The four-subnet requirement concerns Management/Web/App/Data. Reserved subnets contain no deployed firewall or VPN service; do not misreport all six subnets as having the flag disabled.

## Documentation/Git reconciliation

The user's final chat reports the work done, and the professor outbrief describes the core exercise as complete. The inspected repository is clean on **feat/day7-state-drift**, tracking origin/feat/day7-state-drift, but HEAD is still **ad7c68f**, the Day 6 commit. There are no Day 7 files under its docs directory.

Therefore: **the technical exercise is evidenced; a separate Day 7 documentation commit is not present in this inspected checkout.** Upstream tracking does not establish that a new documentation commit exists. No invented Day 7 commit hash or fresh remote synchronization claim is made.

The Day 8 runbook copies this closeout into docs/day7-results.md only when that file does not already exist, and includes it in the next reviewed documentation commit. That preserves continuity without repeating the cloud exercise.

## Remaining evidence limits

- Cost visibility/amount and exact sandbox end time were not found in the reviewed saved evidence.
- Data → Web remains live-traffic untested; Day 7 metadata work did not test it.
- Day 5 packet tests remain historical and used simple TCP listeners, not production TLS/SQL.
- The established 22-resource design is reusable; the old sandbox may have expired.

## Startup lessons carried into Day 8

Populate and validate current-session variables before using them. Set AZURE_CONFIG_DIR before login. Never construct a workspace from unset values (the accidental whiz-- workspace demonstrated this). A new shell does not restore old PowerShell variables. Preserve old state and do not reuse old plans for a new sandbox.

Day 8 is identity/access planning with read-only inspection; no Terraform workspace change or network rebuild is required for current RG-level access reads.

