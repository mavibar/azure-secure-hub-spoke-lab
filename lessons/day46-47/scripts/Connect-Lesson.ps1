# Dot-source this once: . "<pack>/scripts/Connect-Lesson.ps1"
[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day46-47-20261123'))
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$c=Import-Clixml -LiteralPath (Join-Path $CaseFolder 'context.xml')
foreach($key in 'Subscription','Tenant','RG','Run','Allowed','Denied','Owner','DriftId','LocationAssignment'){
 if([string]::IsNullOrWhiteSpace([string]$c[$key])){throw "Incomplete recovery record: $key. Stop and return to the preparation chat."}
}
$caseFolder=$CaseFolder
$env:AZURE_CONFIG_DIR=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AzureCloudSecurityLab/personal-cli'
function Invoke-LessonAz { & az @args; if($LASTEXITCODE -ne 0){throw 'Azure command failed. Stop and keep the error; do not broaden permissions.'} }
$a=Invoke-LessonAz account show -o json | ConvertFrom-Json -DateKind String
if($a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Wrong Azure login. Stop; the lesson must use the saved personal account.'}
$g=Invoke-LessonAz group show -n $c.RG --subscription $c.Subscription -o json | ConvertFrom-Json -DateKind String
if($g.tags.labRun -ne $c.Run){throw 'Lab group ownership does not match.'}
[pscustomobject]@{Subscription=$a.name;ResourceGroup=$c.RG;AllowedRegion=$c.Allowed;DeniedTestRegion=$c.Denied;RequiredOwner=$c.Owner} | Format-List
Write-Output 'Context verified. Keep this PowerShell window open; $c holds the saved lesson settings.'
