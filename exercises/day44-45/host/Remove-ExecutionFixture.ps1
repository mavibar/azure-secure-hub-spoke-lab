[CmdletBinding()]
param([Parameter(Mandatory)][string]$CaseFolder)
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$false
function AzChecked { & az @args; if($LASTEXITCODE -ne 0){throw 'Cleanup command failed. Preserve the record and finish exact cleanup before closing.'} }
function JsonAz { AzChecked @args --output json | ConvertFrom-Json -DateKind String }
$file=Join-Path $CaseFolder 'execution.xml'; $x=Import-Clixml -LiteralPath $file; $c=$x.Original
$env:AZURE_CONFIG_DIR=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AzureCloudSecurityLab/personal-cli'
$a=JsonAz account show
if($a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Wrong Azure context.'}
if((Read-Host 'Set LAB44_MODE=inspect, confirm all GitHub jobs AND VM Run Commands have finished, then type CLEANUP') -cne 'CLEANUP'){throw 'Cleanup not approved.'}
$exists=(AzChecked group exists -n $x.RG --subscription $c.Subscription -o tsv) -eq 'true'
if($exists){
 $g=JsonAz group show -n $x.RG --subscription $c.Subscription
 if($g.tags.labRun -ne $x.Run){throw 'Execution group ownership mismatch.'}
 $inventory=@(JsonAz resource list -g $x.RG --subscription $c.Subscription)
 $inventory | Export-Clixml -LiteralPath (Join-Path $CaseFolder 'before-teardown.xml')
 $allowed=@('Microsoft.Network/networkSecurityGroups','Microsoft.Network/virtualNetworks','Microsoft.Network/networkInterfaces','Microsoft.Network/publicIPAddresses','Microsoft.Compute/virtualMachines','Microsoft.Compute/disks','Microsoft.Compute/virtualMachines/extensions','Microsoft.ManagedIdentity/userAssignedIdentities')
 if(@($inventory | Where-Object {$_.type -notin $allowed}).Count){throw 'Unexpected resource type in execution group; inspect before deletion.'}
 $inventory | Select-Object name,type | Format-Table
 if((Read-Host "Type the exact execution resource-group name to approve deleting the listed temporary resources: $($x.RG)") -cne $x.RG){throw 'Exact deletion not approved.'}
}
# Revoke only recorded grants. These IDs are never inferred from a broad role name.
foreach($principal in @($c.PrincipalId,$x.ApplyPrincipal)){
 if(-not $principal){continue}
 $roles=@(JsonAz role assignment list --assignee-object-id $principal --all --fill-principal-name false --subscription $c.Subscription)
 foreach($assignment in $x.Assignments){if($roles.id -contains $assignment.Id){AzChecked role assignment delete --ids $assignment.Id --subscription $c.Subscription}}
}
$f=@(JsonAz identity federated-credential list --identity-name $c.Identity -g $c.RG --subscription $c.Subscription)
if($f.name -contains $c.Federation){
 $owned=$f | Where-Object name -eq $c.Federation
 if($owned.subject -ne $c.Subject){throw 'Original federation differs from record.'}
 AzChecked identity federated-credential delete --identity-name $c.Identity -g $c.RG -n $c.Federation --subscription $c.Subscription --yes
}
$storage=JsonAz storage account show --ids $c.StorageId
if($storage.networkRuleSet.virtualNetworkRules.id -contains $x.SubnetId){AzChecked storage account network-rule remove -g $c.StorageRG --account-name $c.Storage --subnet $x.SubnetId --subscription $c.Subscription -o none}
if($exists){AzChecked group delete -n $x.RG --subscription $c.Subscription --yes}
if((AzChecked group exists -n $x.RG --subscription $c.Subscription -o tsv) -ne 'false'){throw 'Execution group deletion not verified.'}
foreach($definition in @($x.CommandRole,$x.WriterRole)){
 $def=@(JsonAz role definition list --custom-role-only true --subscription $c.Subscription | Where-Object id -like "*/$definition")
 if($def.Count){AzChecked role definition delete --name $definition --subscription $c.Subscription}
}
$storage=JsonAz storage account show --ids $c.StorageId
if($storage.networkRuleSet.defaultAction -ne 'Deny' -or $storage.networkRuleSet.virtualNetworkRules.id -contains $x.SubnetId){throw 'Network cleanup not verified.'}
$roles=@(JsonAz role assignment list --assignee-object-id $c.PrincipalId --all --fill-principal-name false --subscription $c.Subscription)
if(@($x.Assignments | Where-Object {$roles.id -contains $_.Id}).Count){throw 'Original identity still has a lesson assignment.'}
$workload=@(JsonAz resource list -g $c.RG --subscription $c.Subscription | Where-Object {$_.type -eq 'Microsoft.Network/networkSecurityGroups' -and $_.name -eq 'nsg-csl-ci-review'})
$x.CleanupUtc=(Get-Date).ToUniversalTime().ToString('o'); $x.WorkloadNsgRemaining=($workload.Count -gt 0)
$x | Export-Clixml -LiteralPath $file
Write-Output 'Execution group absent, recorded role grants removed, storage subnet exception absent and Default Deny retained.'
if($workload.Count){Write-Warning 'Workload NSG and its state remain: record PARTIAL workload cleanup. The temporary VMs are removed to stop their running costs. Do not delete the backend or edit state.'}
Write-Output 'Keep the private evidence. Review disks/public IPs and delayed billing in the Portal.'
