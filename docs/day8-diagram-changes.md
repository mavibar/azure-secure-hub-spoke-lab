# Day 8 diagram — how to read the changes

Image: day8-architecture.png. Status: established design plus proposed access model.

## Left: established network

The 22-resource hub/spoke baseline was last verified in the Day 7 sandbox. It is not automatically present in today's new sandbox. The picture retains Hub/Spoke ranges, subnets, peering and the three intended application flows. Reserved firewall/gateway subnets do not represent deployed services. Day 5 temporary VMs/NAT/public IPs remain removed from the design used today.

Day 7's drift loop has been replaced by an identity/access design. There is no Day 8 network change.

## Right: future access design

Dashed amber arrows are proposals, not actual role assignments:

- Security reviewer group → Reader.
- Network operator group → Network Contributor.
- Future network automation → federated identity plus Network Contributor.
- Separate access administrator → Role Based Access Control Administrator, with controlled delegation planned.
- Future app managed identity → service-specific role at a target that has not been selected.

The RG box means the current lab RG or a narrower suitable scope. Read the access-model worksheet for why a full network lifecycle job may use RG scope while a single-NSG test uses resource scope.

The Whizlabs student account is shown as an object to inspect. The diagram does not assign that user a role by assumption. Groups/identities shown in the proposed model are not created today.

## Keep the layers separate

Azure RBAC authorizes management operations and supported service-data operations. NSGs filter traffic. An owner tag is a label, not a permission grant. Data→Web remains a future traffic test; identity planning does not close it.

Day 9's Reader test is a plan for a separate isolated actor. A read and a tag-write denial have not been executed by this diagram or by Day 8 preparation.

