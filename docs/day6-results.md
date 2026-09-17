# Day 6 outbrief — architecture and ownership

Status: COMPLETED WITH NOTED EVIDENCE GAPS.

- Date/time: September 17, 2026
- Sandbox: new session
- Starting commit: f13ce98
- Workspace matched current sandbox: yes
- Owner alias (non-secret): mark-lab
- Plan: 0 add / 5 change / 0 destroy
- Apply result: 0 added / 5 changed / 0 destroyed
- Five owner tags verified: 5 / 5
- Existing common tags retained: yes
- Final managed count: 22 baseline managed resources
- Both peerings Connected: created successfully; not separately re-verified with Azure CLI during final Day 6 evidence pass
- Three workload NSG associations verified: present in refreshed Terraform state; not separately captured with direct Azure subnet output
- Web allow source 10.10.1.0/24: yes, directly verified in Azure
- Four workload/management subnets default outbound disabled: configured in Terraform; not separately captured with direct Azure subnet output
- Temporary VMs/NICs/NAT/public IPs absent: test hosts disabled; no temporary resources managed by the final configuration
- Final plan: exit 0; no changes
- Terraform validate result: success
- Local evidence folder: local-evidence/day6-20260917-165303
- Commit: pending
- Push: pending
- Errors, blockers, or deviations:
  - Existing data.azurerm_resource_group.lab block was accidentally removed while editing main.tf. It was restored and terraform validate then succeeded.
  - Initial multiline Azure CLI JMESPath query failed because of PowerShell argument parsing. A single-line query variable was used successfully.
  - Data -> Web traffic remains explicitly untested.

## Review conclusions

- [x] Owner gap fixed on the five taggable managed baseline resources.
- [x] Day 6 architecture documentation and diagram added.
- [x] Data -> Web remains explicitly untested.
- [x] Day 5 traffic evidence is historical; no new packet tests are claimed for Day 6.
- [x] Final Terraform plan returned no changes with detailed exit code 0.
- [ ] Sandbox ended normally or remaining session recorded.

## What I learned

Terraform common_tags is a reusable local map explicitly assigned to resources. Azure resource tags are not automatically inherited from the resource group simply because resources reside inside it.

Tags are metadata used for ownership, classification, search, cost organization, and governance. They do not grant permissions, alter NSG behavior, or control packet flow.

terraform validate checks whether the Terraform configuration is syntactically and structurally valid. A no-change terraform plan goes further: Terraform refreshes managed resources from Azure and compares the observed infrastructure with the desired configuration and state.

A Terraform data source such as data.azurerm_resource_group.lab reads an existing object. Terraform does not create or own that Whizlabs resource group.

Data -> App and Data -> Web are separate traffic paths. Blocking Data -> App does not prove Data -> Web is blocked. Data -> Web therefore remains a future traffic-test requirement.

## Handoff

Day 7: Terraform state and drift.

Start from the Day 6 baseline:
- 22 managed baseline resources
- owner metadata added to two VNets and three NSGs
- final terraform plan clean
- test hosts disabled
- Day 5 traffic evidence remains historical
- Data -> Web remains a traffic-evidence gap
