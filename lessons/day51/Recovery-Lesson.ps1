[CmdletBinding()]
param(
    [ValidateSet('Review','Seed','Backup','Status','Change','Restore','Verify','RemoveRestore')]
    [string]$Action = 'Review',
    [string]$Case = "$env:LOCALAPPDATA/CloudSecurityLab/day51-20261127",
    [switch]$Preparation
)
$ErrorActionPreference = 'Stop'
$c = Import-Clixml "$Case/context.xml"
$env:AZURE_CONFIG_DIR = $c.CliConfig
$phase = if ($Preparation) { 'Preparation' } else { 'Learner' }
$diskName = if ($Preparation) { $c.PrepRestoreDisk } else { $c.RestoredDisk }
$diskId = "$($c.RestoreRGId)/providers/Microsoft.Compute/disks/$diskName"
$api = '2026-03-01'
function Save-Context { $c | Export-Clixml "$Case/context.xml" }
function Completed-Job([string]$Category,[string]$After) {
    if(-not $After){throw 'Missing operation intent'}
    $jobs=Arm "$($c.VaultId)/backupJobs" GET $null "$phase-job-check"
    $matching=@($jobs.value|Where-Object {
        $_.properties.backupInstanceId -ieq $c.InstanceId -and
        $_.properties.dataSourceId -ieq $c.DiskId -and
        $_.properties.operationCategory -eq $Category -and
        [DateTimeOffset]$_.properties.startTime -ge [DateTimeOffset]$After
    })
    if($matching.Count -ne 1 -or $matching[0].properties.status -ne 'Completed'){
        throw "$Category is not uniquely verified Completed. Run Status; do not repeat the request."
    }
}
function Az([string[]]$Arguments) {
    $raw = & az.cmd @Arguments --only-show-errors --output json
    if ($LASTEXITCODE) { throw "Azure CLI failed: $($Arguments[0..1] -join ' '). See error; do not repeat uncertain writes." }
    if ($raw) { return ($raw | ConvertFrom-Json -Depth 100 -DateKind String) }
}
function Arm([string]$Path, [string]$Method='GET', $Body=$null, [string]$Record='read') {
    if (-not $Path.StartsWith("/subscriptions/$($c.Subscription)/", [StringComparison]::OrdinalIgnoreCase)) { throw 'ARM scope rejected' }
    $url = "https://management.azure.com${Path}?api-version=$api"
    $args = @('rest','--method',$Method,'--url',$url)
    if ($null -ne $Body) {
        $file = "$Case/$Record-request.json"
        $Body | ConvertTo-Json -Depth 30 | Set-Content $file
        $args += @('--body', "@$file", '--headers','Content-Type=application/json')
    }
    $result = Az $args
    $result | ConvertTo-Json -Depth 100 | Set-Content "$Case/$Record-response.json"
    return $result
}
function Guest([string]$Mode) {
    $vm = Az @('vm','show','-g',$c.RG,'-n',$c.VM,'--subscription',$c.Subscription)
    $source = @($vm.storageProfile.dataDisks | Where-Object lun -eq 0)
    if ($source.Count -ne 1 -or $source[0].managedDisk.id -ine $c.DiskId) { throw 'LUN 0 source mismatch' }
    if ($Mode -eq 'verify') {
        $restore = @($vm.storageProfile.dataDisks | Where-Object lun -eq 1)
        if ($restore.Count -ne 1 -or $restore[0].managedDisk.id -ine $diskId) { throw 'LUN 1 restore mismatch' }
    }
    $changed=if($Preparation){'0'}else{'1'}
    $script = (Get-Content "$PSScriptRoot/guest.sh" -Raw).Replace('__MODE__',$Mode).Replace('__REQUIRE_CHANGED__',$changed)
    $scriptFile = "$Case/guest-$Mode.sh"
    [IO.File]::WriteAllText($scriptFile, $script.Replace("`r`n","`n"), [Text.UTF8Encoding]::new($false))
    $c["$phase-GuestIntent"] = @{Mode=$Mode;At=[DateTimeOffset]::UtcNow.ToString('o');VM=$vm.id}
    Save-Context
    $r = Az @('vm','run-command','invoke','-g',$c.RG,'-n',$c.VM,'--subscription',$c.Subscription,'--command-id','RunShellScript','--scripts',"@$scriptFile")
    $r | ConvertTo-Json -Depth 30 | Set-Content "$Case/$phase-$Mode.json"
    $message = $r.value.message -join "`n"
    if ($message -notmatch "CSL_${Mode}_PASS") { throw "Guest operation not verified; inspect private $phase-$Mode.json" }
    $message
}
$account = Az @('account','show')
if ($account.id -ne $c.Subscription -or $account.tenantId -ne $c.Tenant) { throw 'Wrong personal Azure context' }
foreach ($rg in @($c.RG,$c.SnapshotRG,$c.RestoreRG)) {
    $g = Az @('group','show','-n',$rg,'--subscription',$c.Subscription)
    if ($g.tags.labRun -ne $c.Run) { throw "Ownership mismatch: $rg" }
}
switch ($Action) {
    Review {
        $v=Arm $c.VaultId
        $i=Arm $c.InstanceId
        [pscustomobject]@{Vault=$c.Vault;Protection=$i.properties.currentProtectionState;SoftDelete=$v.properties.securitySettings.softDeleteSettings.state;SourceDisk=$c.Disk;ShutdownUTC=$c.ShutdownUtc}
        foreach ($entry in @(@($c.DiskId,$c.Roles.Reader),@($c.SnapshotRGId,$c.Roles.Snapshot),@($c.RestoreRGId,$c.Roles.Restore))) {
            $r=Az @('rest','--method','get','--url',"https://management.azure.com$($entry[0])/providers/Microsoft.Authorization/roleAssignments/$($entry[1])?api-version=2022-04-01")
            if ($r.properties.principalId -ne $v.identity.principalId) { throw 'Role principal mismatch' }
            [pscustomobject]@{Scope=$r.properties.scope;RoleDefinition=$r.properties.roleDefinitionId;PrincipalMatchesVault=$true}
        }
    }
    Seed { if(-not $Preparation){throw 'Seed is assistant preparation only'}; Guest 'seed' }
    Backup {
        if ($c["$phase-BackupIntent"]) { throw 'Backup already requested or uncertain. Run Status; do not submit again.' }
        $before=Arm "$($c.InstanceId)/recoveryPoints"
        $p=Arm "$($c.VaultId)/backupPolicies/$($c.Policy)"
        $rule=@($p.properties.policyRules|Where-Object objectType -eq AzureBackupRule)
        if ($rule.Count -ne 1) { throw 'Ambiguous backup rule' }
        $c["$phase-BeforeRP"]=@($before.value.name)
        $c["$phase-BackupIntent"]=[DateTimeOffset]::UtcNow.ToString('o'); Save-Context
        $body=@{backupRuleOptions=@{ruleName=$rule[0].name;triggerOption=@{retentionTagOverride='Default'}}}
        $null=Arm "$($c.InstanceId)/backup" POST $body "$phase-backup"
        'Backup request submitted. Completion is NOT established; use Status.'
    }
    Status {
        $jobs=Arm "$($c.VaultId)/backupJobs" GET $null "$phase-jobs"
        $jobs.value | ForEach-Object { [pscustomobject]@{Operation=$_.properties.operation;Status=$_.properties.status;StartedUTC=$_.properties.startTime;Job=$_.name} }
        $points=Arm "$($c.InstanceId)/recoveryPoints" GET $null "$phase-points"
        $new=@($points.value|Where-Object {$_.name -notin @($c["$phase-BeforeRP"])} )
        if ($c["$phase-BackupIntent"] -and $new.Count -eq 1) {
            $c["$phase-RP"]=$new[0].name; Save-Context
            [pscustomobject]@{RecoveryPoint=$new[0].name;CreatedUTC=$new[0].properties.recoveryPointTime;Note='Confirm matching Backup job Completed before proceeding'}
        }
    }
    Change {
        if (-not $c["$phase-RP"]) { throw 'No recorded recovery point' }
        Completed-Job 'Backup' $c["$phase-BackupIntent"]
        Guest 'change'
    }
    Restore {
        if (-not $c["$phase-RP"]) { throw 'No recorded recovery point; run Status' }
        Completed-Job 'Backup' $c["$phase-BackupIntent"]
        if ($c["$phase-RestoreIntent"]) { throw 'Restore already requested or uncertain. Inspect Status and exact disk; never try a new name.' }
        $existing=Az @('disk','list','-g',$c.RestoreRG,'--subscription',$c.Subscription)
        if (@($existing|Where-Object name -eq $diskName).Count) { throw 'Restore target already exists; do not adopt it' }
        $c["$phase-RestoreIntent"]=@{At=[DateTimeOffset]::UtcNow.ToString('o');Target=$diskId;RecoveryPoint=$c["$phase-RP"]}; Save-Context
        $body=@{objectType='AzureBackupRecoveryPointBasedRestoreRequest';recoveryPointId=$c["$phase-RP"];sourceDataStoreType='OperationalStore';restoreTargetInfo=@{objectType='RestoreTargetInfo';recoveryOption='FailIfExists';restoreLocation=$c.Region;datasourceInfo=@{resourceID=$diskId;resourceUri=$diskId;datasourceType='Microsoft.Compute/disks';resourceName=$diskName;resourceType='Microsoft.Compute/disks';resourceLocation=$c.Region;objectType='Datasource'}}}
        $null=Arm "$($c.InstanceId)/restore" POST $body "$phase-restore"
        'Restore request submitted. Use Status; accepted is not completed.'
    }
    Verify {
        if (-not $c["$phase-RestoreIntent"]) { throw 'No restore intent' }
        Completed-Job 'Restore' $c["$phase-RestoreIntent"].At
        $d=Az @('disk','show','--ids',$diskId,'--subscription',$c.Subscription)
        if ($d.provisioningState -ne 'Succeeded') { throw 'Restore disk not ready' }
        $vm=Az @('vm','show','-g',$c.RG,'-n',$c.VM,'--subscription',$c.Subscription)
        $lun=@($vm.storageProfile.dataDisks|Where-Object lun -eq 1)
        if($lun.Count -and $lun[0].managedDisk.id -ine $diskId){throw 'LUN 1 already belongs to another disk'}
        if(-not $lun.Count){
            $c["$phase-AttachIntent"]=$diskId; Save-Context
            $null=Az @('vm','disk','attach','-g',$c.RG,'--vm-name',$c.VM,'--name',$diskId,'--lun','1','--caching','None','--subscription',$c.Subscription)
        }
        Guest 'verify'
        $c["$phase-VerifiedUTC"]=[DateTimeOffset]::UtcNow.ToString('o'); Save-Context
    }
    RemoveRestore {
        if (-not $c["$phase-RestoreIntent"]) { 'No recorded restore to remove'; break }
        $vm=Az @('vm','show','-g',$c.RG,'-n',$c.VM,'--subscription',$c.Subscription)
        $attached=@($vm.storageProfile.dataDisks|Where-Object {$_.managedDisk.id -ieq $diskId})
        $c["$phase-RemoveIntent"]=$diskId; Save-Context
        if($attached.Count){ $null=Az @('vm','disk','detach','-g',$c.RG,'--vm-name',$c.VM,'--name',$diskName,'--subscription',$c.Subscription) }
        $null=Az @('disk','delete','--ids',$diskId,'--subscription',$c.Subscription,'--yes')
        'Exact restored disk deleted. Source and snapshots retained.'
    }
}
