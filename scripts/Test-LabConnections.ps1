[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TerraformDirectory,
    [Parameter(Mandatory)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'

function Invoke-AzJson {
    param([string[]]$Arguments)
    $text = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0..1] -join ' ')" }
    return ($text -join "`n" | ConvertFrom-Json)
}

function Invoke-LabRunCommand {
    param([string]$VmName, [string]$Script, [string]$Label)
    $filePath = Join-Path $EvidenceDirectory "$Label.sh"
    # Linux needs LF endings. A script file also avoids nested CLI quoting.
    [IO.File]::WriteAllText($filePath, $Script.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    $response = Invoke-AzJson -Arguments @('vm', 'run-command', 'invoke', '--subscription', $account.id,
        '--resource-group', $resourceGroup, '--name', $VmName,
        '--command-id', 'RunShellScript', '--scripts', "@$filePath")
    $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "$Label.json")
    $message = @($response.value | ForEach-Object message) -join "`n"
    Write-Host $message
    return $message
}

New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
Push-Location -LiteralPath $TerraformDirectory
try {
    $outputText = & terraform output -json
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Terraform outputs.' }
    $outputs = ($outputText -join "`n") | ConvertFrom-Json
    $hostsByRole = $outputs.test_hosts.value
    $resourceGroup = $outputs.resource_group_name.value
    $account = Invoke-AzJson -Arguments @('account', 'show')
    if ($account.id -ne $env:TF_VAR_subscription_id -or $resourceGroup -ne $env:TF_VAR_resource_group_name) {
        throw 'CLI account, environment variables and selected Terraform state disagree.'
    }
    foreach ($role in @('management', 'web', 'app', 'data')) {
        $hostInfo = $hostsByRole.$role
        if (-not $hostInfo.vm_id -or -not $hostInfo.private_ip) { throw "Missing deployed host: $role" }
        $expectedPrefix = "/subscriptions/$($account.id)/resourceGroups/$resourceGroup/"
        if (-not $hostInfo.vm_id.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected subscription or resource group for $role."
        }
    }
    $hostsByRole | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'host-inventory.json')

    # Confirm every destination's listener before interpreting any failed connection.
    foreach ($role in @('management', 'web', 'app', 'data')) {
        $hostInfo = $hostsByRole.$role
        $port = [int]$hostInfo.port
        $healthScript = @"
set -eu
timeout 120 cloud-init status --wait
command -v python3
if [ $port -ne 0 ]; then
  systemctl is-active lab-listener.service
  /usr/bin/python3 - <<'PY'
import socket
with socket.create_connection(('127.0.0.1', $port), timeout=5) as s:
    reply = s.recv(128).decode('ascii').strip()
    assert reply == 'LAB_OK:$role', repr(reply)
PY
fi
ip -4 route
echo LAB_READY:$role
"@
        $message = Invoke-LabRunCommand -VmName $hostInfo.vm_name -Script $healthScript -Label "health-$role"
        if ($message -notmatch "(?m)^LAB_READY:$role\s*$") {
            throw "Health check did not complete for $role. Do not count connection failures as security successes."
        }
    }

    $matrix = @(
        @{ source = 'management'; destination = 'web'; expected = 'allow' },
        @{ source = 'web'; destination = 'app'; expected = 'allow' },
        @{ source = 'app'; destination = 'data'; expected = 'allow' },
        @{ source = 'web'; destination = 'data'; expected = 'deny' },
        @{ source = 'management'; destination = 'app'; expected = 'deny' },
        @{ source = 'management'; destination = 'data'; expected = 'deny' },
        @{ source = 'data'; destination = 'app'; expected = 'deny' }
    )
    $allResults = @()
    foreach ($source in @('management', 'web', 'app', 'data')) {
        $cases = @($matrix | Where-Object { $_.source -eq $source } | ForEach-Object {
            @{
                source = $_.source
                destination = $_.destination
                expected = $_.expected
                ip = $hostsByRole.($_.destination).private_ip
                port = [int]$hostsByRole.($_.destination).port
            }
        })
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $cases -Compress)))
        $probeScript = @"
set -eu
/usr/bin/python3 - <<'PY'
import base64, json, socket
cases = json.loads(base64.b64decode('$payload'))
for case in cases:
    result = dict(case)
    try:
        with socket.create_connection((case['ip'], case['port']), timeout=5) as connection:
            connection.settimeout(5)
            greeting = connection.recv(128).decode('ascii', errors='replace').strip()
            if greeting != 'LAB_OK:' + case['destination']:
                result.update(observed='connected_wrong_or_missing_listener', verdict='INCONCLUSIVE')
            else:
                result.update(observed='connected_to_expected_listener', verdict='PASS_ALLOW' if case['expected'] == 'allow' else 'FAIL_UNEXPECTED_ALLOW')
    except (TimeoutError, socket.timeout):
        result.update(observed='timeout', verdict='BLOCK_OBSERVED_NEEDS_RULE_CHECK' if case['expected'] == 'deny' else 'FAIL_EXPECTED_ALLOW')
    except OSError as error:
        result.update(observed=type(error).__name__ + ': ' + str(error), verdict='INCONCLUSIVE')
    print('LAB_RESULT:' + json.dumps(result, separators=(',', ':')), flush=True)
print('LAB_PROBES_COMPLETE')
PY
"@
        $message = Invoke-LabRunCommand -VmName $hostsByRole.$source.vm_name -Script $probeScript -Label "probe-$source"
        if ($message -notmatch '(?m)^LAB_PROBES_COMPLETE\s*$') { throw "Probe execution incomplete on $source." }
        $rows = @([regex]::Matches($message, '(?m)^LAB_RESULT:(\{[^\r\n]+\})') | ForEach-Object {
            $_.Groups[1].Value | ConvertFrom-Json
        })
        if ($rows.Count -ne $cases.Count) { throw "Missing probe results from $source." }
        $allResults += $rows
    }
    $allResults | Export-Csv -LiteralPath (Join-Path $EvidenceDirectory 'connection-results.csv') -NoTypeInformation
    $allResults | Format-Table source, destination, port, expected, observed, verdict -AutoSize
    Write-Host 'Timeouts are observations, not proof of NSG causation. Complete the runbook rule/route checks.'
    if (@($allResults | Where-Object { $_.verdict -match '^(FAIL|INCONCLUSIVE)' }).Count -gt 0) {
        throw 'At least one probe failed or is inconclusive. Inspect saved evidence before changing a rule.'
    }
}
finally {
    Pop-Location
}
