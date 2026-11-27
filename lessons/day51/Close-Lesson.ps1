[CmdletBinding()]
param([switch]$Execute,[string]$Case="$env:LOCALAPPDATA/CloudSecurityLab/day51-20261127")
$ErrorActionPreference='Stop'
$c=Import-Clixml "$Case/context.xml"
$env:AZURE_CONFIG_DIR=$c.CliConfig
$tf='C:/Tools/Terraform/terraform.exe'
function Az([string[]]$Arguments){
    $r=& az.cmd @Arguments --only-show-errors -o json
    if($LASTEXITCODE){throw 'Azure command failed. Stop; preserve private state.'}
    if($r){$r|ConvertFrom-Json -Depth 100 -DateKind String}
}
function TF([string[]]$Arguments,[string]$Log){
    & $tf "-chdir=$Case/terraform" @Arguments *> "$Case/$Log.log"
    if($LASTEXITCODE){throw "Terraform stopped. See private $Log.log; do not disable soft delete or delete unrelated groups."}
}
$a=Az @('account','show')
if($a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Context mismatch'}
$inventory=@()
foreach($rg in @($c.RG,$c.SnapshotRG,$c.RestoreRG)){
    $exists=Az @('group','exists','-n',$rg,'--subscription',$c.Subscription)
    if($exists){
        $g=Az @('group','show','-n',$rg,'--subscription',$c.Subscription)
        if($g.tags.labRun -ne $c.Run){throw "Ownership mismatch: $rg"}
        $inventory+=@(Az @('resource','list','-g',$rg,'--subscription',$c.Subscription))
    }
}
$inventory | ConvertTo-Json -Depth 30 | Set-Content "$Case/cleanup-inventory.json"
$inventory | Select-Object name,type,resourceGroup
TF @('plan','-destroy','-input=false','-no-color','-out=cleanup.tfplan') 'cleanup-plan'
$raw=& $tf "-chdir=$Case/terraform" show -json cleanup.tfplan
if($LASTEXITCODE){throw 'Cannot read cleanup plan'}
$p=$raw|ConvertFrom-Json -Depth 100
$changes=@($p.resource_changes|Where-Object {$_.mode -eq 'managed' -and ($_.change.actions -join ',') -ne 'no-op'})
foreach($change in $changes){
    if($change.address -notin $c.ExpectedAddresses -or ($change.change.actions -join ',') -ne 'delete'){throw 'Cleanup plan outside saved resource boundary'}
}
"Verified $($changes.Count) Terraform deletes within saved fixture. Service snapshots/restored disks require separate exact checks."
if(-not $Execute){'Review cleanup-plan.log. Add -Execute only to close this disposable lesson.';return}
$c.CleanupIntent=@{At=[DateTimeOffset]::UtcNow.ToString('o');Groups=@($c.RGId,$c.SnapshotRGId,$c.RestoreRGId)}
$c|Export-Clixml "$Case/context.xml"
# Deallocate first so a service-retention obstacle does not leave compute running.
if(@($inventory|Where-Object type -eq 'Microsoft.Compute/virtualMachines').Count){
    $null=Az @('vm','deallocate','-g',$c.RG,'-n',$c.VM,'--subscription',$c.Subscription)
}
$vaultExists=@($inventory|Where-Object type -eq 'Microsoft.DataProtection/backupVaults').Count
if($vaultExists){
    $jobs=Az @('rest','--method','get','--url',"https://management.azure.com$($c.VaultId)/backupJobs?api-version=2026-03-01")
    if(@($jobs.value|Where-Object {$_.properties.status -notin @('Completed','Failed','Cancelled','CompletedWithWarnings')}).Count){throw 'A backup/restore job is still active or has an unrecognized status. VM is deallocated; wait and rerun cleanup after job completion.'}
}
# Stop protection before touching snapshots or the vault identity's permissions.
$state=& $tf "-chdir=$Case/terraform" state list
if($LASTEXITCODE){throw 'State read failed'}
if('azurerm_data_protection_backup_instance_disk.source' -in $state){
    TF @('plan','-destroy','-target=azurerm_data_protection_backup_instance_disk.source','-input=false','-no-color','-out=stop-protection.tfplan') 'stop-protection-plan'
    $raw=& $tf "-chdir=$Case/terraform" show -json stop-protection.tfplan
    if($LASTEXITCODE){throw 'Cannot verify stop-protection plan'}
    $sp=$raw|ConvertFrom-Json -Depth 100
    $mut=@($sp.resource_changes|Where-Object {($_.change.actions -join ',') -ne 'no-op'})
    if($mut.Count -ne 1 -or $mut[0].address -ne 'azurerm_data_protection_backup_instance_disk.source' -or ($mut[0].change.actions -join ',') -ne 'delete'){throw 'Unexpected stop-protection scope'}
    TF @('apply','-input=false','-no-color','stop-protection.tfplan') 'stop-protection'
}
# Keep soft-delete configuration On. Only disposable operational snapshots are removed.
if(Az @('group','exists','-n',$c.SnapshotRG,'--subscription',$c.Subscription)){
    $snaps=@(Az @('snapshot','list','-g',$c.SnapshotRG,'--subscription',$c.Subscription))
    $snaps|ConvertTo-Json -Depth 30|Set-Content "$Case/cleanup-snapshots.json"
    foreach($s in $snaps){
        if($s.creationData.sourceResourceId -ine $c.DiskId){throw 'Snapshot source mismatch; leave it for assistant review'}
    }
    foreach($s in $snaps){$null=Az @('snapshot','delete','--ids',$s.id,'--subscription',$c.Subscription)}
}
if(Az @('group','exists','-n',$c.RestoreRG,'--subscription',$c.Subscription)){
    $disks=@(Az @('disk','list','-g',$c.RestoreRG,'--subscription',$c.Subscription))
    foreach($d in $disks){
        $phase=if($d.name -eq $c.PrepRestoreDisk){'Preparation'}elseif($d.name -eq $c.RestoredDisk){'Learner'}else{throw 'Unrecognized restore disk'}
        if($c["$phase-RestoreIntent"].Target -ine $d.id){throw 'Disk lacks exact recovery intent'}
        & "$PSScriptRoot/Recovery-Lesson.ps1" -Action RemoveRestore -Case $Case -Preparation:($phase -eq 'Preparation')
    }
}
# Refresh because the protection item and service-created resources changed.
TF @('plan','-destroy','-input=false','-no-color','-out=final-cleanup.tfplan') 'final-cleanup-plan'
$raw=& $tf "-chdir=$Case/terraform" show -json final-cleanup.tfplan
if($LASTEXITCODE){throw 'Final plan read failed'}
$final=$raw|ConvertFrom-Json -Depth 100
foreach($r in @($final.resource_changes|Where-Object {($_.change.actions -join ',') -ne 'no-op'})){
    if($r.address -notin $c.ExpectedAddresses -or ($r.change.actions -join ',') -ne 'delete'){throw 'Final cleanup boundary mismatch'}
}
TF @('apply','-input=false','-no-color','final-cleanup.tfplan') 'final-cleanup'
foreach($rg in @($c.RG,$c.SnapshotRG,$c.RestoreRG)){
    if(Az @('group','exists','-n',$rg,'--subscription',$c.Subscription)){throw 'Group still exists; cleanup PARTIAL'}
}
$remaining=& $tf "-chdir=$Case/terraform" state list
if($LASTEXITCODE -or $remaining){throw 'Local state not empty'}
$c.Stage='ACTIVE RESOURCE CLEANUP VERIFIED; SERVICE SOFT-DELETE RETENTION MAY REMAIN'
$c.CleanupVerifiedUTC=[DateTimeOffset]::UtcNow.ToString('o')
$c|Export-Clixml "$Case/context.xml"
$c.Stage
