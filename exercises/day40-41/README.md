# Days 40–41 pull-request investigations

The starting commit contains two deliberate defects for investigation. The workflow runs two independent jobs so each ticket has its own result.

- Day 40 uses the Terraform validation job. Diagnose the root output reference using the validation error and module interface.
- Day 41 uses the RDP policy scan job. Determine which source can reach TCP 3389 and restrict it to the approved management subnet `10.10.1.0/24`.

The Terraform root and the security fixture use synthetic resource names. The NSG module comes from the completed Days 37–38 refactor. The checks cover configuration validity and the selected RDP policy.

From the repository root, reproduce the validation job with Terraform `1.16.2`.

```powershell
terraform fmt -check -recursive exercises/day40-41
terraform -chdir=exercises/day40-41/terraform init -backend=false -input=false -lockfile=readonly
terraform -chdir=exercises/day40-41/terraform validate -no-color
```

Use the isolated Checkov installation prepared with the lesson. For a fresh clone, create a local environment using Python `3.12` and install Checkov `3.4.4` there once.

```powershell
py -3.12 -m venv exercises/day40-41/.venv
& ./exercises/day40-41/.venv/Scripts/python.exe -m pip install checkov==3.4.4
```

Then reproduce the policy check.

```powershell
& ./exercises/day40-41/.venv/Scripts/python.exe ./exercises/day40-41/.venv/Scripts/checkov --file exercises/day40-41/security-fixture/main.tf --framework terraform --check CKV_AZURE_9 --skip-download
```

Record the failing check, relevant file and line, your explanation, the smallest corrective edit and the passing rerun. Keep the plan and apply commands outside this exercise. The jobs require source files and provider schemas, and the policy scanner reads the fixture directly.
