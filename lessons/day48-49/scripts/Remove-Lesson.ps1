[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day48-49-20261124'),[switch]$PreviewOnly)
. "$PSScriptRoot/Connect-Lesson.ps1" -CaseFolder $CaseFolder
$tf=Join-Path $CaseFolder 'terraform'
if(-not(Test-Path "$tf/terraform.tfstate")){throw 'Private state missing. Preserve recovery records and request exact recovery.'}
$inventory=@(Invoke-LessonAz resource list -g $c.RG --subscription $c.Subscription -o json | ConvertFrom-Json -Depth 25 -DateKind String)
$inventory | Export-Clixml "$CaseFolder/before-cleanup.xml"
foreach($r in $inventory){
 if($r.name -notin $c.ExpectedResourceNames -or -not $r.id.StartsWith($c.RGId+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected resource. Stop deletion and investigate ownership.'}
}
& terraform "-chdir=$tf" plan -destroy -input=false -no-color '-out=cleanup.tfplan' *> "$CaseFolder/cleanup-plan.log"
if($LASTEXITCODE -ne 0){throw 'Cleanup plan failed. Preserve state.'}
$p=& terraform "-chdir=$tf" show -json cleanup.tfplan | ConvertFrom-Json -Depth 100 -DateKind String
if($LASTEXITCODE -ne 0){throw 'Unreadable cleanup plan.'}
foreach($r in @($p.resource_changes)){
 if($r.address -notin $c.ExpectedAddresses -or ($r.change.actions -join ',') -ne 'delete'){throw 'Unexpected cleanup change.'}
 if($r.type -ne 'azurerm_resource_group' -and -not $r.change.before.id.StartsWith($c.RGId+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'State contains an object outside this group.'}
 if($r.type -eq 'azurerm_resource_group' -and $r.change.before.name -ne $c.RG){throw 'Wrong resource group in state.'}
 if($r.type -eq 'azurerm_role_assignment' -and $r.change.before.scope -ine $c.ContainerId){throw 'Unexpected role scope.'}
 if($r.type -eq 'azurerm_role_assignment' -and $r.change.before.name -notin @($c.RoleAssignment,$c.ReviewerAssignment)){throw 'Unexpected role-assignment identifier.'}
}
Write-Host "Cleanup plan: $(@($p.resource_changes).Count) managed resources in $($c.RG). Private evidence remains."
if($PreviewOnly){return}
if((Read-Host "Type the exact group name to delete this lesson") -cne $c.RG){throw 'Cleanup not confirmed.'}
$c.Stage='CLEANUP STARTED'; $c | Export-Clixml "$CaseFolder/context.xml"
& terraform "-chdir=$tf" apply -input=false -no-color cleanup.tfplan *> "$CaseFolder/cleanup-apply.log"
if($LASTEXITCODE -ne 0){throw 'Cleanup incomplete. Preserve logs and request recovery; do not remove the state folder.'}
$exists=Invoke-LessonAz group exists -n $c.RG --subscription $c.Subscription -o tsv
$left=@(& terraform "-chdir=$tf" state list)
if($LASTEXITCODE -ne 0 -or $exists -ne 'false' -or $left.Count){throw 'Cleanup readback failed.'}
$c.Stage='CLEANUP VERIFIED'; $c.CleanupUtc=(Get-Date).ToUniversalTime().ToString('o'); $c | Export-Clixml "$CaseFolder/context.xml"
Write-Output 'CLEANUP VERIFIED: exact resource group absent and private Terraform state empty. Evidence retained locally.'
