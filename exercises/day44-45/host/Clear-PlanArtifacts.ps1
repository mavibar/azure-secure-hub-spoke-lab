[CmdletBinding()]
param([Parameter(Mandatory)][string]$CaseFolder)
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$false
$x=Import-Clixml -LiteralPath (Join-Path $CaseFolder 'execution.xml'); $c=$x.Original
$env:AZURE_CONFIG_DIR=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AzureCloudSecurityLab/personal-cli'
$a=az account show -o json | ConvertFrom-Json -DateKind String
if($LASTEXITCODE -ne 0 -or $a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Wrong or unavailable Azure context.'}
$payload=@{client=$x.ApplyClient;storage=$c.Storage;container=$c.Container} | ConvertTo-Json -Compress
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$script=@'
set -eu
python3 - <<'PY'
import base64,json,os,re,subprocess,tempfile
p=json.loads(base64.b64decode('PAYLOAD'))
with tempfile.TemporaryDirectory(prefix='csl-plan-cleanup-') as t:
 env=os.environ.copy();env['AZURE_CONFIG_DIR']=t
 def az(*args):
  r=subprocess.run(['az',*args],env=env,capture_output=True,text=True,timeout=90)
  if r.returncode: raise RuntimeError('Private cleanup read failed')
  return json.loads(r.stdout) if r.stdout.strip() else None
 az('login','--identity','--client-id',p['client'],'-o','none')
 scope=['--account-name',p['storage'],'--container-name',p['container'],'--auth-mode','login','--only-show-errors']
 lease=az('storage','blob','show',*scope,'--name','day42-43.tfstate','-o','json')
 if lease['properties']['lease']['status']!='unlocked': raise RuntimeError('Backend is not verified unlocked')
 plans=az('storage','blob','list',*scope,'--prefix','plans/','-o','json')
 if any(not re.fullmatch(r'plans/\d+-\d+/review\.tfplan',item['name']) for item in plans): raise RuntimeError('Unknown artifact names; inspect privately')
 for item in plans: az('storage','blob','delete',*scope,'--name',item['name'],'--delete-snapshots','include','-o','none')
 remaining=az('storage','blob','list',*scope,'--prefix','plans/','-o','json')
 if remaining: raise RuntimeError('Current plan blobs remain')
 print('CSL_ARTIFACT_CLEANUP_PASS: backend unlocked; current plan blobs absent; state retained')
PY
'@
$path=Join-Path $CaseFolder 'clear-plan-artifacts.sh'
$script.Replace('PAYLOAD',$encoded).Replace("`r`n","`n") | Set-Content -LiteralPath $path -Encoding utf8
$raw=az vm run-command invoke -g $x.RG -n vm-apply --command-id RunShellScript --scripts "@$path" --subscription $c.Subscription -o json
if($LASTEXITCODE -ne 0){throw 'Remote cleanup failed. Do not infer that an active VM operation was canceled.'}
$raw | Set-Content -LiteralPath (Join-Path $CaseFolder 'artifact-cleanup-private.json') -Encoding utf8
$r=$raw | ConvertFrom-Json -DateKind String
if(($r.value.message -join "`n") -notmatch 'CSL_ARTIFACT_CLEANUP_PASS:'){throw 'Plan cleanup not verified; inspect private result.'}
Write-Output 'Backend lease verified unlocked; current plan blobs absent; state retained. Soft-deleted versions may remain under account retention.'
