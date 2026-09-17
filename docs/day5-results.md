# Day 5 Results — Network Policy Validation

## Objective

Validate the hub-and-spoke network segmentation policy using real private Linux test hosts, while keeping the test infrastructure temporary and Terraform-managed.

## Baseline Changes

- Restricted Web HTTPS ingress from the entire Hub VNet (`10.10.0.0/16`) to only the Management subnet (`10.10.1.0/24`).
- Disabled Azure default outbound access on:
  - `snet-management`
  - `snet-web`
  - `snet-app`
  - `snet-data`
- Retained explicit workload-tier NSG rules.

## Intended Application Flow

Management -> Web : TCP 443  
Web -> App : TCP 443  
App -> Data : TCP 1433

All other tested east-west paths were expected to be blocked.

## Temporary Test Infrastructure

Terraform temporarily deployed:

- 4 private Ubuntu Linux VMs
- 4 NICs
- 2 NAT Gateways
- 2 Standard public IPs attached to the NAT Gateways
- NAT associations for the four test subnets

The VMs did not receive public IP addresses.

VM size:

`Standard_B1s`

Ubuntu image:

`Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:22.04.202608060`

## Live Connectivity Results

| Source | Destination | Port | Expected | Observed |
|---|---|---:|---|---|
| Management | Web | 443 | Allow | Connected to expected listener |
| Management | App | 443 | Deny | Timeout |
| Management | Data | 1433 | Deny | Timeout |
| Web | App | 443 | Allow | Connected to expected listener |
| Web | Data | 1433 | Deny | Timeout |
| App | Data | 1433 | Allow | Connected to expected listener |
| Data | App | 443 | Deny | Timeout |

All three expected allow paths succeeded.

All four expected deny paths were observed as blocked.

## Route Validation

The Web NIC effective route table showed:

- `10.20.0.0/16` -> `VnetLocal`
- `10.10.0.0/16` -> `VNetPeering`
- `0.0.0.0/0` -> `Internet`

This confirms that blocked east-west tests were not failing because Azure lacked a route to the destination.

## Effective NSG Validation

The Data NIC effective NSG showed:

Priority 100:

`Allow-App-SQL`

- Source: `10.20.2.0/24`
- Destination: `10.20.3.0/24`
- TCP 1433
- Allow

Priority 4000:

`Deny-Other-VNet-Traffic`

- Source: `VirtualNetwork`
- Destination: Any
- Deny

The custom deny rule executes before Azure's default `AllowVnetInBound` rule at priority 65000.

Therefore, traffic such as Web -> Data had a valid Azure route but was denied by the Data subnet security policy.

## Network Watcher

No Network Watcher instance was available in the Whizlabs sandbox.

IP Flow Verify was therefore not used.

Blocked-path attribution was instead supported by:

1. Successful listener initialization on all test hosts.
2. Successful allowed-path tests.
3. Effective route inspection.
4. Effective NSG inspection.
5. Matching custom NSG policy.

## Cleanup

`TF_VAR_enable_test_hosts` was returned to `false`.

Terraform planned:

`0 to add, 0 to change, 18 to destroy`

The temporary test infrastructure was successfully removed.

Final Terraform validation returned:

`No changes. Your infrastructure matches the configuration.`

Final state:

- 22 managed baseline Azure resources
- 1 resource-group data source
- No temporary `vm-test-*`, `nic-test-*`, `nat-test-*`, or `pip-test-*` resources

## Key Learning

Routing and security policy answer different questions.

A route answers:

"Can Azure determine how to reach this destination?"

An NSG answers:

"Is this traffic permitted to reach the destination?"

Day 5 demonstrated that a workload can have a valid route to another subnet while the connection is still intentionally blocked by NSG policy.
