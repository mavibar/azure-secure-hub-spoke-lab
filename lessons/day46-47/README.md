# Days 46–47: tagging and location policy

Historical lesson source, reconciled into the repository on November 24, 2026. Terraform 1.16.2 / AzureRM 5.4.0 created seven resources: one isolated group, two unattached NSGs, two custom policy definitions and two group-scoped assignments. Audit checked the NSG Owner tag; Deny restricted NSG locations. Azure CLI used the existing personal login for tests and the controlled tag change. No VM, storage, new identity or RBAC assignment was needed.

Terraform applied from a copied source folder with private local state. Existing hub/spoke state and older feature branches were not applied or replaced. The scripts preserve exact ownership, recovery IDs and cleanup boundaries. Source was initially local only; this commit closes that tracking gap.

## Observed closeout

On November 24, the saved learner tag readback showed Owner restored to CloudSecurityLab. The saved negative test recorded RequestDisallowedByPolicy for the exact lesson location assignment. The private context recorded CLEANUP VERIFIED, and a fresh Azure group-existence check returned false. Cleanup had removed the policy definitions as well as the group and assignments according to the recorded recovery check.

Policy state exports contain mixed/historical results and are not treated here as an independently verified final compliance assessment. No fresh recreation or retest was performed just to populate this repository. Detailed evidence, runtime IDs, saved plans and Terraform state remain private; this is a sanitized source and execution summary.

## November 25 reconciliation

Day50 examined the original Policy export at the exact two assignment IDs and two NSG IDs, selecting the latest timestamp per pair. The resulting four saved evaluations are Compliant, dated November23 around16:39UTC. This resolves the earlier mixed-export ambiguity without claiming current live compliance for deleted resources. Fresh readback also confirmed the group and both custom definitions absent, with empty local state. See the Day50 lesson for the review method.
