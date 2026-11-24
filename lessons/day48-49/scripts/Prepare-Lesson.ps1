# Assistant preparation: creates private recovery records and a plan, never applies.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$CaseFolder,[Parameter(Mandatory)][string]$PreviousContext)
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$false
function Invoke-AzChecked { & az @args; if($LASTEXITCODE -ne 0){throw 'Azure preflight failed.'} }
if(Test-Path -LiteralPath $CaseFolder){throw 'Existing case. Inspect its state; do not generate another fixture.'}
$old=Import-Clixml -LiteralPath $PreviousContext
$cli=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AzureCloudSecurityLab/personal-cli'
$env:AZURE_CONFIG_DIR=$cli
$a=Invoke-AzChecked account show -o json | ConvertFrom-Json -DateKind String
if($a.id -ne $old.Subscription -or $a.tenantId -ne $old.Tenant){throw 'Wrong personal context.'}
$run='d48-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$c=[ordered]@{Run=$run;Subscription=$a.id;Tenant=$a.tenantId;CliConfig=$cli;Folder=$CaseFolder;RG="rg-csl-private-$run";VM='vm-private-tester';Storage=('csl'+$run.Replace('-',''));RoleAssignment=[guid]::NewGuid().ToString();Stage='INTENT SAVED';ShutdownUtc=(Get-Date).ToUniversalTime().AddHours(4).ToString('HHmm');CreatedUtc=(Get-Date).ToUniversalTime().ToString('o')}
$c.RGId="/subscriptions/$($c.Subscription)/resourceGroups/$($c.RG)"
$c.StorageId="$($c.RGId)/providers/Microsoft.Storage/storageAccounts/$($c.Storage)"
$c.ContainerId="$($c.StorageId)/blobServices/default/containers/lesson"
$c.RoleId="$($c.ContainerId)/providers/Microsoft.Authorization/roleAssignments/$($c.RoleAssignment)"
$user=& az ad signed-in-user show -o json | ConvertFrom-Json -DateKind String
if($LASTEXITCODE -ne 0 -or -not $user.id){throw 'Existing reviewer identity lookup failed.'}
$c.ReviewerPrincipal=$user.id
$c.ReviewerAssignment=[guid]::NewGuid().ToString()
$c.ReviewerRoleId="$($c.ContainerId)/providers/Microsoft.Authorization/roleAssignments/$($c.ReviewerAssignment)"
$c.ExpectedAddresses=@('azurerm_resource_group.lab','azurerm_virtual_network.lab','azurerm_subnet.tester','azurerm_subnet.endpoint','azurerm_network_security_group.tester','azurerm_public_ip.egress','azurerm_network_interface.tester','azurerm_network_interface_security_group_association.tester','azurerm_linux_virtual_machine.tester','azurerm_dev_test_global_vm_shutdown_schedule.safety','azurerm_storage_account.lab','azurerm_storage_container.lesson','azurerm_private_dns_zone.blob','azurerm_private_dns_zone_virtual_network_link.lab','azurerm_private_endpoint.blob','azurerm_role_assignment.dummy_writer')
$c.ExpectedResourceNames=@('vnet-private-lesson','nsg-tester-no-inbound','pip-tester-egress','nic-tester','nic-private-endpoint',$c.VM,'disk-private-tester','shutdown-computevm-vm-private-tester',$c.Storage,'privatelink.blob.core.windows.net','privatelink.blob.core.windows.net/link-lesson-vnet','pe-lesson-blob')
$c.ExpectedAddresses+=@('azurerm_role_assignment.external_reader')
$null=New-Item -ItemType Directory -Path $CaseFolder
$c | Export-Clixml "$CaseFolder/context.xml"
if((Invoke-AzChecked group exists -n $c.RG --subscription $c.Subscription -o tsv) -ne 'false'){throw 'RG collision. Do not adopt.'}
$nameCheck=Invoke-AzChecked storage account check-name --name $c.Storage --subscription $c.Subscription -o json | ConvertFrom-Json
if(-not $nameCheck.nameAvailable){throw 'Storage collision. Inspect exact ownership before any new intent.'}
$tf=Join-Path $CaseFolder 'terraform'; $null=New-Item -ItemType Directory -Path $tf
$source=Join-Path (Split-Path $PSScriptRoot) 'terraform'
Copy-Item -LiteralPath "$source/main.tf","$source/.terraform.lock.hcl" -Destination $tf
# Generate a public SSH key solely to satisfy VM provisioning; no inbound SSH is allowed.
# Its private half is never serialized or retained. Run Command is the access path.
$rsa=[Security.Cryptography.RSA]::Create(2048); $p=$rsa.ExportParameters($false)
$stream=[IO.MemoryStream]::new()
foreach($bytes in @([Text.Encoding]::ASCII.GetBytes('ssh-rsa'),$p.Exponent,([byte[]](@(0)+$p.Modulus)))){
 $length=[BitConverter]::GetBytes([int]$bytes.Length); [array]::Reverse($length)
 $stream.Write($length); $stream.Write([byte[]]$bytes)
}
$pub='ssh-rsa '+[Convert]::ToBase64String($stream.ToArray())+' disposable-run-command-only'
$rsa.Dispose(); $stream.Dispose()
@{subscription_id=$c.Subscription;tenant_id=$c.Tenant;run_id=$run;ssh_public_key=$pub;role_assignment_id=$c.RoleAssignment;reviewer_assignment_id=$c.ReviewerAssignment;reviewer_principal_id=$c.ReviewerPrincipal;shutdown_utc=$c.ShutdownUtc} | ConvertTo-Json | Set-Content "$tf/lesson.auto.tfvars.json" -Encoding utf8
$env:TF_PLUGIN_CACHE_DIR='C:/git/azure-secure-hub-spoke-lab/infra/terraform/.terraform/providers'
& terraform "-chdir=$tf" init -input=false -lockfile=readonly -no-color *> "$CaseFolder/init.log"
if($LASTEXITCODE -ne 0){throw 'Initialization failed. Inspect private init.log.'}
& terraform "-chdir=$tf" validate -no-color *> "$CaseFolder/validate.log"
if($LASTEXITCODE -ne 0){throw 'Validation failed. Inspect private validate.log.'}
& terraform "-chdir=$tf" plan -input=false -no-color '-out=fixture.tfplan' *> "$CaseFolder/plan.log"
if($LASTEXITCODE -ne 0){throw 'Plan failed. Inspect private plan.log.'}
$plan=& terraform "-chdir=$tf" show -json fixture.tfplan | ConvertFrom-Json -Depth 100 -DateKind String
if($LASTEXITCODE -ne 0 -or @($plan.resource_changes).Count -ne 17){throw 'Expected exactly 17 creates.'}
foreach($r in $plan.resource_changes){if($r.address -notin $c.ExpectedAddresses -or ($r.change.actions -join ',') -ne 'create'){throw 'Unexpected plan change.'}}
$c.Stage='17-CREATE PLAN VERIFIED'; $c | Export-Clixml "$CaseFolder/context.xml"
Write-Output 'Prepared isolated 17-create plan. Apply is a separate authorized preparation step.'
