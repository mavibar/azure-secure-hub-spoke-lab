# Assistant preparation only. The learner receives an already-created fixture.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$CaseFolder,[Parameter(Mandatory)][string]$PreviousContext)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
function Invoke-AzChecked { & az @args; if($LASTEXITCODE -ne 0){throw 'Azure command failed; preserve the exact case before recovery.'} }
if(Test-Path -LiteralPath $CaseFolder){throw 'Existing case: inspect, do not initialize another run.'}
$old=Import-Clixml -LiteralPath $PreviousContext
$env:AZURE_CONFIG_DIR=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AzureCloudSecurityLab/personal-cli'
$a=Invoke-AzChecked account show -o json | ConvertFrom-Json -DateKind String
if($a.id -ne $old.Subscription -or $a.tenantId -ne $old.Tenant){throw 'Personal Azure context mismatch.'}
$run='d46-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$c=[ordered]@{Subscription=$old.Subscription;Tenant=$old.Tenant;Run=$run;RG="rg-csl-policy-$run";Allowed='eastus';Denied='westus2';Owner='CloudSecurityLab';Folder=$CaseFolder;PreparedUtc=$null;Stage='Intent saved'}
$c.RGId="/subscriptions/$($c.Subscription)/resourceGroups/$($c.RG)"
$c.ReferenceId="$($c.RGId)/providers/Microsoft.Network/networkSecurityGroups/nsg-reference"
$c.DriftId="$($c.RGId)/providers/Microsoft.Network/networkSecurityGroups/nsg-drift"
$c.OwnerAssignment="$($c.RGId)/providers/Microsoft.Authorization/policyAssignments/csl-owner-audit"
$c.LocationAssignment="$($c.RGId)/providers/Microsoft.Authorization/policyAssignments/csl-location-deny"
$c.DefinitionNames=@("csl-$run-owner","csl-$run-location")
$c.ProbeNames=@('nsg-allowed-probe','nsg-denied-probe')
$null=New-Item -ItemType Directory -Path $CaseFolder
$c | Export-Clixml -LiteralPath "$CaseFolder/context.xml"
$tf=Join-Path $CaseFolder 'terraform'; $null=New-Item -ItemType Directory -Path $tf
$source=Join-Path (Split-Path $PSScriptRoot) 'terraform'
Copy-Item -LiteralPath "$source/main.tf","$source/.terraform.lock.hcl" -Destination $tf
@{subscription_id=$c.Subscription;tenant_id=$c.Tenant;run_id=$run;allowed_location=$c.Allowed;owner_value=$c.Owner} | ConvertTo-Json | Set-Content "$tf/lesson.auto.tfvars.json" -Encoding utf8
$exists=Invoke-AzChecked group exists -n $c.RG --subscription $c.Subscription -o tsv
if($exists -ne 'false'){throw 'Resource-group collision: no adoption.'}
$env:TF_PLUGIN_CACHE_DIR='C:/git/azure-secure-hub-spoke-lab/infra/terraform/.terraform/providers'
& terraform "-chdir=$tf" init -input=false -lockfile=readonly -no-color *> "$CaseFolder/init.log"
if($LASTEXITCODE -ne 0){throw 'Initialization failed; inspect private init.log.'}
& terraform "-chdir=$tf" validate -no-color *> "$CaseFolder/validate.log"
if($LASTEXITCODE -ne 0){throw 'Validation failed.'}
& terraform "-chdir=$tf" plan -input=false -no-color '-out=fixture.tfplan' *> "$CaseFolder/plan.log"
if($LASTEXITCODE -ne 0){throw 'Plan failed.'}
$plan=& terraform "-chdir=$tf" show -json fixture.tfplan | ConvertFrom-Json -Depth 100 -DateKind String
if($LASTEXITCODE -ne 0){throw 'Plan inspection failed.'}
$allowed=@('azurerm_resource_group.lab','azurerm_network_security_group.sample["drift"]','azurerm_network_security_group.sample["reference"]','azurerm_policy_definition.owner','azurerm_policy_definition.location','azurerm_resource_group_policy_assignment.owner','azurerm_resource_group_policy_assignment.location')
if(@($plan.resource_changes).Count -ne 7){throw 'Unexpected resource count.'}
foreach($r in $plan.resource_changes){if($r.address -notin $allowed -or ($r.change.actions -join ',') -ne 'create'){throw 'Unexpected Terraform change.'}}
$c.Stage='Reviewed seven-create plan; apply not started'; $c | Export-Clixml "$CaseFolder/context.xml"
Write-Output 'Prepared seven-create fixture plan: one RG, two unattached NSGs, two definitions and two RG-only assignments. No apply performed by this script.'
