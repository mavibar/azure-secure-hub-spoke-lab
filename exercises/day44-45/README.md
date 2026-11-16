# Days 44–45 controlled execution

Prepared lesson code; live deployment is not yet verified. The consolidated runbook lives in the Cloud Security Engineering Lab project, day44-45/DAYS-44-45-RUNBOOK.md.

Start with repository variable LAB44_MODE=inspect. Required GitHub environment reviewers and exact branch restrictions must be configured before granting credentials. Do not run from pull requests. The workload uses the existing separate day42-43.tfstate backend key.

- terraform/: one unattached demonstration NSG; revision.txt selects v1 or v2.
- scripts/dispatch.py: hosted GitHub job invokes its own isolated Azure VM.
- scripts/guest.py: MSI backend access, strict saved-plan review, digest verification and execution.
- bootstrap-cloud-init.yml: disposable Ubuntu execution dependencies.
- host/: staged PowerShell setup and exact cleanup, with recovery records outside Git.

Plan and apply identities use different VMs. Both have container-scoped blob data access; only apply can change NSGs in the dedicated workload group. Raw state/plans, role assignment records and runtime identifiers must stay outside Git. Root Run Command access controls the associated VM identity: review these permissions accordingly.

Never infer completion from prepared code. Never force-unlock an uncertain backend, broaden storage to all networks, or retry an ambiguous apply. Retire both execution VMs, their disks/IPs and temporary access at session end. A canceled hosted job may leave Run Command running.
