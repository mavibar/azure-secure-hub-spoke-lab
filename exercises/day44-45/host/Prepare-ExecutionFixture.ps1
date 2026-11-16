[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('Initialize','Network','Identities','VMs','Roles','Trust','Inspect')][string]$Step,
 [Parameter(Mandatory)][string]$CaseFolder,
 [string]$Day42ContextPath,
 [string]$RepositoryPath='C:\git\azure-secure-hub-spoke-lab-d44-45',
 [string]$ApplySubject,
 [switch]$ResumeAfterReview
)
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
function AzChecked { & az @args; if($LASTEXITCODE -ne 0){throw 'Azure command failed. Preserve this case and inspect before retrying.'} }
function JsonAz { AzChecked @args --output json | ConvertFrom-Json -DateKind String }
$env:AZURE_CONFIG_DIR=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AzureCloudSecurityLab/personal-cli'
$file=Join-Path $CaseFolder 'execution.xml'
if($Step -eq 'Initialize'){
 if(Test-Path -LiteralPath $CaseFolder){throw 'Case folder already exists. Resume its record; do not overwrite.'}
 $c=Import-Clixml -LiteralPath $Day42ContextPath
 $a=JsonAz account show
 if($a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Select the recorded personal Azure account first.'}
 $identity=JsonAz identity show --ids $c.IdentityId
 if($identity.principalId -ne $c.PrincipalId){throw 'Original identity changed.'}
 $storage=JsonAz storage account show --ids $c.StorageId
 if($storage.networkRuleSet.defaultAction -ne 'Deny' -or $storage.allowSharedKeyAccess -ne $false){throw 'Storage protection changed.'}
 $run='d44-'+[guid]::NewGuid().ToString('N').Substring(0,8)
 $x=[ordered]@{Run=$run;Original=$c;Folder=$CaseFolder;Region=$storage.location;RG="rg-csl-exec-$run";Size='Standard_B2als_v2';Image='Canonical:ubuntu-24_04-lts:server:24.04.202610250';VNet='vnet-exec';Subnet='exec';NSG='nsg-exec';ApplyIdentity='id-apply';Completed=@('Initialize');Intent='';CommandRole=[guid]::NewGuid().ToString();WriterRole=[guid]::NewGuid().ToString();Assignments=@();ApplySubject=''}
 $x.RGId="/subscriptions/$($c.Subscription)/resourceGroups/$($x.RG)"
 $x.SubnetId="$($x.RGId)/providers/Microsoft.Network/virtualNetworks/$($x.VNet)/subnets/$($x.Subnet)"
 $x.ApplyIdentityId="$($x.RGId)/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$($x.ApplyIdentity)"
 $x.VMs=@('plan','apply')
 foreach($side in $x.VMs){$x["${side}VMId"]="$($x.RGId)/providers/Microsoft.Compute/virtualMachines/vm-$side"}
 foreach($row in @(@('plan-reader',$c.ReaderGuid,$c.RGId,'acdd72a7-3385-48ef-bd42-f606fba81ae7'),@('plan-blob',$c.BlobGuid,$c.ContainerId,'ba92f5b4-2d11-453d-a403-e96b0029c9fe'),@('plan-command',[guid]::NewGuid().ToString(),$x.planVMId,$x.CommandRole),@('apply-reader',[guid]::NewGuid().ToString(),$c.RGId,'acdd72a7-3385-48ef-bd42-f606fba81ae7'),@('apply-blob',[guid]::NewGuid().ToString(),$c.ContainerId,'ba92f5b4-2d11-453d-a403-e96b0029c9fe'),@('apply-command',[guid]::NewGuid().ToString(),$x.applyVMId,$x.CommandRole),@('apply-writer',[guid]::NewGuid().ToString(),$c.RGId,$x.WriterRole))){$x.Assignments+=@{Label=$row[0];Guid=$row[1];Scope=$row[2];Role=$row[3];Id="$($row[2])/providers/Microsoft.Authorization/roleAssignments/$($row[1])"}}
 $null=New-Item -ItemType Directory -Path $CaseFolder
 $storage | Export-Clixml -LiteralPath (Join-Path $CaseFolder 'storage-before.xml')
 $x | Export-Clixml -LiteralPath $file
 Write-Output "Intent saved: $file"; return
}
$x=Import-Clixml -LiteralPath $file; $c=$x.Original
$a=JsonAz account show
if($a.id -ne $c.Subscription -or $a.tenantId -ne $c.Tenant){throw 'Wrong Azure context.'}
if($Step -ne 'Inspect'){
 if($x.Completed -contains $Step){throw 'Step already recorded complete. Inspect before making a new change.'}
 if($x.Intent -and -not $ResumeAfterReview){throw "Previous step $($x.Intent) is uncertain. Inspect its exact recorded resources before using -ResumeAfterReview."}
 $x.Intent=$Step; $x | Export-Clixml -LiteralPath $file
}
switch($Step){
 'Network' {
  if((Read-Host 'Type CREATE to authorize the temporary network and subsequent billable fixture') -cne 'CREATE'){throw 'Not approved.'}
  if((AzChecked group exists --name $x.RG --subscription $c.Subscription -o tsv) -eq 'true'){
   $g=JsonAz group show --name $x.RG --subscription $c.Subscription
   if($g.tags.labRun -ne $x.Run -or -not $ResumeAfterReview){throw 'Existing group requires exact ownership review.'}
  }else{AzChecked group create -n $x.RG -l $x.Region --subscription $c.Subscription --tags "labRun=$($x.Run)" --output none}
  AzChecked network nsg create -g $x.RG -n $x.NSG -l $x.Region --subscription $c.Subscription --tags "labRun=$($x.Run)" -o none
  AzChecked network nsg rule create -g $x.RG --nsg-name $x.NSG -n DenyAllInbound --priority 100 --direction Inbound --access Deny --protocol '*' --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges '*' --subscription $c.Subscription -o none
  AzChecked network vnet create -g $x.RG -n $x.VNet -l $x.Region --address-prefixes '10.44.0.0/24' --subnet-name $x.Subnet --subnet-prefixes '10.44.0.0/27' --subscription $c.Subscription --tags "labRun=$($x.Run)" -o none
  AzChecked network vnet subnet update -g $x.RG --vnet-name $x.VNet -n $x.Subnet --service-endpoints Microsoft.Storage --network-security-group $x.NSG --subscription $c.Subscription -o none
  AzChecked storage account network-rule add --account-name $c.Storage --resource-group $c.StorageRG --subnet $x.SubnetId --subscription $c.Subscription -o none
 }
 'Identities' {
  if($x.Completed -notcontains 'Network'){throw 'Network step is not complete.'}
  AzChecked identity create -g $x.RG -n $x.ApplyIdentity -l $x.Region --subscription $c.Subscription --tags "labRun=$($x.Run)" -o none
  $i=JsonAz identity show --ids $x.ApplyIdentityId
  $x.ApplyClient=$i.clientId; $x.ApplyPrincipal=$i.principalId
 }
 'VMs' {
  if($x.Completed -notcontains 'Identities'){throw 'Identity step is not complete.'}
  $key=Join-Path $CaseFolder 'executor-key'
  if(-not(Test-Path -LiteralPath "$key.pub")){
   & ssh-keygen -t ed25519 -N '' -f $key -C 'disposable-executor' -q
   if($LASTEXITCODE -ne 0){throw 'SSH public-key preparation failed.'}
  }
  $public=(Get-Content -Raw -LiteralPath "$key.pub").Trim()
  foreach($side in $x.VMs){
   AzChecked network public-ip create -g $x.RG -n "pip-$side" -l $x.Region --sku Standard --allocation-method Static --subscription $c.Subscription --tags "labRun=$($x.Run)" -o none
   AzChecked network nic create -g $x.RG -n "nic-$side" -l $x.Region --subnet $x.SubnetId --network-security-group $x.NSG --public-ip-address "pip-$side" --subscription $c.Subscription --tags "labRun=$($x.Run)" -o none
   $mi=if($side -eq 'plan'){$c.IdentityId}else{$x.ApplyIdentityId}
   $existing=@(JsonAz vm list -g $x.RG --subscription $c.Subscription | Where-Object name -eq "vm-$side")
   if($existing.Count){if(-not $ResumeAfterReview -or $existing[0].tags.labRun -ne $x.Run -or $existing[0].provisioningState -ne 'Succeeded'){throw 'VM exists; inspect provisioning and identity before retrying.'}; continue}
   AzChecked vm create -g $x.RG -n "vm-$side" -l $x.Region --nics "nic-$side" --image $x.Image --size $x.Size --admin-username labexec --authentication-type ssh --ssh-key-values $public --assign-identity $mi --os-disk-name "os-$side" --storage-sku Standard_LRS --os-disk-delete-option Delete --nic-delete-option Delete --security-type TrustedLaunch --enable-vtpm true --enable-secure-boot true --custom-data "$RepositoryPath/exercises/day44-45/bootstrap-cloud-init.yml" --subscription $c.Subscription --tags "labRun=$($x.Run)" -o none
  }
 }
 'Roles' {
  if($x.Completed -notcontains 'VMs'){throw 'VM creation is not complete.'}
  $defs=@(@{Name="CSL Command $($x.Run)";Id=$x.CommandRole;IsCustom=$true;Description='Invoke commands only on assigned disposable executor VM';Actions=@('Microsoft.Compute/virtualMachines/read','Microsoft.Compute/virtualMachines/runCommand/action');NotActions=@();DataActions=@();NotDataActions=@();AssignableScopes=@($x.RGId)},@{Name="CSL NSG $($x.Run)";Id=$x.WriterRole;IsCustom=$true;Description='Only NSG lifecycle in the dedicated CI lab group';Actions=@('Microsoft.Network/networkSecurityGroups/read','Microsoft.Network/networkSecurityGroups/write','Microsoft.Network/networkSecurityGroups/delete');NotActions=@();DataActions=@();NotDataActions=@();AssignableScopes=@($c.RGId)})
  foreach($def in $defs){
   $path=Join-Path $CaseFolder ($def.Id+'.json')
   $body=@{properties=@{roleName=$def.Name;description=$def.Description;type='CustomRole';permissions=@(@{actions=$def.Actions;notActions=@();dataActions=@();notDataActions=@()});assignableScopes=$def.AssignableScopes}}
   $body | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
   $existing=@(JsonAz role definition list --custom-role-only true --subscription $c.Subscription | Where-Object id -like "*/$($def.Id)")
   if($existing.Count){
    if(-not $ResumeAfterReview -or @(Compare-Object @($existing[0].permissions.actions) @($def.Actions)).Count -or @(Compare-Object @($existing[0].assignableScopes) @($def.AssignableScopes)).Count -or @($existing[0].permissions.dataActions).Count){throw 'Existing custom role requires exact permission review.'}
   }else{
    $url="https://management.azure.com/subscriptions/$($c.Subscription)/providers/Microsoft.Authorization/roleDefinitions/$($def.Id)?api-version=2022-04-01"
    AzChecked rest --method put --url $url --body "@$path" -o none
   }
  }
  foreach($assignment in $x.Assignments){
   $principal=if($assignment.Label -like 'plan-*'){$c.PrincipalId}else{$x.ApplyPrincipal}
   $existing=@(JsonAz role assignment list --scope $assignment.Scope --fill-principal-name false --subscription $c.Subscription | Where-Object id -eq $assignment.Id)
   if($existing.Count){if($existing[0].principalId -ne $principal -or $existing[0].roleDefinitionId -notlike "*/$($assignment.Role)"){throw 'Role assignment collision.'}; continue}
   AzChecked role assignment create --name $assignment.Guid --assignee-object-id $principal --assignee-principal-type ServicePrincipal --role $assignment.Role --scope $assignment.Scope --subscription $c.Subscription -o none
  }
 }
 'Trust' {
  if($x.Completed -notcontains 'Roles'){throw 'Roles are not complete.'}
  if([string]::IsNullOrWhiteSpace($ApplySubject) -or $ApplySubject -notlike '*csl-apply*'){throw 'Supply the exact observed apply-environment subject.'}
  $x.ApplySubject=$ApplySubject; $x | Export-Clixml -LiteralPath $file
  foreach($trust in @(@{Identity=$c.Identity;RG=$c.RG;Name=$c.Federation;Subject=$c.Subject},@{Identity=$x.ApplyIdentity;RG=$x.RG;Name='github-apply';Subject=$x.ApplySubject})){
   $old=@(JsonAz identity federated-credential list --identity-name $trust.Identity -g $trust.RG --subscription $c.Subscription | Where-Object name -eq $trust.Name)
   if($old.Count){if($old[0].subject -ne $trust.Subject -or $old[0].issuer -ne 'https://token.actions.githubusercontent.com' -or @($old[0].audiences).Count -ne 1 -or $old[0].audiences[0] -ne 'api://AzureADTokenExchange'){throw 'Federation collision.'};continue}
   AzChecked identity federated-credential create --identity-name $trust.Identity -g $trust.RG -n $trust.Name --issuer 'https://token.actions.githubusercontent.com' --subject $trust.Subject --audiences 'api://AzureADTokenExchange' --subscription $c.Subscription -o none
  }
 }
 'Inspect' {
  AzChecked resource list -g $x.RG --subscription $c.Subscription --query '[].{name:name,type:type}' -o table
  AzChecked storage account network-rule list -g $c.StorageRG --account-name $c.Storage --subscription $c.Subscription -o json
  foreach($principal in @($c.PrincipalId,$x.ApplyPrincipal)){if($principal){AzChecked role assignment list --assignee-object-id $principal --all --fill-principal-name false --subscription $c.Subscription --query '[].{role:roleDefinitionName,scope:scope}' -o table}}
  return
 }
}
$x.Completed+=@($Step); $x.Intent=''; $x | Export-Clixml -LiteralPath $file
Write-Output "$Step recorded complete. Verify its readback in the runbook."
