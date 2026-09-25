# Dot-source this file. Loading it makes no Azure calls and creates no resources.
# All Azure operations are selected explicitly in DAY-11-12-RUNBOOK.md.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Save-LabRecord {
    $temporary = $script:RecordPath + '.new'
    $script:R | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
    # Atomic replacement on this local volume; the old record survives a failed write.
    Move-Item -LiteralPath $temporary -Destination $script:RecordPath -Force -ErrorAction Stop
}
function Save-LabEvidence($Name, $Object) {
    $Object | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $script:Evidence $Name) -Encoding UTF8 -ErrorAction Stop
}
function Invoke-LabAz {
    param([string[]]$AzArguments)
    $errFile = Join-Path $script:Evidence ('az-error-' + [guid]::NewGuid().ToString('N') + '.txt')
    $raw = & az @AzArguments --subscription $script:R.subscription --only-show-errors -o json 2> $errFile
    if ($LASTEXITCODE -ne 0) { throw "Azure command failed. Inspect private error file: $errFile. Do not repeat creates." }
    if ($raw) { $raw | ConvertFrom-Json -ErrorAction Stop }
}
function Assert-LabOperator {
    if ($env:AZURE_CONFIG_DIR -cne $script:R.cliCache) { throw 'Wrong Azure CLI cache.' }
    $a = Invoke-LabAz @('account','show')
    if ($a.id -ine $script:R.subscription -or $a.tenantId -ine $script:R.tenant -or
        $a.user.name -ine $script:R.operatorUser -or $a.user.type -ne 'user') { throw 'Wrong operator/subscription/tenant.' }
}
function Show-LabClock {
    $now = [DateTimeOffset]::UtcNow
    [pscustomobject]@{
        ElapsedMinutes = [math]::Round(($now - [DateTimeOffset]$script:R.startedUtc).TotalMinutes,1)
        SandboxMinutesLeft = [math]::Round(([DateTimeOffset]$script:R.expiresUtc - $now).TotalMinutes,1)
        CleanupStartsUtc = $script:R.workStopUtc
        Day11 = $script:R.day11; Day12 = $script:R.day12
    }
}
function Assert-LabWork([switch]$Day11) {
    Assert-LabOperator
    if ([DateTimeOffset]::UtcNow -ge [DateTimeOffset]$script:R.workStopUtc) { throw 'Work deadline reached. Run Invoke-LabCleanup now.' }
    if ($Day11 -and [DateTimeOffset]::UtcNow -ge [DateTimeOffset]$script:R.day11StopUtc) { throw 'Day 11 reached minute 55. Skip Day 12 and clean up.' }
}
function Get-LabLimit([int]$Minutes,[switch]$Day11) {
    $end = [DateTimeOffset]::UtcNow.AddMinutes($Minutes)
    $limit = [DateTimeOffset]$script:R.workStopUtc
    if ($Day11 -and [DateTimeOffset]$script:R.day11StopUtc -lt $limit) { $limit = [DateTimeOffset]$script:R.day11StopUtc }
    if ($end -gt $limit) { $end = $limit }
    return $end
}
function Initialize-Day1112 {
    param([string]$Repo,[string]$SubscriptionId,[string]$ResourceGroupName,
          [string]$ExpectedUsername,[string]$OwnerAlias,[ValidateRange(90,120)][int]$MinutesRemaining=120)
    $started = [DateTimeOffset]::UtcNow
    $script:Repo = (Resolve-Path -LiteralPath $Repo).Path
    $active = Join-Path $script:Repo 'local-evidence\day11-12-active.txt'
    if (Test-Path -LiteralPath $active) {
        $oldPath = (Get-Content -LiteralPath $active -Raw).Trim()
        $old = Get-Content -LiteralPath $oldPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $old.cleanupVerified) { throw 'An unresolved run exists. Use Resume-Day1112 and cleanup; do not generate new fixtures.' }
    }
    git -C $script:Repo check-ignore --quiet -- 'local-evidence/day11-12-check.json'
    if ($LASTEXITCODE -ne 0) { throw 'local-evidence must be ignored by Git before continuing.' }
    $LabContextReady = $false
    . (Join-Path $script:Repo 'scripts\Initialize-LabContext.ps1') -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ExpectedUsername $ExpectedUsername -OwnerAlias $OwnerAlias
    if (-not $LabContextReady) { throw 'Context helper did not complete.' }
    # Entra is tenant-scoped: NEVER pass this command through Invoke-LabAz.
    $selfRaw = az ad signed-in-user show --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify current operator in Entra. No resources created.' }
    $self = $selfRaw | ConvertFrom-Json -ErrorAction Stop
    if (-not $self.id -or $self.userPrincipalName -ine $Account.user.name) { throw 'Signed-in operator mismatch.' }
    $run = 'd1112-' + [guid]::NewGuid().ToString('N').Substring(0,12)
    $script:Evidence = Join-Path $script:Repo ('local-evidence\' + $run)
    New-Item -ItemType Directory -Path $script:Evidence -ErrorAction Stop | Out-Null
    $script:RecordPath = Join-Path $script:Evidence 'recovery.json'
    $vaultName = 'kv-' + $run
    $aciName = 'aci-' + $run
    $stopMinute = [math]::Min(95, $MinutesRemaining - 25)
    $script:R = [pscustomobject]@{
        schema=1; runId=$run; subscription=$Account.id; tenant=$Account.tenantId
        operatorUser=$Account.user.name; operatorId=$self.id; cliCache=$env:AZURE_CONFIG_DIR
        rg=$LabGroup.name; rgId=$LabGroup.id; location=$LabGroup.location; owner=$OwnerAlias
        startedUtc=$started.ToString('o'); expiresUtc=$started.AddMinutes($MinutesRemaining).ToString('o')
        workStopUtc=$started.AddMinutes($stopMinute).ToString('o'); day11StopUtc=$started.AddMinutes(55).ToString('o')
        vault=[pscustomobject]@{name=$vaultName;id=($LabGroup.id+'/providers/Microsoft.KeyVault/vaults/'+$vaultName);attempted=$false;preAbsent=$false;validated=$false;deleteRequested=$false;absent=$false;uri=$null}
        aci=[pscustomobject]@{name=$aciName;id=($LabGroup.id+'/providers/Microsoft.ContainerInstance/containerGroups/'+$aciName);attempted=$false;preAbsent=$false;validated=$false;deleteRequested=$false;absent=$false;principal=$null}
        secretName='lab-demo'; seedAttempted=$false; secretVersion=$null; expectedHash=$null
        grants=@(); preDenySeq=$null; firstAllowSeq=$null; revokeAfterSeq=$null; revokedUtc=$null
        day11='BLOCKED'; day12='BLOCKED'; day12Started=$false; graphReview=@(); humanControls='NOT TESTED'
        cleanupVerified=$false; softDelete='NOT CHECKED'
    }
    Save-LabRecord
    $script:RecordPath | Set-Content -LiteralPath $active -Encoding UTF8 -ErrorAction Stop
    foreach ($ns in @('Microsoft.ContainerInstance','Microsoft.KeyVault')) {
        $p = Invoke-LabAz @('provider','show','--namespace',$ns)
        if ($p.registrationState -ne 'Registered') { throw "$ns is not registered. Stop; do not register it to force the lab." }
    }
    $access = @(Invoke-LabAz @('role','assignment','list','--scope',$script:R.rgId,'--include-inherited','--fill-principal-name','false'))
    Save-LabEvidence 'operator-rg-access.json' $access
    $mine = @($access | Where-Object principalId -IEQ $script:R.operatorId)
    foreach ($assignment in $mine) {
        $definition = Invoke-LabAz @('role','definition','list','--name',($assignment.roleDefinitionId -split '/')[-1])
        Save-LabEvidence ('operator-role-'+($assignment.roleDefinitionId -split '/')[-1]+'.json') $definition
    }
    $mine | Select-Object roleDefinitionName,scope,condition | Format-Table -Wrap
    Write-Host 'Preflight saved. Read the displayed/current role permissions before Phase 2.'
    Show-LabClock
}
function Resume-Day1112 {
    param([string]$Repo)
    $script:Repo = (Resolve-Path -LiteralPath $Repo).Path
    $script:RecordPath = (Get-Content -LiteralPath (Join-Path $script:Repo 'local-evidence\day11-12-active.txt') -Raw).Trim()
    $privateRoot = [IO.Path]::GetFullPath((Join-Path $script:Repo 'local-evidence')) + [IO.Path]::DirectorySeparatorChar
    if (-not [IO.Path]::GetFullPath($script:RecordPath).StartsWith($privateRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Recovery path is outside private evidence.' }
    $script:Evidence = Split-Path -Parent $script:RecordPath
    $script:R = Get-Content -LiteralPath $script:RecordPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $env:AZURE_CONFIG_DIR = $script:R.cliCache
    Assert-LabOperator
    if ($script:R.rgId -ine ('/subscriptions/'+$script:R.subscription+'/resourceGroups/'+$script:R.rg)) { throw 'Recovery scope mismatch.' }
    Show-LabClock
}
function Get-LabObject([string]$Kind) {
    if ($Kind -eq 'vault') { $objects = @(Invoke-LabAz @('keyvault','list','--resource-type','vault','-g',$script:R.rg)) }
    elseif ($Kind -eq 'aci') { $objects = @(Invoke-LabAz @('container','list','-g',$script:R.rg)) }
    else { throw 'Unknown fixture kind.' }
    $fixture = $script:R.$Kind
    $found = @($objects | Where-Object id -IEQ $fixture.id)
    if ($found.Count -gt 1) { throw 'Ambiguous resource inventory.' }
    if ($found.Count -eq 1) {
        if (-not $fixture.attempted -or -not $fixture.preAbsent -or $found[0].tags.runId -cne $script:R.runId -or
            $found[0].tags.purpose -cne 'day11-12' -or $found[0].tags.owner -cne $script:R.owner) {
            throw 'Exact resource exists but ownership does not match this recorded attempt. Never adopt or delete it.'
        }
        return $found[0]
    }
}
function Confirm-LabVault {
    if (-not (Get-LabObject 'vault')) { throw 'Recorded vault is not present.' }
    $v = Invoke-LabAz @('keyvault','show','-g',$script:R.rg,'-n',$script:R.vault.name)
    if ($v.id -ine $script:R.vault.id -or $v.properties.tenantId -ine $script:R.tenant -or
        $v.properties.enableRbacAuthorization -ne $true -or $v.properties.enablePurgeProtection -ne $true -or
        $v.properties.softDeleteRetentionInDays -ne 7 -or $v.properties.publicNetworkAccess -ne 'Enabled' -or
        $v.properties.networkAcls.defaultAction -ne 'Allow' -or $v.properties.networkAcls.bypass -ne 'None') { throw 'Vault identity/security settings differ. Stop; do not weaken configuration.' }
    $script:R.vault.uri=$v.properties.vaultUri; $script:R.vault.validated=$true
    Save-LabRecord
    Save-LabEvidence 'vault-confirmed.json' $v
    return $v
}
function New-Day11Vault {
    Assert-LabWork -Day11
    if ($script:R.vault.attempted) { throw 'Vault create already attempted. Inspect-LabRecovery; never repeat this create blindly.' }
    $before = @(Invoke-LabAz @('keyvault','list','--resource-type','vault','-g',$script:R.rg))
    Save-LabEvidence 'vaults-before.json' $before
    if (@($before | Where-Object id -IEQ $script:R.vault.id).Count) { throw 'Name already exists in this RG. Do not adopt it.' }
    $script:R.vault.preAbsent=$true
    Save-LabRecord
    $bodyPath=Join-Path $script:Evidence 'name-check.json'
    @{name=$script:R.vault.name;type='Microsoft.KeyVault/vaults'} | ConvertTo-Json | Set-Content -LiteralPath $bodyPath -Encoding UTF8 -ErrorAction Stop
    $url='https://management.azure.com/subscriptions/'+$script:R.subscription+'/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2024-11-01'
    $available=Invoke-LabAz @('rest','--method','post','--url',$url,'--body',('@'+$bodyPath))
    Save-LabEvidence 'name-availability.json' $available
    if ($available.nameAvailable -ne $true) { throw 'Vault name unavailable. Inspect-LabRecovery; no adoption, recovery, or new-name retry in this session.' }
    $script:R.vault.attempted=$true; $script:R.day11='PARTIAL'; Save-LabRecord
    Invoke-LabAz @('keyvault','create','-g',$script:R.rg,'-n',$script:R.vault.name,'-l',$script:R.location,
        '--sku','standard','--enable-rbac-authorization','true','--enable-purge-protection','true','--retention-days','7',
        '--public-network-access','Enabled','--default-action','Allow','--bypass','None','--no-self-perms','true','--no-wait',
        '--tags',('runId='+$script:R.runId),'purpose=day11-12',('owner='+$script:R.owner)) | Out-Null
    $end=Get-LabLimit -Minutes 4 -Day11
    do {
        Assert-LabWork -Day11
        if (Get-LabObject 'vault') { $null=Confirm-LabVault; Write-Host 'VAULT VERIFIED'; return }
        Start-Sleep -Seconds 10
    } while ([DateTimeOffset]::UtcNow -lt $end)
    throw 'Vault not verified within four minutes. Inspect exact attempt, then cleanup.'
}
function Add-LabGrant([string]$Label,[string]$Principal,[string]$PrincipalType,[string]$RoleName) {
    Assert-LabWork -Day11
    $null=Confirm-LabVault
    if (@($script:R.grants | Where-Object label -EQ $Label).Count) { throw 'Grant already recorded. Inspect exact ID; do not create a replacement GUID.' }
    $defs=@(Invoke-LabAz @('role','definition','list','--name',$RoleName,'--scope',$script:R.vault.id))
    $d=@($defs | Where-Object { $_.roleName -eq $RoleName -and $_.roleType -eq 'BuiltInRole' })
    if ($d.Count -ne 1) { throw 'Cannot resolve the precise built-in role.' }
    Save-LabEvidence ($Label+'-role.json') $d[0]
    $guid=[guid]::NewGuid().ToString()
    $entry=[pscustomobject]@{label=$Label;id=($script:R.vault.id+'/providers/Microsoft.Authorization/roleAssignments/'+$guid);scope=$script:R.vault.id;roleId=$d[0].name;principal=$Principal;principalType=$PrincipalType;attemptUtc=[DateTimeOffset]::UtcNow.ToString('o');confirmed=$false;deleteRequested=$false;absent=$false}
    $script:R.grants += $entry; Save-LabRecord
    $g=Invoke-LabAz @('role','assignment','create','--name',$guid,'--assignee-object-id',$Principal,'--assignee-principal-type',$PrincipalType,'--role',$entry.roleId,'--scope',$entry.scope,'--description',($script:R.runId+' '+$Label))
    if ($g.id -ine $entry.id -or $g.principalId -ine $Principal -or $g.scope -ine $entry.scope -or ($g.roleDefinitionId -split '/')[-1] -ine $entry.roleId) { throw 'Grant response differs from exact recovery record.' }
    $entry.confirmed=$true; Save-LabRecord
    Write-Host "$Label grant created at this vault only."
}
function Initialize-DummySecret {
    Assert-LabWork -Day11
    if ($script:R.seedAttempted) { throw 'Secret set already attempted. Inspect saved record/metadata; do not create another version blindly.' }
    $null=Confirm-LabVault
    if (-not @($script:R.grants | Where-Object label -EQ 'operator-seed').Count) {
        Add-LabGrant 'operator-seed' $script:R.operatorId 'User' 'Key Vault Secrets Officer'
    }
    # Wait using READ-ONLY metadata requests, so propagation retries cannot create versions.
    $end=Get-LabLimit -Minutes 6 -Day11
    $ready=$false
    do {
        Assert-LabWork -Day11
        $errPath=Join-Path $script:Evidence 'seed-readiness-error.txt'
        $raw=az keyvault secret list --vault-name $script:R.vault.name --subscription $script:R.subscription --only-show-errors -o json 2> $errPath
        if ($LASTEXITCODE -eq 0) {
            $items=@($raw | ConvertFrom-Json -ErrorAction Stop)
            if ($items.Count) { throw 'Fresh vault is not empty. Stop and investigate; do not overwrite secrets.' }
            $ready=$true; break
        }
        $err=Get-Content -LiteralPath $errPath -Raw
        if ($err -notmatch 'ForbiddenByRbac') { throw "Seed readiness failed for a reason other than RBAC propagation. Inspect $errPath" }
        Start-Sleep -Seconds 15
    } while ([DateTimeOffset]::UtcNow -lt $end)
    if (-not $ready) { throw 'Seed role propagation exceeded six-minute budget. Clean up.' }
    $dummy='TRAINING-ONLY-'+$script:R.runId
    $sha=[Security.Cryptography.SHA256]::Create()
    $script:R.expectedHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($dummy)))).Replace('-','').ToLowerInvariant()
    $sha.Dispose()
    $script:R.seedAttempted=$true; Save-LabRecord
    # --query id prevents secret-set's normal value field from reaching output/evidence.
    $id=Invoke-LabAz @('keyvault','secret','set','--vault-name',$script:R.vault.name,'--name',$script:R.secretName,'--value',$dummy,'--query','id')
    Remove-Variable dummy
    $prefix=$script:R.vault.uri+'secrets/'+$script:R.secretName+'/'
    if (-not $id -or -not $id.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $id.Length -le $prefix.Length) { throw 'Unexpected secret version response.' }
    $script:R.secretVersion=$id; Save-LabRecord
    Write-Host 'DUMMY SECRET SEEDED; value suppressed; version/hash saved privately.'
}

# This program runs only inside ACI. Tokens and secret values stay in process memory.
$script:LabProbe = @'
import os, json, time, base64, hashlib, sys
from urllib.request import Request, build_opener, ProxyHandler
from urllib.error import HTTPError, URLError
opener = build_opener(ProxyHandler({}))
seq = 0
deadline = time.monotonic() + max(0, float(os.environ['STOP_EPOCH']) - time.time())
first_oid = None
def emit(**data):
    global seq
    seq += 1
    print(json.dumps(dict(seq=seq, epoch=time.time(), **data)), flush=True)
def get(url, headers):
    remaining = deadline-time.monotonic()
    if remaining <= 0: raise TimeoutError()
    try:
        with opener.open(Request(url, headers=headers), timeout=min(12,remaining)) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        try: return error.code, json.loads(error.read())
        except (ValueError, UnicodeDecodeError): return error.code, {'error':{'code':'NonJsonResponse'}}
def main():
    global first_oid
    imds='http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net'
    identity_end=min(deadline,time.monotonic()+120)
    first_read=True
    while time.monotonic() < deadline:
        try:
            status, body=get(imds, {'Metadata':'true'})
            if status != 200 or not body.get('access_token'):
                if first_oid is None and time.monotonic()<identity_end:
                    time.sleep(min(5,max(0,deadline-time.monotonic()))); continue
                emit(result='ERROR',reason='IMDS_UNAVAILABLE'); return 2
            token=body['access_token']
            part=token.split('.')[1]
            claims=json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
            oid=claims.get('oid','').lower()
            if not oid or claims.get('tid','').lower()!=os.environ['TENANT_ID'].lower() or (first_oid and oid!=first_oid):
                emit(result='ERROR',reason='IDENTITY_MISMATCH'); return 3
            if first_oid is None:
                first_oid=oid
                emit(result='IDENTITY',principalId=oid,tenantId=claims['tid'])
            status, body=get(os.environ['SECRET_VERSION']+'?api-version=7.4', {'Authorization':'Bearer '+token})
            if status==200:
                exact=body.get('id','').lower()==os.environ['SECRET_VERSION'].lower()
                match=hashlib.sha256(body.get('value','').encode()).hexdigest()==os.environ['EXPECTED_HASH']
                if first_read:
                    emit(result='FAILED_EXPECTATION',reason='UNEXPECTED_PREGRANT_ACCESS',http=200); return 3
                if not exact or not match:
                    emit(result='FAILED_EXPECTATION',reason='VERSION_OR_HASH_MISMATCH',http=200); return 3
                emit(result='ALLOW_VERIFIED',http=200,exactVersionMatch=exact,valueMatch=match,principalId=oid)
            else:
                err=body.get('error',{})
                inner=err.get('innererror',err.get('innerError',{}))
                if status!=403 or err.get('code')!='Forbidden' or inner.get('code')!='ForbiddenByRbac':
                    emit(result='ERROR',http=status,error=err.get('code'),inner=inner.get('code')); return 2
                emit(result='DENIED',http=403,error='Forbidden',inner='ForbiddenByRbac',principalId=oid)
            first_read=False
        except (URLError,TimeoutError):
            if first_oid is None and time.monotonic()<identity_end:
                time.sleep(min(5,max(0,deadline-time.monotonic()))); continue
            emit(result='ERROR',reason='TRANSPORT_OR_TIMEOUT'); return 2
        except Exception as error:
            emit(result='ERROR',reason=type(error).__name__); return 2
        time.sleep(min(20,max(0,deadline-time.monotonic())))
    emit(result='STOP_TIME'); return 0
sys.exit(main())
'@

function Start-Day11Workload {
    Assert-LabWork -Day11
    if (-not $script:R.secretVersion) { throw 'Seed must be verified first.' }
    if ($script:R.aci.attempted) { throw 'ACI creation already attempted. Inspect exact attempt; never recreate the identity silently.' }
    $objects=@(Invoke-LabAz @('container','list','-g',$script:R.rg))
    Save-LabEvidence 'containers-before.json' $objects
    if (@($objects | Where-Object id -IEQ $script:R.aci.id).Count) { throw 'Container name already exists. Do not adopt.' }
    $script:R.aci.preAbsent=$true; Save-LabRecord
    $environment=@(
        @{name='TENANT_ID';value=$script:R.tenant},@{name='SECRET_VERSION';value=$script:R.secretVersion},
        @{name='EXPECTED_HASH';value=$script:R.expectedHash},
        @{name='STOP_EPOCH';value=([DateTimeOffset]$script:R.workStopUtc).ToUnixTimeSeconds().ToString()})
    $spec=@{
        apiVersion='2023-05-01';type='Microsoft.ContainerInstance/containerGroups';name=$script:R.aci.name;location=$script:R.location
        tags=@{runId=$script:R.runId;purpose='day11-12';owner=$script:R.owner};identity=@{type='SystemAssigned'}
        properties=@{osType='Linux';restartPolicy='Never';containers=@(@{name='probe';properties=@{
            image='mcr.microsoft.com/azure-cli:azurelinux3.0';command=@('python3','-u','-c',$script:LabProbe)
            resources=@{requests=@{cpu=1;memoryInGB=1.5}};environmentVariables=$environment}})}
    }
    $specPath=Join-Path $script:Evidence 'aci-spec.json'
    $spec | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $specPath -Encoding UTF8 -ErrorAction Stop
    $script:R.aci.attempted=$true; Save-LabRecord
    Invoke-LabAz @('container','create','-g',$script:R.rg,'--file',$specPath,'--no-wait') | Out-Null
    $end=Get-LabLimit -Minutes 8 -Day11
    do {
        Assert-LabWork -Day11
        if (Get-LabObject 'aci') {
            $c=Invoke-LabAz @('container','show','-g',$script:R.rg,'-n',$script:R.aci.name)
            if ($c.provisioningState -eq 'Failed') { Save-LabEvidence 'aci-failed.json' $c; throw 'ACI provisioning failed. Clean up exact attempted fixture.' }
            if ($c.identity.principalId) {
                $script:R.aci.principal=$c.identity.principalId
                if ($c.identity.tenantId -ine $script:R.tenant -or $c.identity.type -ne 'SystemAssigned') { throw 'Wrong container identity.' }
                $script:R.aci.validated=$true; Save-LabRecord
                Save-LabEvidence 'aci-created.json' $c
                if ($c.provisioningState -eq 'Succeeded' -and $c.containers[0].instanceView.currentState.state -in @('Running','Terminated')) {
                    Write-Host 'ACI IDENTITY AND STARTUP RECORDED. Next read the actual workload evidence.'; return
                }
            }
        }
        Start-Sleep -Seconds 10
    } while ([DateTimeOffset]::UtcNow -lt $end)
    throw 'ACI identity not verified within eight-minute budget. Clean up.'
}
function Get-LabEvents {
    Assert-LabOperator
    $null=Get-LabObject 'aci'
    $c=Invoke-LabAz @('container','show','-g',$script:R.rg,'-n',$script:R.aci.name)
    if ($c.identity.principalId -ine $script:R.aci.principal) { throw 'ACI principal changed; experiment invalid.' }
    $path=Join-Path $script:Evidence 'workload-log.txt'
    $raw=az container logs -g $script:R.rg -n $script:R.aci.name --container-name probe --subscription $script:R.subscription --only-show-errors 2> (Join-Path $script:Evidence 'logs-error.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read ACI logs. Inspect private logs-error.txt; never restart/recreate to manufacture a result.' }
    $raw | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    $events=@(foreach ($line in $raw) { if ($line.Trim().StartsWith('{')) { $line | ConvertFrom-Json -ErrorAction Stop } })
    foreach ($e in $events) {
        if ($e.principalId -and $e.principalId -ine $script:R.aci.principal) { throw 'Workload principal does not match the Azure resource.' }
        if ($e.result -eq 'FAILED_EXPECTATION') {
            if ($script:R.day12Started) { $script:R.day12='FAILED EXPECTATION' } else { $script:R.day11='FAILED EXPECTATION' }
            Save-LabRecord; throw 'Unexpected pregrant access or wrong secret result. Clean up.'
        }
        if ($e.result -eq 'ERROR') { throw 'Workload reported a non-RBAC or identity failure. Inspect sanitized private log; clean up.' }
    }
    return $events
}
function Wait-Day11Denial {
    $end=Get-LabLimit -Minutes 4 -Day11
    do {
        Assert-LabWork -Day11
        $events=@(Get-LabEvents)
        $deny=@($events | Where-Object result -EQ 'DENIED')
        if ($deny.Count) {
            if (@($script:R.grants | Where-Object label -EQ 'workload-read').Count) { throw 'Cannot establish pregrant denial after an attempted grant.' }
            $script:R.preDenySeq=$deny[0].seq; Save-LabRecord
            Write-Host 'PASS: matching workload principal; HTTP 403 Forbidden / ForbiddenByRbac BEFORE grant.'; return
        }
        Start-Sleep -Seconds 15
    } while ([DateTimeOffset]::UtcNow -lt $end)
    throw 'No valid pregrant denial within four minutes. Do not grant; clean up.'
}
function Grant-Day11Read {
    Assert-LabWork -Day11
    if ($null -eq $script:R.preDenySeq) { throw 'First prove the pregrant RBAC denial.' }
    $events=@(Get-LabEvents)
    if (@($events | Where-Object result -EQ 'ALLOW_VERIFIED').Count) { $script:R.day11='FAILED EXPECTATION'; Save-LabRecord; throw 'Access appeared before our recorded grant. Stop.' }
    Add-LabGrant 'workload-read' $script:R.aci.principal 'ServicePrincipal' 'Key Vault Secrets User'
    $end=Get-LabLimit -Minutes 8 -Day11
    do {
        Assert-LabWork -Day11
        $allow=@(Get-LabEvents | Where-Object { $_.result -eq 'ALLOW_VERIFIED' -and $_.seq -gt $script:R.preDenySeq })
        if ($allow.Count) {
            $script:R.firstAllowSeq=$allow[0].seq; $script:R.day11='PROOF COMPLETE; CLEANUP PENDING'; Save-LabRecord
            Write-Host 'DAY 11 PROOF PASSED: HTTP 200, same principal, exact version and dummy hash match; no value output.'; return
        }
        Start-Sleep -Seconds 15
    } while ([DateTimeOffset]::UtcNow -lt $end)
    throw 'Read grant did not produce verified retrieval in eight minutes. Skip Day 12 and clean up.'
}
function Remove-LabGrant([string]$Label) {
    Assert-LabOperator
    $entries=@($script:R.grants | Where-Object label -EQ $Label)
    if ($entries.Count -eq 0) { return } # Not attempted: no grant to delete.
    if ($entries.Count -ne 1) { throw 'Ambiguous recovery grant.' }
    $entry=$entries[0]
    $entry.absent=$false; Save-LabRecord
    $list=@(Invoke-LabAz @('role','assignment','list','--scope',$entry.scope,'--fill-principal-name','false'))
    $g=@($list | Where-Object id -IEQ $entry.id)
    if ($g.Count) {
        if ($g.Count -ne 1 -or $g[0].principalId -ine $entry.principal -or $g[0].scope -ine $entry.scope -or ($g[0].roleDefinitionId -split '/')[-1] -ine $entry.roleId) { throw 'Assignment ownership mismatch. Do not delete.' }
        $entry.confirmed=$true
        $entry.deleteRequested=$true; Save-LabRecord
        Invoke-LabAz @('role','assignment','delete','--ids',$entry.id) | Out-Null
    }
    elseif (-not $entry.confirmed) { throw 'Uncertain grant attempt has never been observed. Do not equate one empty read with settled absence. Inspect exact attempt; retry cleanup, not creation.' }
    $list=@(Invoke-LabAz @('role','assignment','list','--scope',$entry.scope,'--fill-principal-name','false'))
    if (@($list | Where-Object id -IEQ $entry.id).Count) { throw 'Exact grant still present. Retry cleanup of this same ID after inspection.' }
    $entry.absent=$true; Save-LabRecord
    Write-Host "$Label exact assignment VERIFIED ABSENT."
}
function Start-Day12Review {
    Assert-LabWork
    if ($script:R.day11 -ne 'PROOF COMPLETE; CLEANUP PENDING') { throw 'Day 11 proof is incomplete. Skip Day 12 and clean up.' }
    if ([DateTimeOffset]::UtcNow -ge [DateTimeOffset]$script:R.day11StopUtc -or
        ([DateTimeOffset]$script:R.workStopUtc-[DateTimeOffset]::UtcNow).TotalMinutes -lt 35) { throw 'Day 12 time gate failed. Clean up instead.' }
    $script:R.day12Started=$true; $script:R.day12='PARTIAL'; Save-LabRecord
    Remove-LabGrant 'operator-seed'
    # Existing delegated login only: no extra scopes, consent, registration or tenant writes.
    $principalFilter=[uri]::EscapeDataString("principalId eq '$($script:R.operatorId)'")
    $reads=@(
        @{name='security-defaults';url='https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy?$select=id,isEnabled'},
        @{name='conditional-access';url='https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$select=id,displayName,state&$top=1'},
        @{name='own-directory-pim';url=('https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances?$filter='+$principalFilter+'&$select=id,principalId,roleDefinitionId,directoryScopeId,startDateTime,endDateTime')})
    foreach ($read in $reads) {
        Assert-LabWork
        $errPath=Join-Path $script:Evidence ($read.name+'-error.txt')
        $raw=az rest --method get --url $read.url --only-show-errors -o json 2> $errPath
        $exitCode=$LASTEXITCODE
        if ($exitCode -eq 0) {
            $obj=$raw | ConvertFrom-Json -ErrorAction Stop
            Save-LabEvidence ($read.name+'.json') $obj
            $status='READABLE; CONFIGURATION ONLY'
            $obj | ConvertTo-Json -Depth 8 | Write-Host
        } else { $status='UNAVAILABLE; INSPECT PRIVATE ERROR (NOT PROOF DISABLED)' }
        $script:R.graphReview += [pscustomobject]@{control=$read.name;status=$status}
        Save-LabRecord
        Write-Host ($read.name+': '+$status)
    }
    $script:R.humanControls='NOT LIVE-TESTED: provider-owned tenant; no CA/MFA/PIM configuration or activation changes'
    Save-LabRecord
    Write-Host 'Read-only availability review saved. Continue with exact workload grant revocation.'
}
function Test-Day12Revocation {
    Assert-LabWork
    if (-not $script:R.day12Started) { throw 'Run Day 12 review gate first.' }
    $null=Confirm-LabVault
    $events=@(Get-LabEvents)
    $last=$events | Select-Object -Last 1
    $nowEpoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $last -or $last.result -ne 'ALLOW_VERIFIED' -or $nowEpoch-$last.epoch -gt 60) { throw 'Need a fresh successful read from the unchanged workload before removing access. Inspect logs; do not recreate anything.' }
    if ($script:R.revokedUtc) { throw 'Revocation already attempted; use Wait-Day12Revocation without another mutation.' }
    $script:R.revokeAfterSeq=$last.seq; Save-LabRecord
    Remove-LabGrant 'workload-read'
    # Events must occur AFTER control-plane absence was verified, not merely after an earlier denial.
    $script:R.revokedUtc=[DateTimeOffset]::UtcNow.ToString('o'); Save-LabRecord
    Wait-Day12Revocation
}
function Wait-Day12Revocation {
    Assert-LabWork
    if (-not $script:R.revokedUtc) { throw 'No verified grant-removal checkpoint exists.' }
    $end=Get-LabLimit -Minutes 12
    $after=([DateTimeOffset]$script:R.revokedUtc).ToUnixTimeMilliseconds()/1000.0
    do {
        Assert-LabWork
        $events=@(Get-LabEvents)
        $denied=@($events | Where-Object { $_.result -eq 'DENIED' -and $_.seq -gt $script:R.revokeAfterSeq -and $_.epoch -gt $after })
        if ($denied.Count) {
            $null=Confirm-LabVault
            # Workload only GETs; no secret deletion/disable/update was performed during this experiment.
            $script:R.day12='REVOCATION PROOF COMPLETE; HUMAN CONTROL TESTS BLOCKED'; Save-LabRecord
            Write-Host 'PASS: exact grant absent, SAME workload now HTTP403 ForbiddenByRbac, vault still active.'
            Write-Host 'Day12 overall PARTIAL: tenant-control live testing was not performed in Whizlabs.'; return
        }
        Start-Sleep -Seconds 15
    } while ([DateTimeOffset]::UtcNow -lt $end)
    $script:R.day12='PARTIAL: assignment absent; data-plane denial not observed within window'; Save-LabRecord
    Write-Warning 'Revocation propagation window expired. Do not broaden/regrant, refresh by recreating identity, or delete secret to manufacture a denial. Start cleanup.'
}
function Inspect-LabRecovery {
    Assert-LabOperator
    foreach ($kind in @('vault','aci')) {
        try { $o=Get-LabObject $kind; Save-LabEvidence ($kind+'-recovery-inspection.json') $o; Write-Host ($kind+': exact owned fixture present = '+[bool]$o) }
        catch { Write-Warning $_.Exception.Message }
    }
    # This may be forbidden at subscription scope. Failure is UNKNOWN, never 'not found'.
    $raw=az keyvault show-deleted --name $script:R.vault.name --location $script:R.location --subscription $script:R.subscription --only-show-errors -o json 2> (Join-Path $script:Evidence 'deleted-inspection-error.txt')
    if ($LASTEXITCODE -eq 0) {
        $deleted=$raw | ConvertFrom-Json -ErrorAction Stop
        Save-LabEvidence 'deleted-vault-inspection.json' $deleted
        Write-Host ('Deleted-vault original ID matches recorded target = '+($deleted.properties.vaultId -ieq $script:R.vault.id))
    } else { Write-Warning 'Deleted-vault state UNKNOWN. Inspect private error. Do not recover/adopt/purge or generate replacement names.' }
    foreach ($g in $script:R.grants) {
        try {
            $rows=@(Invoke-LabAz @('role','assignment','list','--scope',$g.scope,'--fill-principal-name','false'))
            Save-LabEvidence ($g.label+'-recovery-inspection.json') @($rows | Where-Object id -IEQ $g.id)
        } catch { Write-Warning $_.Exception.Message }
    }
}
function Invoke-LabCleanup {
    # Cleanup intentionally bypasses work cutoffs; context/ownership checks remain mandatory.
    Assert-LabOperator
    $script:R.cleanupVerified=$false; $script:R.aci.absent=$false; $script:R.vault.absent=$false
    Save-LabRecord
    $problems=[Collections.Generic.List[string]]::new()
    foreach ($g in @($script:R.grants)) {
        try { Remove-LabGrant $g.label } catch { $problems.Add($_.Exception.Message) }
    }
    $end=[DateTimeOffset]::UtcNow.AddMinutes(5)
    if ($end -gt [DateTimeOffset]$script:R.expiresUtc) { $end=[DateTimeOffset]$script:R.expiresUtc }
    do {
        foreach ($kind in @('aci','vault')) {
            try {
                $fixture=$script:R.$kind
                $fixture.absent=$false; Save-LabRecord
                # A successful exact inventory read is required. A CLI error is never absence.
                $obj=Get-LabObject $kind
                if ($obj) {
                    if ($kind -eq 'vault' -and @($script:R.grants | Where-Object { -not $_.absent }).Count) { throw 'Keep vault until exact grants are verified absent; ACI containment cleanup still proceeds.' }
                    $fixture.deleteRequested=$true; Save-LabRecord
                    if ($kind -eq 'aci') {
                        Invoke-LabAz @('container','delete','-g',$script:R.rg,'-n',$fixture.name,'--yes','--no-wait') | Out-Null
                    } else {
                        Invoke-LabAz @('keyvault','delete','-g',$script:R.rg,'-n',$fixture.name,'--no-wait') | Out-Null
                    }
                } elseif (-not $fixture.attempted -or $fixture.deleteRequested) {
                    $fixture.absent=$true
                } else {
                    $problems.Add($kind+': uncertain create has never been settled by deletion; empty inventory alone is insufficient. Continue exact-target inspection; no new names.')
                }
                Save-LabRecord
            } catch { $problems.Add($_.Exception.Message) }
        }
        if ($script:R.aci.absent -and $script:R.vault.absent) { break }
        Start-Sleep -Seconds 15
    } while ([DateTimeOffset]::UtcNow -lt $end)
    if ($script:R.vault.deleteRequested -and $script:R.vault.absent) {
        $raw=az keyvault show-deleted --name $script:R.vault.name --location $script:R.location --subscription $script:R.subscription --only-show-errors -o json 2> (Join-Path $script:Evidence 'deleted-vault-error.txt')
        if ($LASTEXITCODE -eq 0) {
            $deleted=$raw | ConvertFrom-Json -ErrorAction Stop
            Save-LabEvidence 'soft-deleted-vault.json' $deleted
            if ($deleted.properties.vaultId -ieq $script:R.vault.id) { $script:R.softDelete='MATCHING SOFT-DELETED VAULT RETAINED; NO PURGE' }
            else { $script:R.softDelete='UNEXPECTED DELETED VAULT ID; INVESTIGATE' }
        } else { $script:R.softDelete='ACTIVE VAULT ABSENT; DELETED-VAULT DETAILS UNVERIFIED (SEE PRIVATE ERROR)' }
    }
    $script:R.cleanupVerified=($script:R.aci.absent -and $script:R.vault.absent -and @($script:R.grants | Where-Object { -not $_.absent }).Count -eq 0)
    if ($script:R.cleanupVerified -and $script:R.day11 -eq 'PROOF COMPLETE; CLEANUP PENDING') { $script:R.day11='COMPLETE' }
    Save-LabRecord
    Save-LabEvidence 'cleanup-problems.json' @($problems)
    [pscustomobject]@{ExactGrantsAbsent=(@($script:R.grants | Where-Object { -not $_.absent }).Count -eq 0);AciAbsent=$script:R.aci.absent;ActiveVaultAbsent=$script:R.vault.absent;CleanupVerified=$script:R.cleanupVerified;SoftDelete=$script:R.softDelete} | Format-List
    if (-not $script:R.cleanupVerified) { Write-Warning 'CLEANUP INCOMPLETE. Inspect-LabRecovery, then rerun cleanup of these SAME recorded targets before expiry.' }
    $problems | ForEach-Object { Write-Warning $_ }
}
