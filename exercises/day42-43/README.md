# Days 42–43: OIDC and a plan for review

Prepared exercise files only. Copy this exercise and its workflow into the reviewed repository as directed by the runbook. Commit the provider lockfile with AzureRM 5.4.0 checksums for `darwin_amd64` before enabling planning. Terraform is pinned to 1.16.2.

Use the exact branch `feat/day42-43-oidc-plan`. Configure GitHub environment `csl-plan` to permit only that branch. The workflow accepts only pushes to that branch; it has no pull-request trigger. Restrict who can change the branch, workflow and environment before adding trust.

Leave environment variable `LAB_PLAN_READY` unset for the first push. That run prints only the public OIDC `iss`, `aud` and `sub` claims. Create the UAMI federated credential from those exact observed values; do not construct the subject from repository names. Claim inspection alone does not prove Azure trusts the token.

Create these seven **environment secrets** in `csl-plan`:

| Secret | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | Existing exercise UAMI client ID |
| `AZURE_TENANT_ID` | Personal tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Personal subscription ID |
| `LAB_RESOURCE_GROUP` | Existing lab resource group; UAMI receives Reader here only |
| `TFSTATE_STORAGE_ACCOUNT` | Existing Day 39 storage account |
| `TFSTATE_CONTAINER` | Separate pre-created CI container; never the Day 39 live-state container |
| `TFSTATE_RESOURCE_GROUP` | Resource group containing the existing state account |

Grant the UAMI Storage Blob Data Contributor on that exact CI container. It receives no role to write storage firewall rules and no workload Contributor role. Use the runbook to inspect and grant these scopes. The provider does not register Azure resource providers.

Set `LAB_PLAN_READY` to the literal `true`, then push a reviewed change under this exercise path. The standard `macos-15-intel` runner signs in, verifies the tenant/subscription and resource-group GET, records a non-conclusive data-access baseline, and prints its public IPv4 after two services agree. The same job waits up to ten minutes while you add that single address from the host. An already reachable baseline is allowed. Remove only the recorded temporary IP after the run; the pipeline never changes the firewall.

The backend uses direct OIDC/Entra authentication, `use_cli=false`, and key `day42-43.tfstate`. Initialization uses `-lockfile=readonly`. A plan proposes one NSG, `azurerm_network_security_group.proposed`, with no custom rules. There is no apply command. CLI exit 0 and 2 are successful Terraform outcomes; this particular exercise additionally requires exit 2 and exactly one create, zero updates and zero deletes.

Raw Azure responses, backend configuration, Terraform output/error files, binary plan and JSON remain in private runner temporary storage. The only uploaded file contains the fixed resource address/action and counts. Artifact retention is explicitly one day; artifact metadata and the GitHub run log follow their separate repository retention settings. The always-run cleanup logs out and removes temporary files. Runner interruption can prevent cleanup steps; the GitHub-hosted ephemeral runner is then the remaining isolation boundary.

If a step fails, the log deliberately gives a short error. Inspect the exact FIC, role scopes, current runner IP, container and lockfile from the private host runbook; never enable debug logging or upload the raw plan. State access and proposed changes are distinct permissions: a successful plan does not prove the UAMI could apply it.
