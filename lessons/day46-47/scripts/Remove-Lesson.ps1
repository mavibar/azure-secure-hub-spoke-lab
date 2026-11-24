[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day46-47-20261123'))
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$false
. (Join-Path $PSScriptRoot 'Connect-Lesson.ps1') -CaseFolder $CaseFolder
if($c.RG -ne "rg-csl-policy-$($c.Run)" -or $c.Run -notmatch '^d46-[a-f0-9]{8}$'){throw 'Unexpected cleanup target.'}
$tf=Join-Path $CaseFolder 'terraform'
if(-not(Test-Path -LiteralPath "$tf/terraform.tfstate")){throw 'Private state missing. Do not delete by guessing.'}
$inventory=@(Invoke-LessonAz resource list -g $c.RG --subscription $c.Subscription -o json | ConvertFrom-Json -DateKind String)
$inventory | Export-Clixml -LiteralPath "$CaseFolder/before-cleanup.xml"
$names=@('nsg-reference','nsg-drift')+@($c.ProbeNames)
if(@($inventory | Where-Object {$_.name -notin $names -or $_.type -ne 'Microsoft.Network/networkSecurityGroups' -or $_.tags.labRun -ne $c.Run}).Count){throw 'Unexpected resource in the group; request exact recovery.'}
if((Read-Host "Delete only this lesson's two policies, assignments and group? Type $($c.RG)") -cne $c.RG){throw 'Cleanup not confirmed.'}
foreach($probe in $c.ProbeNames){
 if($inventory.name -contains $probe){Invoke-LessonAz network nsg delete -g $c.RG -n $probe --subscription $c.Subscription --output none}
}
& terraform "-chdir=$tf" plan '-destroy' '-input=false' '-no-color' '-out=cleanup.tfplan' *> "$CaseFolder/cleanup-plan.log"
if($LASTEXITCODE -ne 0){throw 'Cleanup plan failed; preserve the private state.'}
$p=& terraform "-chdir=$tf" show -json cleanup.tfplan | ConvertFrom-Json -Depth 100 -DateKind String
if($LASTEXITCODE -ne 0){throw 'Cleanup plan unreadable.'}
$allowed=@('azurerm_resource_group.lab','azurerm_network_security_group.sample["drift"]','azurerm_network_security_group.sample["reference"]','azurerm_policy_definition.owner','azurerm_policy_definition.location','azurerm_resource_group_policy_assignment.owner','azurerm_resource_group_policy_assignment.location')
foreach($r in @($p.resource_changes)){
 if($r.address -notin $allowed -or ($r.change.actions -join ',') -ne 'delete'){throw 'Unexpected cleanup change.'}
 if($r.type -eq 'azurerm_resource_group' -and $r.change.before.name -ne $c.RG){throw 'Wrong resource group in state.'}
 if($r.type -eq 'azurerm_policy_definition' -and $r.change.before.name -notin $c.DefinitionNames){throw 'Wrong definition in state.'}
}
& terraform "-chdir=$tf" apply '-input=false' '-no-color' cleanup.tfplan *> "$CaseFolder/cleanup-apply.log"
if($LASTEXITCODE -ne 0){throw 'Cleanup incomplete. Preserve the logs and return to the preparation chat.'}
$exists=Invoke-LessonAz group exists -n $c.RG --subscription $c.Subscription -o tsv
$remaining=@(& terraform "-chdir=$tf" state list)
if($LASTEXITCODE -ne 0 -or $exists -ne 'false' -or $remaining.Count){throw 'Cleanup readback did not pass.'}
$defs=@(Invoke-LessonAz policy definition list --subscription $c.Subscription -o json | ConvertFrom-Json -Depth 100 -DateKind String)
if(@($defs | Where-Object name -In $c.DefinitionNames).Count){throw 'A lesson policy definition remains.'}
$c.Stage='CLEANUP VERIFIED'; $c['CleanupUtc']=(Get-Date).ToUniversalTime().ToString('o'); $c | Export-Clixml "$CaseFolder/context.xml"
Write-Output 'CLEANUP VERIFIED: lab group absent, private Terraform state empty, both lesson definitions absent. Evidence retained privately.'
