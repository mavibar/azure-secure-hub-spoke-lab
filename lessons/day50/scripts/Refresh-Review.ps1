# Read-only Azure collection. Runtime requests/results stay in the private case.
[CmdletBinding()]
param([string]$CaseFolder=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudSecurityLab/day50-20261125'))
. "$PSScriptRoot/Connect-Review.ps1" -CaseFolder $CaseFolder
$checked=(Get-Date).ToUniversalTime().ToString('o')
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$capture=Join-Path $CaseFolder $stamp
$null=New-Item -ItemType Directory -Path $capture
$cleanup=foreach($prior in @($d46,$d48)){
 $exists=Invoke-ReviewAz group exists --name $prior.RG --subscription $c.Subscription -o tsv
 if($exists -notin @('true','false')){throw 'Unrecognized existence response.'}
 $state=@(& terraform "-chdir=$($prior.Folder)/terraform" state list)
 if($LASTEXITCODE -ne 0){throw 'Could not read exact prior local state.'}
 [pscustomobject]@{Case=(Split-Path $prior.Folder -Leaf);RecordedStage=$prior.Stage;RecordedCleanupUtc=$prior.CleanupUtc;GroupExists=($exists -eq 'true');StateAddressCount=$state.Count;Verified=($exists -eq 'false' -and $state.Count -eq 0)}
}
$definitions=foreach($name in $d46.DefinitionNames){
 $text=& az policy definition show --name $name --subscription $c.Subscription -o json 2>&1
 $exitCode=$LASTEXITCODE
 $text | Out-String | Set-Content "$capture/definition-$name.txt"
 if($exitCode -eq 0){[pscustomobject]@{Name=$name;Absent=$false}}
 elseif(($text | Out-String) -match '\(PolicyDefinitionNotFound\)'){[pscustomobject]@{Name=$name;Absent=$true}}
 else{throw 'Definition absence could not be established; inspect the captured error.'}
}
$before=Import-Clixml "$($c.Day46)/student-before.xml"
$after=Import-Clixml "$($c.Day46)/student-after.xml"
$allowed=Get-Content "$($c.Day46)/student-allowed.json" -Raw | ConvertFrom-Json -DateKind String
if($allowed.NewNSG){$allowed=$allowed.NewNSG}
$denied=Get-Content "$($c.Day46)/student-denied.txt" -Raw
$states=@(Import-Clixml "$($c.Day46)/student-policy-states.xml")
$scoped=@($states | Where-Object {$_.policyAssignmentId -in @($d46.OwnerAssignment,$d46.LocationAssignment) -and $_.resourceId -in @($d46.ReferenceId,$d46.DriftId)})
$latest=@($scoped | Group-Object policyAssignmentId,resourceId | ForEach-Object {$_.Group | Sort-Object {[DateTimeOffset]$_.timestamp} -Descending | Select-Object -First 1})
if($latest.Count -ne 4){throw 'Expected four assignment/resource pairs. Do not infer missing compliance.'}
$policyRows=@($latest | Select-Object policyAssignmentName,@{n='resource';e={($_.resourceId -split '/')[-1]}},complianceState,timestamp)
$network=Import-Clixml "$($c.Day48)/latest-test.xml"
$queries=[ordered]@{}
foreach($name in @('01-current-inventory','02-retired-lesson-groups')){
 $query=Get-Content (Join-Path (Split-Path $PSScriptRoot) "queries/$name.kql") -Raw
 $body=@{subscriptions=@($c.Subscription);query=$query;options=@{resultFormat='objectArray';'$top'=1000}}
 $body | ConvertTo-Json -Depth 6 | Set-Content "$capture/$name-request.json" -Encoding utf8
 $raw=Invoke-ReviewAz rest --method post --url 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' --body "@$capture/$name-request.json" -o json
 $raw | Set-Content "$capture/$name-result.json" -Encoding utf8
 $result=$raw | ConvertFrom-Json -Depth 20 -DateKind String
 if($result.'$skipToken' -or $result.resultTruncated -eq 'true'){throw 'Query results truncated. Do not use partial inventory as complete.'}
 $queries[$name]=@($result.data)
}
$facts=[ordered]@{
 CheckedUtc=$checked
 Capture=$capture
 TagBeforeHasOwner=('Owner' -in $before.tags.PSObject.Properties.Name)
 TagAfterOwner=$after.tags.Owner
 AllowedProbeState=$allowed.provisioningState
 AllowedProbeLocation=$allowed.location
 AllowedProbeExact=($allowed.id -ieq "$($d46.RGId)/providers/Microsoft.Network/networkSecurityGroups/nsg-allowed-probe")
 ExactPolicyDenial=($denied -match 'RequestDisallowedByPolicy' -and $denied -match [regex]::Escape($d46.LocationAssignment))
 SavedPolicyRows=$states.Count
 LatestScopedPolicyRows=$policyRows
 NetworkTestUtc=$network.utc
 PrivateHttp=$network.private_vm.private.status
 ExternalHttp=$network.external_host.status
 ExternalCode=$network.external_host.error_code
 SameIdentity=$network.same_identity
 ExternalReaderAssignmentVerified=$network.external_host.reader_assignment_verified
 PublicNetworkAccess=$network.public_network_access
 NetworkRecordedPass=$network.pass
 Cleanup=@($cleanup)
 DefinitionAbsence=@($definitions)
 CurrentInventory=$queries['01-current-inventory']
 RetiredLessonGroups=$queries['02-retired-lesson-groups']
}
$facts | Export-Clixml "$capture/review-facts.xml"
$facts | Export-Clixml "$CaseFolder/latest-review.xml"
$facts | ConvertTo-Json -Depth 12 | Set-Content "$capture/review-facts.json" -Encoding utf8
Write-Host "Evidence refreshed: $capture"
$facts.Cleanup | Format-Table Case,GroupExists,StateAddressCount,Verified
$facts.DefinitionAbsence | Format-Table Name,Absent
$facts.LatestScopedPolicyRows | Format-Table -AutoSize
if(@($cleanup | Where-Object {-not $_.Verified}).Count -or @($definitions | Where-Object {-not $_.Absent}).Count){throw 'Cleanup discrepancy recorded. Stop and request exact recovery; no deletion was attempted.'}
