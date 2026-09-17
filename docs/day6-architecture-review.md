# Day 6 architecture and requirements review

Prepared September 17, 2026. Review baseline: original docs/requirements.md, Day 5 commit f13ce98, saved traffic results and outbrief. Day 6 tag deployment remains pending until recorded in day6-results.md.

## Architecture

Hub vnet-hub-dev: 10.10.0.0/16. Management 10.10.1.0/24; empty AzureFirewallSubnet 10.10.2.0/26; empty GatewaySubnet 10.10.3.0/27.

Spoke vnet-app-dev: 10.20.0.0/16. Web 10.20.1.0/24; App 10.20.2.0/24; Data 10.20.3.0/24. One NSG per workload subnet. Two peering objects connect Hub and Spoke; peering does not imply unrestricted reachability.

22 managed instances = 2 VNets + 6 subnets + 2 peerings + 3 NSGs + 6 custom NSG rules + 3 NSG/subnet associations. Whizlabs RG is a data lookup, excluded from the count.

Day 5 removed 18 temporary instances: 4 VMs, 4 NICs, 2 NAT gateways, 2 NAT public IPs, 2 NAT/public-IP associations, 4 subnet/NAT associations. No active firewall, VPN gateway, WAF, UDR or application service is part of this baseline.

## Original requirements mapped to actual evidence

| Requirement | Evidence/status | Remaining scope |
|---|---|---|
| App and database servers have no public IPs | Day 5 private test VMs had no NIC public IP; temporary public IPs belonged to NAT. No servers remain after cleanup. | Recheck any future real workload. |
| Internet must never reach App/DB directly | Private addresses, no inbound public endpoint in this design. | No external Internet-origin traffic test; future ingress/load balancers require review. |
| Web → App only required application ports | TCP443 allowed and succeeded in Day 5; source-specific NSG allow with deny-other-VNet inbound. | No exhaustive test of other ports/protocols. |
| App → DB only DB port | TCP1433 allowed and succeeded in Day 5; configured source-specific rule. | Listener was TCP, not a real SQL database; other ports were not exhaustively tested. |
| Database must not initiate connections to Web | Web NSG configuration should deny new Data-origin VNet inbound. | **Data → Web NOT live-tested.** Data → App timeout does not satisfy this test. Add it to next traffic regression. |
| Administration originates from Management | Management /24 is the Web443 allow source; that test succeeded. | No SSH/RDP administration path or full administration policy implemented. Do not call TCP443 an admin-access test. |
| Hub/spoke connected through peering | Two peering objects; Day 5 traffic crossed peering; route evidence retained. | Recheck both peerings in each recreated sandbox. |
| Reproducible Terraform deployment | Parameterized source, named sandbox state, optional host stack, deploy/test/cleanup completed Day 5. | Future persistent environment needs durable state/identity strategy beyond this local sandbox exercise. |
| No secrets committed | Interactive Whizlabs sign-in; source separates ephemeral identity; raw evidence local. | Review staged changes each commit. No full repository-history secret audit claimed. |
| Resources tagged environment/project/owner/managedBy | Existing shared map has project/environment/managedBy/purpose. **Owner missing** on 5 taggable baseline resources. | Day 6 adds required owner input; verify 2 VNets + 3 NSGs. Whizlabs-owned RG is out of management scope; child resources without tag support cannot receive these tags. |

Business objective is a three-tier application design. This phase implements network segmentation and test infrastructure, not a deployed enterprise application. Empty firewall/gateway subnets reserve addresses; they are not deployed services.

## Traffic evidence, Day 5

| Initiator | Destination | Port | Observed result |
|---|---|---:|---|
| Management | Web | 443 | PASS_ALLOW |
| Web | App | 443 | PASS_ALLOW |
| App | Data | 1433 | PASS_ALLOW |
| Management | App | 443 | BLOCK_OBSERVED_NEEDS_RULE_CHECK (timeout) |
| Management | Data | 1433 | BLOCK_OBSERVED_NEEDS_RULE_CHECK (timeout) |
| Web | Data | 1433 | BLOCK_OBSERVED_NEEDS_RULE_CHECK (timeout) |
| Data | App | 443 | BLOCK_OBSERVED_NEEDS_RULE_CHECK (timeout) |
| Data | Web | 443 | **Not tested** |

Timeouts were correlated with saved routes/NSG evidence. They do not alone prove which control dropped traffic. Network Watcher was unavailable. Listeners proved TCP reachability, not HTTPS encryption, SQL authentication or application correctness. NSGs are stateful; permitted response traffic is distinct from initiating a new connection.

## Day 6 changes

- Add required owner variable in governance.tf and owner = var.owner to common_tags.
- Existing baseline: expect five in-place tag updates and no network changes, subject to actual plan.
- New sandbox: rebuild the same 22-resource baseline with owner included.
- Future optional taggable test resources also reference common_tags; their ownership metadata will be set when they are created. This is explicit Terraform assignment, not Azure tag inheritance.
- Diagram highlights five planned owner tags and shows Day 5 temporary infrastructure as removed history.
- Record Data → Web as an evidence gap. No new traffic test is claimed today.

Management/Web/App/Data have default outbound disabled. There is no management-subnet NSG or custom outbound policy. A default Internet route alone does not provide usable outbound Internet access without the required outbound mechanism.

## Follow-up

Day 7: controlled Terraform drift exercise according to the calendar. Future traffic session: add a Data → Web new-connection test to the harness and retain listener-health, route and effective-rule evidence. Expand negative ports and administrative-path coverage as the application design develops.

