# Dot-source this file so the verified context remains in your current terminal.
# This script changes local CLI/session settings and reads Azure. It deploys nothing.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedUsername,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$OwnerAlias,

    [switch]$ForceLogin
)

$LabContextReady = $false
$Account = $null
$LabGroup = $null
$LabScope = $null
$ResourceGroupName = $ResourceGroupName.Trim()
$ExpectedUsername = $ExpectedUsername.Trim()
$OwnerAlias = $OwnerAlias.Trim()
if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -or [string]::IsNullOrWhiteSpace($ExpectedUsername)) {
    throw 'Current resource group and Whizlabs username are required.'
}
if ([string]::IsNullOrWhiteSpace($OwnerAlias) -or $OwnerAlias.Length -gt 64) {
    throw 'Owner alias must contain 1-64 characters.'
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Open the terminal where az is installed.'
}

# Set the cache location BEFORE checking or starting authentication.
$env:AZURE_CONFIG_DIR = Join-Path $env:LOCALAPPDATA 'AzureCloudSecurityLab\cli'
New-Item -ItemType Directory -Force -Path $env:AZURE_CONFIG_DIR -ErrorAction Stop | Out-Null

$CachedAccountJson = az account show --only-show-errors --output json
$CachedAccountExit = $LASTEXITCODE
$CachedAccount = $null
if ($CachedAccountExit -eq 0) {
    $CachedAccount = $CachedAccountJson | ConvertFrom-Json -ErrorAction Stop
}

if ($ForceLogin -or $CachedAccountExit -ne 0 -or $CachedAccount.user.name -ine $ExpectedUsername -or $CachedAccount.user.type -ne 'user') {
    az config set core.enable_broker_on_windows=false --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Unable to configure the dedicated lab CLI cache.' }
    az login --use-device-code --output none
    if ($LASTEXITCODE -ne 0) { throw 'Sign-in failed.' }
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Current sandbox subscription selection failed.' }
$AccountJson = az account show --only-show-errors --output json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read current Azure CLI account.' }
$Account = $AccountJson | ConvertFrom-Json -ErrorAction Stop
if ($Account.id -ine $SubscriptionId -or $Account.user.name -ine $ExpectedUsername -or $Account.user.type -ne 'user' -or [string]::IsNullOrWhiteSpace($Account.tenantId)) {
    throw 'Account does not match the supplied sandbox identity. Rerun with -ForceLogin and the current Whizlabs username.'
}

$LabGroupJson = az group show --subscription $Account.id --name $ResourceGroupName --only-show-errors --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot read the current sandbox RG. Verify its name/session expiry. If authentication expired, rerun with -ForceLogin.'
}
$LabGroup = $LabGroupJson | ConvertFrom-Json -ErrorAction Stop
$LabScope = [string]$LabGroup.id
$ExpectedRgId = "/subscriptions/$($Account.id)/resourceGroups/$ResourceGroupName"
if ($LabScope -ine $ExpectedRgId -or $LabGroup.name -ine $ResourceGroupName) {
    throw 'Returned resource group does not match the requested sandbox scope.'
}

# These are runtime inputs only. No password or username is written into Terraform.
$env:TF_VAR_subscription_id = $Account.id
$env:TF_VAR_tenant_id = $Account.tenantId
$env:TF_VAR_resource_group_name = $LabGroup.name
$env:TF_VAR_project_name = 'secureapp'
$env:TF_VAR_environment = 'dev'
$env:TF_VAR_owner = $OwnerAlias
$env:TF_VAR_enable_test_hosts = 'false'
$LabContextReady = $true

[pscustomobject]@{
    User = $Account.user.name
    Subscription = $Account.id
    Tenant = $Account.tenantId
    ResourceGroup = $LabGroup.name
    Scope = $LabScope
    OwnerAlias = $OwnerAlias
    ContextReady = $LabContextReady
}
Write-Host 'Verified current lab context. Terraform workspace was not selected or changed.'

