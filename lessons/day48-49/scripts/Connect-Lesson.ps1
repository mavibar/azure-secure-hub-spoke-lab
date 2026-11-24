[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day48-49-20261124'))
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
function Invoke-LessonAz { & az @args; if($LASTEXITCODE -ne 0){throw 'Azure command failed. Preserve this case; do not create replacement IDs.'} }
$c=Import-Clixml -LiteralPath "$CaseFolder/context.xml"
$env:AZURE_CONFIG_DIR=$c.CliConfig
$a=Invoke-LessonAz account show -o json | ConvertFrom-Json -DateKind String
if($a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Wrong Azure context.'}
if($c.Run -notmatch '^d48-[a-f0-9]{8}$' -or $c.RG -ne "rg-csl-private-$($c.Run)"){throw 'Invalid saved fixture boundary.'}
$group=Invoke-LessonAz group show -n $c.RG --subscription $c.Subscription -o json | ConvertFrom-Json -DateKind String
if($group.tags.labRun -ne $c.Run){throw 'Ownership mismatch.'}
Write-Host 'Personal subscription and lesson ownership verified. Keep this PowerShell window open.'
