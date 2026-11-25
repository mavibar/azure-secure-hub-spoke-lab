[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day50-20261125'))
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$false
$c=Import-Clixml -LiteralPath "$CaseFolder/context.xml"
$env:AZURE_CONFIG_DIR=$c.CliConfig
function Invoke-ReviewAz { & az @args; if($LASTEXITCODE -ne 0){throw 'Azure read failed. Record BLOCKED; do not change permissions or deploy resources.'} }
$account=Invoke-ReviewAz account show -o json | ConvertFrom-Json -DateKind String
if($account.id -ne $c.Subscription -or $account.tenantId -ne $c.Tenant){throw 'Personal subscription context mismatch.'}
$d46=Import-Clixml -LiteralPath "$($c.Day46)/context.xml"
$d48=Import-Clixml -LiteralPath "$($c.Day48)/context.xml"
foreach($prior in @($d46,$d48)){if($prior.Subscription -ne $c.Subscription -or $prior.Tenant -ne $c.Tenant){throw 'Previous lesson context mismatch.'}}
Write-Host 'Personal subscription verified. Day50 is read-only in Azure; deleted lesson groups are expected.'
