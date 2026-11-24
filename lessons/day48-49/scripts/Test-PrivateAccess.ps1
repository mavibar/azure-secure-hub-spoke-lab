[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day48-49-20261124'),[switch]$Seed)
. "$PSScriptRoot/Connect-Lesson.ps1" -CaseFolder $CaseFolder
$dns=@(Resolve-DnsName "$($c.Storage).blob.core.windows.net" -Type A -DnsOnly -ErrorAction Stop | Where-Object Type -eq A)
if(-not $dns.Count){throw 'Host public DNS lookup failed.'}
if($dns.IPAddress -contains $c.PrivateIP){throw 'Host resolves the private endpoint; it is not a valid external test origin.'}
$cfg=@{storage=$c.Storage;private_ip=$c.PrivateIP;seed=[bool]$Seed} | ConvertTo-Json -Compress
$code=[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PSScriptRoot/probe.py"))
$config=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cfg))
$shell="python3 - '$config' <<'PY'`nimport base64,sys`nsys.argv=[sys.argv[0],base64.b64decode(sys.argv[1]).decode()]`nexec(compile(base64.b64decode('$code'),'<lesson-probe>','exec'))`nPY"
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$shell | Set-Content "$CaseFolder/probe-$stamp.sh" -Encoding utf8
# Intent saved before Run Command. The only data write is the explicitly selected dummy seed.
@{Utc=$stamp;VM=$c.VM;Seed=[bool]$Seed;PrivateIP=$c.PrivateIP;PublicIP=$dns[0].IPAddress} | Export-Clixml "$CaseFolder/probe-intent-$stamp.xml"
$raw=Invoke-LessonAz vm run-command invoke -g $c.RG -n $c.VM --subscription $c.Subscription --command-id RunShellScript --scripts "@$CaseFolder/probe-$stamp.sh" -o json
$raw | Set-Content "$CaseFolder/probe-result-$stamp.json" -Encoding utf8
$r=$raw | ConvertFrom-Json -Depth 20 -DateKind String
$line=(@($r.value.message) -join "`n") -split "`n" | Where-Object {$_ -like 'CSL_RESULT=*'} | Select-Object -Last 1
if(-not $line){throw "Guest result absent; inspect the private result file. Do not change network rules."}
$test=$line.Substring(11) | ConvertFrom-Json -Depth 12 -DateKind String
if(-not $test.pass){$test | Export-Clixml "$CaseFolder/latest-test.xml"; throw 'Private read failed. Preserve evidence; do not broaden access.'}
# External reader is the existing signed-in user. Entra commands reject --subscription.
$user=& az ad signed-in-user show -o json | ConvertFrom-Json -DateKind String
if($LASTEXITCODE -ne 0 -or $user.id -ne $c.ReviewerPrincipal){throw 'External reviewer identity mismatch.'}
$assignment=Invoke-LessonAz rest --url "https://management.azure.com$($c.ReviewerRoleId)?api-version=2022-04-01" -o json | ConvertFrom-Json
if($assignment.properties.scope -ine $c.ContainerId -or $assignment.properties.principalId -ne $user.id -or $assignment.properties.roleDefinitionId -notlike '*/2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'){throw 'External data-reader assignment mismatch.'}
$s=Invoke-LessonAz storage account show -g $c.RG -n $c.Storage --subscription $c.Subscription -o json | ConvertFrom-Json
if($s.publicNetworkAccess -ne 'Disabled'){throw 'Public access configuration drift.'}
# The token stays in memory. Never print it or write the request headers to evidence.
$access=Invoke-LessonAz account get-access-token --resource https://storage.azure.com/ --subscription $c.Subscription -o json | ConvertFrom-Json
try {
 $response=Invoke-WebRequest -Uri "https://$($c.Storage).blob.core.windows.net/lesson/dummy.txt" -Headers @{Authorization=('Bearer '+$access.accessToken);'x-ms-version'='2023-11-03'} -SkipHttpErrorCheck -TimeoutSec 25
 $errorCode=$null
 if([int]$response.StatusCode -ge 400){$errorCode=([xml]$response.Content.TrimStart([char]0xfeff)).Error.Code}
 $outside=[ordered]@{origin='Host outside lesson VNet; existing signed-in user';status=[int]$response.StatusCode;error_code=$errorCode;request_id=($response.Headers['x-ms-request-id'] -join '');public_dns=@($dns.IPAddress);reader_assignment_verified=$true}
} finally { $access=$null }
$combined=[ordered]@{utc=(Get-Date).ToUniversalTime().ToString('o');private_vm=$test;external_host=$outside;public_network_access=$s.publicNetworkAccess;same_identity=$false;pass=($test.pass -and $outside.status -eq 403 -and $outside.error_code -eq 'AuthorizationFailure')}
$combined | Export-Clixml "$CaseFolder/latest-test.xml"
$combined | ConvertTo-Json -Depth 10
if(-not $combined.pass){throw 'Expected private allow/external deny pair was not established. No permission broadening.'}
