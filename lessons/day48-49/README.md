# Days 48–49: private storage access

Combined lesson: private endpoint/DNS review and an authenticated private/public endpoint comparison. Start with DAYS-48-49-RUNBOOK-ONENOTE.html; Markdown contains the same lesson. Preparation is separate from the learner's 60-minute practical exercise.

Infrastructure is Terraform 1.16.2 / AzureRM 5.4.0, authenticated with the operator's existing Azure CLI session. It uses isolated local state outside this repository. No GitHub Actions workflow is introduced; committing source does not deploy infrastructure.

The 17 managed resources are confined to a fresh tagged group. A VM managed identity receives Storage Blob Data Contributor at one dummy container to seed and read the fixture. Public network access, shared-key access and anonymous blob access are disabled. The Blob endpoint has a private DNS zone and VNet link. The VM permits no inbound connections; a public IP supplies explicit egress. The NSG is not a comprehensive outbound policy.

The VM probe checks private DNS and an authenticated dummy-blob read. The host independently checks the same blob through the public endpoint using its existing signed-in user with a temporary container-scoped Blob Data Reader assignment. Tokens remain in memory on their respective origins. TLS verification stays enabled. The identities differ; the external assignment is verified, but its effective permission is not separately exercised on a private route. A preparation-only same-VNet forced-public test returned 200 and was rejected as an outside-access test; its original evidence remains private. Only dummy data is used. The test does not prove coverage of all networks, identities or storage subresources.

Preparation writes exact intent, role-assignment GUID, resource names and state location before Azure mutations. The preparation script generates a plan; applying it is a separate authorized step. Source parameters must come from the saved case, never yesterday's state. Cleanup checks exact ownership, inventory and destroy-plan scope, then verifies group absence and empty state.

Runtime files, plans, state, tokens, private evidence and raw API results must remain outside Git. Copying a context into this folder is not an acceptable way to make it reproducible. Auto-shutdown is a compute backup; mandatory full teardown stops the remaining resource charges.

## Verification record

Live preparation verified November 24, 2026: VM private DNS matched its Blob endpoint, dummy seed returned 201, private read returned 200, authenticated external-host read returned 403 AuthorizationFailure, public access was Disabled, external reader scope/principal matched the intent, and auto-shutdown was Enabled. A 17-delete Terraform cleanup preview passed. Full teardown remains due after the learner session; it has not been performed during preparation.

Learner review and quiz completion are not inferred from preparation success. Keep request IDs, principals and billing exports private. The initial 16-resource fixture and later one-role addition were individually planned; the final source declares 17 resources. Historical Terraform and previous lesson branches were not changed.
