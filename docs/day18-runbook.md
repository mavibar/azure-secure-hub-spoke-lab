# Day 18 — Prepare Commvault TLS and replace the validation client

**October 5, 2026 · HOST: elevated, 64-bit PowerShell 7.6.6 · Commvault: reported 11.36.72**

## Today's finish line

Replace the unstable evaluation client, prove the existing PKI from that replacement, and prepare an exact Commvault certificate change with recoverable configuration. **Day 19 performs the Commvault certificate issuance and binding.** Your PKI WEB already has TLS; it passed Days 16 and 17. Today connects that knowledge to the application that will use it.

Day 17's saved result and private completion flags confirm the correct-name / wrong-name / corrected-name experiment and final live HTTPS proof. Its recorded commit is `09c542b`. The existing ROOT remains off and disconnected. Manual clock accuracy and healthy time synchronization are separate; synchronization remains unresolved. Preserve the Day 14 legacy-CA hash evidence gap.

**Allow 2½–3 hours including Windows installation.** Reserve the final 15 minutes for saving progress. If client setup consumes 75 minutes, save its state and proceed only with independent Commvault inventory; do not turn today into a six-hour rebuild. Stop any one unexpected problem after 15 minutes. PARTIAL with usable recovery records is an acceptable closeout.

| Phase | Approximate time | Checkpoint |
|---|---:|---|
| 1. Recover context | 10 min | Exact prior records and current host |
| 2. Replace CLIENT | 45–75 min | Stable, domain-joined test VM |
| 3. Reprove PKI | 20 min | Same WEB certificate, strict HTTPS success |
| 4. Inventory Commvault | 20–25 min | Actual roles, version, URLs and TLS owner |
| 5–6. Capture recovery and plan change | 25–35 min | Verified copies and exact rollback map |
| 7. Close out | 15 min | Honest result and Day 19 readiness |

### How the pieces fit

- **PKI WEB / IIS:** existing lab HTTPS endpoint and public HTTP CA-certificate/CRL publication. Keep its own certificate and private key.
- **Commvault browser endpoint:** commonly the Commvault Tomcat service. It needs its own hostname/SAN and key in its supported keystore.
- **Commvault IIS web service, if present:** a separate endpoint and procedure; do not assume its port or certificate equals the browser endpoint's.
- **Commvault internal machine identity certificates:** managed by the CommServe's own CA for CommCell authentication, separately from browser HTTPS. Replacing these is outside today's experiment. [2024E client certificates](https://documentation.commvault.com/2024e/commcell-console/client_certificates.html).
- **Your issuer:** can sign a new application CSR after the actual product requirements and trust path are verified. The private key stays with its application.

Commvault identifies 11.36 as **Platform Release 2024E**. The linked 2024E certificate-tool workflow exists for this release family. Keep 11.36.72 for today's inventory and backups; this is not a claim that it is the latest or recommended maintenance release. Review current security advisories and the maintenance-release list before Day 19, and treat any needed upgrade as a separate backed-up change. [Release mapping](https://documentation.commvault.com/2024e/software/changes_in_commvault_platform_release_2024e.html), [maintenance releases](https://documentation.commvault.com/2024e/software/list_of_maintenance_releases_for_commvault_platform_release_2024e.html).

### Working rules

Paste one block at a time. Finish each credential prompt before pasting another block. No blanket `y` responses or global confirmation changes. A placeholder must be filled from the immediately preceding discovery output. Copy or write down discovered paths before continuing.

**HOST** blocks run in your existing PowerShell 7.6.6 console. `Invoke-Command` executes its braces inside the named guest; use the successful Day 14/17 plain `New-PSSession -VMName ... -Credential ...` pattern and verify the guest engine. **CV-SERVER** blocks run in an elevated built-in Windows PowerShell console on the actual Commvault web endpoint server. This supports a Commvault machine on another host without inventing remoting or network access. Your HOST console stays in PowerShell 7.

All raw output, paths, runtime identities, configuration copies and keystores stay in private evidence outside Git. No Whizlabs session or personal Azure deployment is needed today.

## 1. Recover the completed context — HOST

**Purpose:** use actual prior state rather than retyping server identities.

### 1A. Discover prior sessions

```powershell
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows -or $PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -ne 7) {
    throw 'Open PowerShell 7.6.6 on the Windows Hyper-V host.'
}
if (-not [Environment]::Is64BitProcess) { throw 'Use the 64-bit terminal.' }
$Principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run the terminal as administrator.' }
Import-Module Hyper-V -ErrorAction Stop
$PSVersionTable
$EvidenceRoot = Join-Path $env:LOCALAPPDATA 'CloudSecurityLab'
$Prior = @(Get-ChildItem -LiteralPath $EvidenceRoot -Directory -Filter 'day15-16-*' |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resume.xml') })
$Prior | Select-Object Name,FullName | Format-List
Get-ChildItem -LiteralPath $EvidenceRoot -Directory -Filter 'day18-*' | Select-Object Name,FullName
```

Write down the completed Day 15–16 folder. If a Day 18 folder already exists, use **Resume** at the end before creating anything.

### 1B. Load and establish today's private record

```powershell
if ($Prior.Count -ne 1) { throw 'Select the exact completed Day 15-16 folder with the tutor; do not choose the latest blindly.' }
$Day16Evidence = $Prior[0].FullName
$Day16 = Import-Clixml -LiteralPath (Join-Path $Day16Evidence 'resume.xml')
if ([int]$Day16.LastCompletedPhase -ne 7) { throw 'Completed Phase 7 record required.' }
$Day14Evidence = $Day16.Day14Evidence
$Ctx = Import-Clixml -LiteralPath (Join-Path $Day14Evidence 'context.xml')
if ($Ctx.HostName -ine $env:COMPUTERNAME) { throw 'Wrong Hyper-V host.' }
$RootVM = $Ctx.RootVM; $WebVM = $Ctx.WebVM; $DcVM = $Ctx.DcVM
$IssuerVM = $Ctx.IssuerVM; $OldClientVM = $Ctx.ClientVM
$WebFqdn = $Day16.WebFqdn; $WebIP = $Ctx.WebIP; $LeafThumb = $Day16.LeafThumbprint
$LabDomain = $Ctx.LabDomain; $DcIP = $Ctx.DcIP; $Prefix = [int]$Ctx.Prefix
$PublicLeaf = Join-Path $Day16Evidence 'web.cer'
$PublicRoot = Join-Path $Day14Evidence 'root.cer'
foreach ($Path in @($PublicLeaf,$PublicRoot)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing saved public file: $Path" }
}
$Leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PublicLeaf)
try { if ($Leaf.Thumbprint -ne $LeafThumb) { throw 'Leaf differs from completed evidence.' } } finally { $Leaf.Dispose() }
$Root = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PublicRoot)
try { $RootThumb = $Root.Thumbprint } finally { $Root.Dispose() }
foreach ($Name in @($RootVM,$WebVM,$IssuerVM)) {
    $Saved = Import-Clixml -LiteralPath (Join-Path $Day14Evidence "$Name-vm.xml")
    if ((Get-VM -Name $Name).Id -ne $Saved.Id) { throw "Recorded VM identity mismatch: $Name" }
}
if ((Get-VM -Name $RootVM).State -ne 'Off' -or @(Get-VMNetworkAdapter -VMName $RootVM | Where-Object SwitchName).Count) {
    throw 'ROOT must be off with no connected NIC.'
}
Get-VM | Select-Object Name,Id,State
$Stamp = Get-Date -Format yyyyMMdd-HHmmss
$Evidence = Join-Path $EvidenceRoot "day18-$Stamp"
New-Item -ItemType Directory -Path $Evidence | Out-Null
icacls.exe $Evidence /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
if ($LASTEXITCODE -ne 0) { throw 'Private evidence ACL setup failed.' }
$GuestWork = "C:\LabPKI\day18-$Stamp"
$State18 = [ordered]@{Day16Evidence=$Day16Evidence;Day14Evidence=$Day14Evidence;Evidence=$Evidence;
    GuestWork=$GuestWork;OldClientVM=$OldClientVM;ClientVM=$null;ClientVMId=$null;ClientIP=$null;
    RootThumb=$RootThumb;LeafThumb=$LeafThumb;ClientReady=$false;PkiPassed=$false;
    WebRuleName="CloudSecurityLab-Day18-$Stamp";WebRuleCreated=$false;CvReportedBuild='11.36.72'}
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
$Evidence
```

**Expected:** prior certificate matches its completion record; ROOT stays off; private Day 18 path is printed. Copy that path. **Stop:** wrong host, missing context, VM identity mismatch or ACL failure. **Recovery:** only today's evidence directory was created; no VM or certificate configuration changed.

Before Phase 2, use Hyper-V Manager to start the recorded DC and WEB if they are off, then wait for Windows to finish booting. Keep ROOT off. Today's validation uses existing certificates and published CRLs; it does not require a new issuer signing operation.

## 2. Replace the unstable client — HOST, then fresh guest

**Purpose:** create one reliable relying-party client. Preserve the old client and historical evidence. A Windows Server 2022 Desktop Experience member VM is sufficient for these TLS tests; it does not need IIS, AD CS or Commvault installed.

### 2A. Discover installation media, storage and network

```powershell
Get-Item -LiteralPath $Ctx.Iso | Select-Object FullName,Length
Get-Item -LiteralPath $Ctx.VmBase | Select-Object FullName
Get-VMSwitch | Select-Object Name,SwitchType
Get-Volume | Select-Object DriveLetter,SizeRemaining
Get-VM | Select-Object Name,State,MemoryAssigned
Get-VMNetworkAdapter -VMName $OldClientVM | Select-Object VMName,SwitchName,IPAddresses
```

Copy the ISO and VM-storage paths. Reserve an unused IPv4 address on the existing lab subnet using your address/DHCP inventory. A failed ping does not prove that an address is free. Use a new computer name and a different IP from the old client, DC, issuer and WEB. On the DC, use **Active Directory Users and Computers → Find → Computers** to search the proposed new name; stop if an existing computer account has that name. Review available host memory and disk before allocating 4 GB / 2 vCPU / a 64 GB dynamic disk.

### 2B. Fill the inputs, record intent, then create once

```powershell
$ClientVM = 'LABCLIENT18' # Proposed NEW VM and Windows computer name; change before creating if needed.
$ClientIP = ''           # Fill with the reserved unused lab IPv4 address.
$AddressReserved = $false # Set true only after checking your address/DHCP inventory.
if (-not $AddressReserved -or [string]::IsNullOrWhiteSpace($ClientIP)) { throw 'Reserve and enter the new client address first.' }
if ([ipaddress]::Parse($ClientIP).AddressFamily -ne 'InterNetwork') { throw 'IPv4 required.' }
if ($ClientIP -in @($DcIP,$WebIP,$Ctx.IssuerIP,$Day16.ClientIP)) { throw 'Use a different unused address.' }
if ($ClientVM -notmatch '^[A-Za-z][A-Za-z0-9-]{0,13}[A-Za-z0-9]$') { throw 'Use a 2-15 character Windows computer name.' }
if (@(Get-VM | Where-Object Name -eq $ClientVM).Count) { throw 'VM already exists; inspect/resume instead of creating again.' }
$ClientFolder = Join-Path $Ctx.VmBase $ClientVM
if (Test-Path -LiteralPath $ClientFolder) { throw 'VM storage folder already exists.' }
if ((Get-VMSwitch -Name $Ctx.LabSwitch).SwitchType -ne 'Internal') { throw 'Expected the recorded Internal lab switch.' }
$State18.ClientVM=$ClientVM; $State18.ClientIP=$ClientIP
$State18.ClientFolder=$ClientFolder; $State18.ClientIso=$Ctx.Iso
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
$NewClient = New-VM -Name $ClientVM -Generation 2 -MemoryStartupBytes 4GB -Path $ClientFolder `
    -NewVHDPath (Join-Path $ClientFolder "$ClientVM.vhdx") -NewVHDSizeBytes 64GB -SwitchName $Ctx.LabSwitch
$State18.ClientVMId=$NewClient.Id
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
Set-VM -VM $NewClient -ProcessorCount 2 -AutomaticCheckpointsEnabled $false `
    -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
$Dvd = Add-VMDvdDrive -VM $NewClient -Path $Ctx.Iso -Passthru
Set-VMFirmware -VM $NewClient -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -FirstBootDevice $Dvd
Start-VM -VM $NewClient
vmconnect.exe localhost $ClientVM
```

In VMConnect, boot the DVD and install **Windows Server 2022 Standard Evaluation (Desktop Experience)** from your legitimate lab media, or your properly licensed equivalent. Select **Custom** and the new VM's sole blank disk. Set its local Administrator password and sign in once. Use Basic Session if Enhanced Session blocks the initial login. Do not clone the expired client or another server's Windows disk.

### 2C. Credentials — each block alone

```powershell
$ClientCred = Get-Credential -UserName 'Administrator' -Message 'NEW client local Administrator password'
```

```powershell
$LabJoinCred = Get-Credential -Message 'Existing LAB domain account permitted to join this new member computer'
```

### 2D. Connect; configure only the recorded new guest

```powershell
if ((Get-VM -Name $ClientVM).Id -ne $State18.ClientVMId) { throw 'New-client VM identity changed.' }
$ClientSession = New-PSSession -VMName $ClientVM -Credential $ClientCred
Invoke-Command -Session $ClientSession {
    $ErrorActionPreference='Stop'
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected built-in Windows PowerShell guest engine.' }
    $Computer = Get-CimInstance Win32_ComputerSystem
    if ($Computer.PartOfDomain -or $Computer.DomainRole -ge 4) { throw 'Expected a fresh workgroup guest; inspect before changing it.' }
    $Nic = @(Get-NetAdapter | Where-Object Status -eq Up)
    if ($Nic.Count -ne 1) { throw 'Expected one active lab NIC.' }
    if (@(Get-NetIPAddress -InterfaceIndex $Nic[0].ifIndex -AddressFamily IPv4 |
        Where-Object { $_.PrefixOrigin -eq 'Manual' -and $_.IPAddress -notlike '169.254.*' }).Count) {
        throw 'An address was already configured; inspect/resume.'
    }
    New-Item -ItemType Directory -Path $using:GuestWork | Out-Null
    Get-NetIPConfiguration | Export-Clixml -LiteralPath (Join-Path $using:GuestWork 'network-before.xml')
    New-NetIPAddress -InterfaceIndex $Nic[0].ifIndex -IPAddress $using:ClientIP -PrefixLength $using:Prefix | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $Nic[0].ifIndex -ServerAddresses $using:DcIP
    Resolve-DnsName "_ldap._tcp.dc._msdcs.$using:LabDomain" -Type SRV
    $Joined = Add-Computer -DomainName $using:LabDomain -NewName $using:ClientVM -Credential $using:LabJoinCred -PassThru -Force
    if (-not $Joined.HasSucceeded) { throw 'Domain join did not succeed.' }
    shutdown.exe /r /t 10
    if ($LASTEXITCODE -ne 0) { throw 'Could not schedule the new-client restart.' }
}
Remove-PSSession $ClientSession
```

Wait for Windows to restart and sign in through VMConnect. Then reconnect from HOST:

```powershell
$ClientSession = New-PSSession -VMName $ClientVM -Credential $ClientCred
Invoke-Command -Session $ClientSession {
    $ErrorActionPreference='Stop'
    $Computer=Get-CimInstance Win32_ComputerSystem
    if ($env:COMPUTERNAME -ine $using:ClientVM -or -not $Computer.PartOfDomain -or $Computer.Domain -ine $using:LabDomain) {
        throw 'New client name/domain does not match the plan.'
    }
    if (-not (Test-ComputerSecureChannel)) { throw 'Domain secure channel failed.' }
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,LastBootUpTime
    cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /dlv
    if ($LASTEXITCODE -ne 0) { throw 'License inspection failed.' }
    cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /xpr
    if ($LASTEXITCODE -ne 0) { throw 'License expiration inspection failed.' }
    Resolve-DnsName $using:WebFqdn -Type A
    [datetime]::UtcNow
} | Tee-Object -FilePath (Join-Path $Evidence 'client-readiness.txt')
[datetime]::UtcNow
Get-VMDvdDrive -VMName $ClientVM | Set-VMDvdDrive -Path $null
```

Verify a usable activation/evaluation state and enough remaining time for this lab block. Merely installing a fresh ISO does not prove stability. If activation needs connectivity, pause for a scoped activation plan; do not alter clocks, bypass licensing, or connect the whole lab to a different network. Compare host UTC with a reliable clock and client UTC with the host; stop if skew exceeds 60 seconds. [Microsoft evaluation guidance](https://learn.microsoft.com/en-us/windows-server/get-started/upgrade-conversion-options), [domain join](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer?view=powershell-5.1).

After these observations pass:

```powershell
$ClientReadinessReviewed = $false # Set true after reviewing licensing, DNS, secure channel and clock results.
if (-not $ClientReadinessReviewed) { throw 'Review the client readiness results first.' }
$State18.ClientReady=$true
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
```

**Expected:** new VM ID recorded; correct name/domain; healthy secure channel; valid OS evaluation/license; reliable boot. **Stop:** unexpected existing object, ambiguous IP ownership, bad licensing or join failure. **Recovery:** retain the new VM and its exact state. After an uncertain join, inspect name/domain before repeating `Add-Computer`; do not rerun VM creation or reset the computer account. Shut down the old client normally through its console after confirming it has no work to save. Keep its disk and original Day 14–17 records intact.

## 3. Reprove the existing PKI from the new client — HOST

**Purpose:** carry the same known-good endpoint onto a fresh relying party. This imports one verified lab root on the new client and adds one narrow WEB firewall rule for that client.

### 3A. WEB credentials alone, then connection

```powershell
$WebCred = Get-Credential -UserName "$WebVM\Administrator" -Message 'Existing PKI WEB local Administrator password'
```

```powershell
if (-not $State18.ClientReady) { throw 'Complete new-client readiness before the PKI validation phase.' }
$WebSession = New-PSSession -VMName $WebVM -Credential $WebCred
foreach ($Session in @($ClientSession,$WebSession)) {
    $Engine=Invoke-Command -Session $Session {
        [pscustomobject]@{Computer=$env:COMPUTERNAME;Edition=$PSVersionTable.PSEdition;Version=$PSVersionTable.PSVersion.ToString();Utc=[datetime]::UtcNow.ToString('o')}
    }
    $Engine
    if ($Engine.Edition -ne 'Desktop' -or [version]$Engine.Version -lt [version]'5.1') { throw 'Unexpected guest engine.' }
    if ([math]::Abs(([datetime]::UtcNow-[datetime]::Parse($Engine.Utc).ToUniversalTime()).TotalSeconds) -gt 60) { throw 'Clock skew exceeds 60 seconds.' }
}
Copy-Item -ToSession $ClientSession -LiteralPath $PublicRoot -Destination "$GuestWork\root.cer"
Copy-Item -ToSession $ClientSession -LiteralPath $PublicLeaf -Destination "$GuestWork\web.cer"
"Import verified root $RootThumb on new client $ClientVM; allow that client's $ClientIP to WEB TCP80/443" |
    Set-Content -LiteralPath (Join-Path $Evidence 'client-trust-and-web-rule-intent.txt')
$WebRuleName=$State18.WebRuleName
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
Invoke-Command -Session $ClientSession {
    $ErrorActionPreference='Stop'
    Get-ChildItem Cert:\LocalMachine\Root | Select-Object Thumbprint,Subject |
        Export-Clixml -LiteralPath (Join-Path $using:GuestWork 'root-store-before.xml')
    $RootFile=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("$using:GuestWork\root.cer")
    try { if ($RootFile.Thumbprint -ne $using:RootThumb) { throw 'Transferred root does not match saved Day 14 root.' } } finally { $RootFile.Dispose() }
    if (-not (Test-Path "Cert:\LocalMachine\Root\$using:RootThumb")) {
        Import-Certificate -FilePath "$using:GuestWork\root.cer" -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    }
}
Invoke-Command -Session $WebSession {
    $ErrorActionPreference='Stop'
    Import-Module WebAdministration
    $Cert=Get-Item "Cert:\LocalMachine\My\$using:LeafThumb"
    if (-not $Cert.HasPrivateKey) { throw 'Existing WEB private key missing.' }
    Get-WebBinding | Select-Object protocol,bindingInformation,certificateHash,certificateStoreName
    if (@(Get-NetFirewallRule | Where-Object Name -eq $using:WebRuleName).Count) { throw 'Recorded rule already exists; inspect/resume.' }
    New-NetFirewallRule -Name $using:WebRuleName -DisplayName 'Day18 new validation client to PKI WEB' `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80,443 -RemoteAddress $using:ClientIP -Profile Any | Out-Null
    Get-NetFirewallRule -Name $using:WebRuleName | Get-NetFirewallAddressFilter
}
$State18.WebRuleCreated=$true
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
```

The added rule allows the new client only. Other existing rules still apply; this does not prove all other clients are blocked. The application certificate and IIS bindings remain the Day 16 baseline.

### 3B. Repeat the successful Day 17 validation sequence

```powershell
Invoke-Command -Session $ClientSession {
    $ErrorActionPreference='Stop'
    $Dns=Resolve-DnsName $using:WebFqdn -Type A
    if ($using:WebIP -notin @($Dns.IPAddress)) { throw 'DNS points to a different WEB address.' }
    if (-not (Test-NetConnection $using:WebFqdn -Port 443 -InformationLevel Quiet)) { throw 'TCP443 failed.' }
    foreach ($Name in 'root.crl','issuer.crl') {
        $Path=Join-Path $using:GuestWork $Name
        Invoke-WebRequest -UseBasicParsing -Uri "http://$using:WebFqdn/pki/$Name" -OutFile $Path -TimeoutSec 20
        certutil.exe -dump $Path
        if ($LASTEXITCODE -ne 0) { throw 'CRL inspection failed.' }
    }
    certutil.exe -verify -urlfetch -sslpolicy $using:WebFqdn "$using:GuestWork\web.cer"
    if ($LASTEXITCODE -ne 0) { throw 'Certificate name/chain/revocation proof failed.' }
    $Tcp=New-Object System.Net.Sockets.TcpClient
    $Tcp.ReceiveTimeout=15000; $Tcp.SendTimeout=15000
    $Tls=$null
    try {
        $Tcp.Connect($using:WebFqdn,443)
        $Tls=New-Object System.Net.Security.SslStream($Tcp.GetStream(),$false)
        $Tls.ReadTimeout=15000; $Tls.WriteTimeout=15000
        $Tls.AuthenticateAsClient($using:WebFqdn,$null,[System.Security.Authentication.SslProtocols]::Tls12,$true)
        $Presented=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Tls.RemoteCertificate)
        try { if ($Presented.Thumbprint -ne $using:LeafThumb) { throw 'A different leaf is presented.' } } finally { $Presented.Dispose() }
        [pscustomobject]@{TLS=$Tls.SslProtocol;Authenticated=$Tls.IsAuthenticated;ExpectedLeafPresented=$true}
    } finally { if ($Tls) { $Tls.Dispose() }; $Tcp.Dispose() }
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $Page=Invoke-WebRequest -UseBasicParsing -Uri "https://$using:WebFqdn/day16.txt" -TimeoutSec 20
    if ($Page.StatusCode -ne 200 -or $Page.Content.Trim() -ne 'Day16 HTTPS baseline OK') { throw 'HTTPS marker failed.' }
    [pscustomobject]@{HTTPSStatus=$Page.StatusCode;MarkerMatched=$true}
} | Tee-Object -FilePath (Join-Path $Evidence 'new-client-pki-validation.txt')
$State18.PkiPassed=$true
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
```

**Expected:** DNS/TCP succeed; correct-name certificate policy succeeds; strict TLS presents the same leaf; marker returns 200. Inspect CRL Next Update dates, not just HTTP status. Day 17 observed issuer CRL expiry on October 8 and root CRL expiry on October 31; these are historical observations to recheck today. Record the issuer publication deadline for this week's maintenance.

**Stop:** expired CRL, wrong certificate, unexpected trust error or endpoint failure. Never bypass certificate validation to pass. **Recovery:** retain the new client and exact trust/firewall records; an expired issuer CRL needs controlled issuer publication maintenance, and an expired root CRL needs a separate ROOT maintenance step. Neither warrants recreating the CA. If this phase is blocked, Commvault inventory can continue, but Day 19 readiness is blocked.

## 4. Map the actual Commvault endpoints — CV-SERVER

**Purpose:** identify which service presents each certificate. Use the actual Commvault machine's console, even if it is on another host. If web roles are split across machines, repeat the inventory on each. These blocks target Windows; if an endpoint is on Linux or behind a separate proxy/load balancer, record that owner and pause its Windows-specific steps.

Open the existing Command Center and record the CommServe build shown on its dashboard. Also record the installed version of the Command Center/Web Server machine; distributed components can differ. Use the existing administrative access path. If a browser reports a certificate warning, record the warning and view its public certificate; do not label it trusted or suppress validation in a test.

### 4A. Create protected recovery storage and inspect installed components

Open **Windows PowerShell as administrator on CV-SERVER**. Variables here are local to that console.

```powershell
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) { throw 'Use elevated 64-bit Windows PowerShell on the Commvault Windows server.' }
$CvPrincipal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CvPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as administrator.' }
$CvStamp=Get-Date -Format yyyyMMdd-HHmmss
$CvEvidence=Join-Path $env:ProgramData "CloudSecurityLab\day18-commvault-$CvStamp"
New-Item -ItemType Directory -Path $CvEvidence | Out-Null
icacls.exe $CvEvidence /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
if ($LASTEXITCODE -ne 0) { throw 'Could not restrict recovery-folder access.' }
$Apps=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object DisplayName -match 'Commvault|CommServe|CommCell'
$Apps | Select-Object DisplayName,DisplayVersion,InstallLocation | Tee-Object -FilePath (Join-Path $CvEvidence 'installed-products.txt')
$CvServices=Get-CimInstance Win32_Service | Where-Object { $_.DisplayName -match 'Commvault|CommServe|CommCell' -or $_.Name -match 'GxTomcat|^Gx' }
$CvServices | Select-Object Name,DisplayName,State,StartName,PathName |
    Export-Clixml -LiteralPath (Join-Path $CvEvidence 'services-before.xml')
$CvServices | Select-Object Name,DisplayName,State,PathName | Format-List
Get-NetTCPConnection -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess |
    Export-Csv -LiteralPath (Join-Path $CvEvidence 'listeners-before.csv') -NoTypeInformation
$CvEvidence
```

Write down this server's name and full recovery-folder path. Installation registry data is a cross-check; it may not report the full maintenance build. Confirm **11.36.72** in the product interface. The phase is read-only apart from protected evidence files.

### 4B. Discover the files and active endpoint owner

Set the installation root from the product's installation path or the service executable path shown above. It is usually a ContentStore directory; do not assume the drive or instance.

```powershell
$CvInstall='' # Exact existing installation root discovered above.
if ([string]::IsNullOrWhiteSpace($CvInstall) -or -not (Test-Path -LiteralPath $CvInstall -PathType Container)) { throw 'Enter the discovered installation root.' }
Get-ChildItem -LiteralPath $CvInstall -Directory | Select-Object FullName
foreach ($Relative in @('Base\cvCertTool.cmd','jre\bin\keytool.exe','Apache\conf','Apache\bin','CVSearchService')) {
    $Candidate=Join-Path $CvInstall $Relative
    if (Test-Path -LiteralPath $Candidate) { Get-Item -LiteralPath $Candidate | Select-Object FullName,LastWriteTime }
}
$ApacheConf=Join-Path $CvInstall 'Apache\conf'
if (Test-Path -LiteralPath $ApacheConf) { Get-ChildItem -LiteralPath $ApacheConf -File | Select-Object Name,FullName,Length }
$Galaxy='HKLM:\SOFTWARE\CommVault Systems\Galaxy'
if (Test-Path $Galaxy) { Get-ChildItem $Galaxy | Select-Object PSChildName,Name }
if (Get-Module -ListAvailable WebAdministration) {
    Import-Module WebAdministration
    Get-Website | Select-Object Name,State,PhysicalPath
    Get-WebBinding | Select-Object protocol,bindingInformation,certificateHash,certificateStoreName
    Get-WebApplication | Select-Object Path,PhysicalPath,ApplicationPool
}
```

Copy the exact paths. To identify the active Tomcat instance, inspect its service executable and existing Java options/configuration through its Commvault Tomcat service UI; close with **Cancel**. Record `catalina.base` if specified. Match its listener PID and port to `listeners-before.csv`. Finding a `server.xml` file alone does not prove that instance loads it.

### 4C. Inspect selected Tomcat certificate references without printing passwords

Run this only when Tomcat serves the target browser endpoint. For an IIS-only or proxy endpoint, record that and use its configuration inventory instead.

```powershell
$TomcatConfig='' # Exact ACTIVE server.xml identified from this service instance.
if (-not (Test-Path -LiteralPath $TomcatConfig -PathType Leaf)) { throw 'Enter the active server.xml path.' }
$Xml=New-Object System.Xml.XmlDocument
$Xml.XmlResolver=$null
$Xml.Load($TomcatConfig)
$Allowed=@('port','address','protocol','scheme','SSLEnabled','keystoreFile','keystoreType','keyAlias',
    'certificateKeystoreFile','certificateKeystoreType','certificateKeyAlias','certificateFile','certificateKeyFile','certificateChainFile')
$TlsReferences=foreach ($Node in $Xml.SelectNodes('//Connector|//SSLHostConfig|//Certificate')) {
    foreach ($Attribute in $Node.Attributes) {
        if ($Attribute.Name -in $Allowed) { [pscustomobject]@{Element=$Node.Name;Setting=$Attribute.Name;Value=$Attribute.Value} }
    }
}
$TlsReferences | Format-Table -AutoSize
$TlsReferences | Export-Csv -LiteralPath (Join-Path $CvEvidence 'tls-references.csv') -NoTypeInformation
```

Resolve the active keystore reference to its **full filesystem path**, using the service's actual base directory and any referenced properties. Do not guess a relative path, assume `Instance001`, or infer that a file in `Apache\conf` is active. Raw XML may contain passwords; keep it out of chats and public evidence.

In the private worksheet below, enter one row per endpoint:

| Field | Record from the running lab |
|---|---|
| CommServe / browser host / IIS Web Server | Actual computer names; same or separate machines |
| CommServe build / web-host build / OS | Confirmed values, not just the reported version |
| Browser URL | Scheme, exact FQDN, port and application path |
| TLS terminator | Tomcat instance, IIS site, or external proxy |
| Current certificate | Subject, SAN, issuer, thumbprint, expiration; browser trust result |
| Key owner / store | Full active keystore path and alias, or Windows machine-store thumbprint |
| Backend service | Existing URL/port and dependent caller; separate from browser URL |
| Network / DNS | Which lab network hosts Commvault; can new CLIENT resolve and reach it? |
| Recovery | Current configuration paths, service names, credentials location in password manager |

### 4D. Test the discovered application route — HOST → new CLIENT

Copy the exact browser URL from the Commvault inventory, including its real port and path. Run this from HOST after the new client is ready. It checks DNS and TCP; it does not authenticate to the application or claim TLS trust.

```powershell
$CvBrowserUrl='' # Actual existing browser URL from the Commvault inventory; no password or token in it.
$CvUri=$null
if (-not [uri]::TryCreate($CvBrowserUrl,[UriKind]::Absolute,[ref]$CvUri) -or $CvUri.Scheme -notin @('http','https')) {
    throw 'Enter the exact existing HTTP/HTTPS application URL.'
}
if ($CvUri.UserInfo -or $CvUri.Query -or $CvUri.Fragment) { throw 'Use the clean application URL without credentials, tokens or fragments.' }
if (-not $State18.ClientReady) { throw 'Record route testing as blocked until CLIENT is ready.' }
Invoke-Command -Session $ClientSession -ArgumentList $CvUri.DnsSafeHost,$CvUri.Port -ScriptBlock {
    param($AppName,$AppPort)
    $ErrorActionPreference='Stop'
    Resolve-DnsName $AppName
    if (-not (Test-NetConnection -ComputerName $AppName -Port $AppPort -InformationLevel Quiet)) { throw 'Commvault route is not reachable from CLIENT.' }
    [pscustomobject]@{Name=$AppName;Port=$AppPort;TcpReachable=$true;TLS='Not tested by this block'}
} | Tee-Object -FilePath (Join-Path $Evidence 'commvault-route-check.txt')
$State18.CvBrowserUrl=$CvBrowserUrl
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
```

**Expected:** actual roles and TLS owner established; 2024E documentation matches the installed release family. **Stop:** unknown owner, split roles not inventoried, build mismatch, inaccessible active store, or unexpected Linux/proxy path. **Recovery:** preserve discovery output. No tool `configure` action, binding edit, service restart or upgrade has run. If Commvault is on another isolated network, record the connectivity gap for Day 19; do not improvise a bridge or gateway.

## 5. Back up the existing certificate configuration — CV-SERVER

**Purpose:** make a verified configuration rollback possible before replacement. Commvault's 2024E guidance requires backing up affected configuration and registry data; Tomcat recovery includes the active XML and key material. A public `.cer` alone cannot restore a server's private key. [Tomcat certificate guidance](https://documentation.commvault.com/2024e/commcell-console/creating_ca_signed_certificate_for_tomcat_server.html), [IIS web-service guidance](https://documentation.commvault.com/2024e/commcell-console/configuring_secured_access_on_web_service.html).

### 5A. Select exact files; copy and verify

For the Tomcat case, include its **active server.xml and active keystore**. If it uses separate PEM key/certificate/chain files, list all of those instead. For an IIS web-service change, include the actual affected `web.config`/proxy configuration files discovered on each relevant host. Add only files needed for this planned endpoint change.

```powershell
$FilesToPreserve=@(
    # 'PASTE full active server.xml path'
    # 'PASTE full active keystore path'
    # Add any other exact active TLS files that this endpoint requires.
)
if ($FilesToPreserve.Count -eq 0) { throw 'List the exact active files from Phase 4.' }
foreach ($Path in $FilesToPreserve) {
    if (-not [IO.Path]::IsPathRooted($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Invalid source file: $Path" }
}
$FilesToPreserve | Set-Content -LiteralPath (Join-Path $CvEvidence 'backup-intent.txt')
$BackupFiles=Join-Path $CvEvidence 'files'
if (Test-Path -LiteralPath $BackupFiles) { throw 'Backup files already exist; inspect them instead of overwriting.' }
New-Item -ItemType Directory -Path $BackupFiles | Out-Null
$Manifest=@()
$Index=0
foreach ($Path in $FilesToPreserve) {
    $Index++
    $Source=Get-Item -LiteralPath $Path
    $Before=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $Destination=Join-Path $BackupFiles ('{0:D2}-{1}' -f $Index,$Source.Name)
    Copy-Item -LiteralPath $Path -Destination $Destination
    $Copied=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    $After=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Before -ne $Copied -or $Before -ne $After) { throw 'Source changed during backup or copy hash differs; backup is incomplete.' }
    $Manifest += [pscustomobject]@{Source=$Source.FullName;Backup=$Destination;SHA256=$Copied;Length=$Source.Length;
        SourceSddl=(Get-Acl -LiteralPath $Path).Sddl;CapturedUtc=[datetime]::UtcNow.ToString('o')}
    $Manifest | Export-Clixml -LiteralPath (Join-Path $CvEvidence 'file-manifest.xml')
}
$Manifest | Select-Object Source,Backup,Length
```

A keystore and some configuration files contain secrets. This folder is restricted to local Administrators and SYSTEM. Keep it off OneDrive/public Git and retain its access controls when making an off-VM copy. A hash match proves the copy matches its source; it does not prove a successful restore.

### 5B. Verify access to the current keystore — Tomcat only

First discover/confirm the installed keytool and active keystore paths:

```powershell
$KeyTool=Join-Path $CvInstall 'jre\bin\keytool.exe'
$CurrentKeystore='' # Full active path from Phase 4, also present in the backup manifest.
Get-Item -LiteralPath $KeyTool,$CurrentKeystore | Select-Object FullName,Length
```

Run the next block by itself. Enter the **existing keystore password** at keytool's prompt, from your secure record. Do not put it on the command line. An empty-password listing that warns integrity was not verified is not a successful password check.

```powershell
& $KeyTool -list -keystore $CurrentKeystore
if ($LASTEXITCODE -ne 0) { throw 'Current keystore could not be opened; resolve rollback access before replacement.' }
```

Record the alias and `PrivateKeyEntry`, plus a successful integrity/password check. If the active TLS source is PEM or the Windows certificate store, document that alternate key source; do not run keystore commands against it. For an IIS certificate, retain the current certificate/private key on its original server and record `HasPrivateKey`; an IIS configuration backup does not export that key.

### 5C. IIS configuration and exact registry keys — only when applicable

On an actual Commvault IIS host, capture the IIS configuration before any later binding change:

```powershell
Import-Module WebAdministration
$IisBackupName="Day18-before-Commvault-$CvStamp"
$IisBackupName | Set-Content -LiteralPath (Join-Path $CvEvidence 'iis-backup-name.txt')
Backup-WebConfiguration -Name $IisBackupName
Get-WebConfigurationBackup -Name $IisBackupName
$IisBackupPath=Join-Path "$env:SystemRoot\System32\inetsrv\backup" $IisBackupName
$IisCopy=Join-Path $CvEvidence 'iis-configuration'
if (Test-Path -LiteralPath $IisCopy) { throw 'IIS recovery copy already exists; inspect/resume.' }
Copy-Item -LiteralPath $IisBackupPath -Destination $IisCopy -Recurse
$IisHashes=foreach ($File in Get-ChildItem -LiteralPath $IisBackupPath -File -Recurse) {
    $Relative=$File.FullName.Substring($IisBackupPath.Length+1)
    $Hash=(Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath (Join-Path $IisCopy $Relative) -Algorithm SHA256).Hash -ne $Hash) { throw 'IIS backup copy hash mismatch.' }
    [pscustomobject]@{Relative=$Relative;SHA256=$Hash}
}
$IisHashes | Export-Clixml -LiteralPath (Join-Path $CvEvidence 'iis-backup-hashes.xml')
Get-ChildItem Cert:\LocalMachine\My | Select-Object Subject,Thumbprint,NotAfter,HasPrivateKey |
    Export-Clixml -LiteralPath (Join-Path $CvEvidence 'machine-certificate-inventory.xml')
```

For each role where the Day 19 plan would alter Commvault registry settings, select the **existing** instance's relevant keys from Phase 4. The usual roles include `AdminConsole` and `Session`; select only actual keys relevant to the endpoint. This exports data; it does not edit the registry.

```powershell
$RegistryKeys=@(
    # 'HKEY_LOCAL_MACHINE\SOFTWARE\CommVault Systems\Galaxy\ACTUAL-INSTANCE\AdminConsole'
    # 'HKEY_LOCAL_MACHINE\SOFTWARE\CommVault Systems\Galaxy\ACTUAL-INSTANCE\Session'
)
$RegistryManifest=@()
$Number=0
foreach ($Key in $RegistryKeys) {
    if (-not (Test-Path -LiteralPath "Registry::$Key")) { throw "Selected registry key does not exist: $Key" }
    $Number++
    $RegFile=Join-Path $CvEvidence "registry-$Number.reg"
    if (Test-Path -LiteralPath $RegFile) { throw 'Registry backup exists; inspect/resume.' }
    reg.exe export $Key $RegFile
    if ($LASTEXITCODE -ne 0) { throw 'Registry export failed.' }
    $RegistryManifest += [pscustomobject]@{Key=$Key;Backup=$RegFile;SHA256=(Get-FileHash -LiteralPath $RegFile -Algorithm SHA256).Hash}
}
$RegistryManifest | Export-Clixml -LiteralPath (Join-Path $CvEvidence 'registry-manifest.xml')
```

If registry changes are not part of the selected endpoint procedure, leave the array empty and record NOT APPLICABLE. Do not interpret an empty manifest as a backup of relevant keys that were never selected.

### 5D. Save recovery locations and check application health

Create the private recovery worksheet on CV-SERVER:

```powershell
$RecoveryNote=Join-Path $CvEvidence 'recovery-readiness.txt'
if (-not (Test-Path -LiteralPath $RecoveryNote)) {
    @'
Actual CommServe / web-host builds:
Browser endpoint and TLS terminator:
Exact service name and prior running state:
Active configuration and key paths (see manifests):
Current certificate thumbprint / alias / expiry:
Existing keystore password verified (YES/NO/NOT APPLICABLE); password-manager entry only:
IIS backup name / old machine certificate retained, if applicable:
Relevant registry exports or reason not applicable:
Off-VM protected copy location / hash verification:
Latest existing CommServe DR backup: job/date/location/status; restore-tested separately:
Current application login/UI and a read-only existing job-history view:
Known pre-existing TLS warning or other fault:
Rollback method selected in Phase 6:
Unresolved gaps:
'@ | Set-Content -LiteralPath $RecoveryNote
}
notepad.exe $RecoveryNote
```

Check the latest **existing** CommServe DR backup in your product's job history and record its status and location. TLS file copies do not back up the CommServe database. Do not invent a successful DR backup or launch a full recovery project today.

Make one protected off-VM copy of this recovery folder using your established private transfer method. For a Commvault VM on this same Hyper-V host, the following HOST path is available; first copy/write down the exact VM name and `$CvEvidence` path from CV-SERVER:

```powershell
# HOST: fill these from the actual Commvault console and Hyper-V inventory.
$CvVM=''
$CvBackupPath=''
if ([string]::IsNullOrWhiteSpace($CvVM) -or [string]::IsNullOrWhiteSpace($CvBackupPath)) { throw 'Enter the discovered VM name and recovery path.' }
Get-VM -Name $CvVM | Select-Object Name,Id,State
```

Credential block alone:

```powershell
$CvCred=Get-Credential -Message 'Administrator of this exact Commvault VM for private backup transfer'
```

Then copy from that VM into the already protected HOST evidence directory:

```powershell
$CvSession=New-PSSession -VMName $CvVM -Credential $CvCred
$SourceList=Invoke-Command -Session $CvSession -ArgumentList $CvBackupPath -ScriptBlock {
    param($BackupPath)
    $ErrorActionPreference='Stop'
    $Base=(Get-Item -LiteralPath $BackupPath).FullName.TrimEnd('\')
    Get-ChildItem -LiteralPath $Base -File -Recurse | ForEach-Object {
        [pscustomobject]@{Relative=$_.FullName.Substring($Base.Length+1);SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    }
}
if (@($SourceList).Count -eq 0) { throw 'No recovery files found at the selected path.' }
$HostCvCopy=Join-Path $Evidence ("commvault-recovery-"+$CvVM)
if (Test-Path -LiteralPath $HostCvCopy) { throw 'Destination exists; inspect rather than overwrite.' }
Copy-Item -FromSession $CvSession -LiteralPath $CvBackupPath -Destination $HostCvCopy -Recurse
foreach ($Item in $SourceList) {
    $Copied=Join-Path $HostCvCopy $Item.Relative
    if ((Get-FileHash -LiteralPath $Copied -Algorithm SHA256).Hash -ne $Item.SHA256) { throw 'Off-VM recovery copy mismatch.' }
}
$SourceList | Export-Clixml -LiteralPath (Join-Path $Evidence ("commvault-off-vm-hashes-"+$CvVM+'.xml'))
$State18.CvTransfers=@($State18.CvTransfers | Where-Object { $_ }) +
    [pscustomobject]@{VM=$CvVM;Source=$CvBackupPath;HostCopy=$HostCvCopy}
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
Remove-PSSession $CvSession
$HostCvCopy
```

If Commvault is elsewhere, copy through your existing protected administrative transfer and verify SHA256 at both ends with `Get-FileHash -LiteralPath 'FULL FILE PATH' -Algorithm SHA256`. Do not create a public share or enable new remoting to force this optional transfer path. Until an off-VM copy is verified, record that recovery limitation.

**Expected:** active TLS files are preserved byte-for-byte; applicable IIS/registry configuration is captured; current key access and recovery locations are known. Current application behavior still matches the starting state. **Stop:** missing active key, unknown store password, copy/hash error, or unexpected application change. **Recovery:** preserve completed copies and mark gaps. No Commvault service/configuration change requires rollback today. A same-VM copy is useful configuration rollback material, not independent disaster recovery; an untested off-VM copy is still not a restore test.

## 6. Select the Day 19 procedure and write the rollback map

**Purpose:** turn inventory into one exact, reviewable change. Use the **2024E / 11.36** documentation, with the installed maintenance build and topology recorded. These are review steps today; do not execute the vendor's certificate replacement commands yet.

| Actual endpoint | Procedure to carry into Day 19 | Recovery material |
|---|---|---|
| Commvault Tomcat browser TLS | [2024E Certificate Tool workflow](https://documentation.commvault.com/2024e/commcell-console/using_commvault_certificate_tool.html): new workspace/key/CSR, signed response, validated keystore, planned service change | Active server.xml, old key store and working password, exact instance/service, file ACLs |
| IIS-hosted Commvault web service | [2024E secured web service](https://documentation.commvault.com/2024e/commcell-console/configuring_secured_access_on_web_service.html): review IIS plus dependent application URLs/settings as one change | IIS backup, old certificate/private key, affected config and exact registry exports |
| Proxy/load balancer terminates TLS | Version-specific procedure at that terminator; backend separately inventoried | That device's current config/key references and recovery method |

The IIS web-service page specifies a well-known CA and includes changes beyond a binding. Do not claim that importing your private lab root automatically satisfies every Commvault integration. Verify the exact private-CA support/trust path for any backend you select; otherwise leave that backend out of the change and mark it BLOCKED. Browser TLS with a locally trusted private CA is the initial lab target, subject to successful product validation.

### Certificate design to record privately

- Select **one** initial browser endpoint and its exact DNS SAN. Use a stable lab FQDN reachable by the new client. Day 17 proved why an alias absent from the SAN will fail.
- Create a **new Commvault-owned key** during Day 19. Do not export PKI WEB's non-exportable Windows key or reuse its leaf.
- For Tomcat, plan RSA 3072 and SHA-256-compatible issuance, Server Authentication, the required full certificate chain, and a protected application keystore. Review the installed tool's actual configuration before running it: the 2024E reference lists `keyalg` default DSA, so do not rely on defaults. Keep `allow-invalid-certs`, `force-actions`, and `skip-validate-keystore` false. [2024E tool settings](https://documentation.commvault.com/2024e/commcell-console/settings_for_workspace_configuration_file.html).
- Verify that the existing narrow, approval-gated template accepts the chosen CSR/provider workflow before issuance. Windows key non-exportability is not a guarantee that a Java keystore cannot be copied. Protect the keystore and password as private-key material. Do not broaden template enrollment to make submission work.
- Check the new client and any dependent backend can resolve the chosen name and reach required ports and the existing HTTP AIA/CDP URLs. Record any cross-network gap without deploying a VPN or exposing Commvault publicly.

### Exact rollback map — write it into recovery-readiness.txt

For **Tomcat**, record: service name; original service state; active XML destination → backup file; active keystore destination → backup file; original ACLs; old alias and password-manager reference. The later recovery sequence is: stop only that Tomcat service, preserve the failed new configuration, restore those exact old files/permissions, start that service, then check the old certificate/URL and application UI. Do not roll back a CommServe, SQL or CA VM snapshot to undo web TLS. The product's [Tomcat configuration procedure](https://documentation.commvault.com/2024e/commcell-console/configuring_tomcat_service.html) calls for a service stop/restart, so reserve a maintenance window.

For **IIS**, record the old site/IP/port/host/SNI/certificate-store/thumbprint combination and any changed application URLs/registry values. Keep the old certificate and private key. Prefer restoring the exact changed binding and settings; a full IIS backup restore affects every site and needs a review of intervening changes. Microsoft's [IIS backup command](https://learn.microsoft.com/en-us/powershell/module/webadministration/backup-webconfiguration?view=windowsserver2025-ps) captures IIS configuration, not all application files or certificate keys.

**Expected:** one endpoint, one applicable procedure, explicit SAN/key owner/trust requirements, recoverable old configuration and a maintenance window. **Stop:** unresolved private-CA compatibility, ambiguous endpoint ownership, absent key recovery or new-client baseline failure. **Recovery:** make no application change; save the exact missing requirement. An upgrade is not a generic fix for an unknown TLS architecture.

## 7. Close out and retain the useful state — HOST and CV-SERVER

**Purpose:** leave a working replacement client and preserved application configuration for Day 19.

On CV-SERVER, finish `recovery-readiness.txt` and revisit the same application login/read-only job-history view used before the backup. Record PASS only if it still works. The new CA-signed Commvault certificate remains **NOT ISSUED / NOT BOUND** today.

On HOST:

```powershell
$CloseNames=@($RootVM)
if ($State18.ClientVMId) { $CloseNames+=$State18.ClientVM }
Get-VM -Name $CloseNames | Select-Object Name,Id,State
if ((Get-VM -Name $RootVM).State -ne 'Off' -or @(Get-VMNetworkAdapter -VMName $RootVM | Where-Object SwitchName).Count) {
    throw 'ROOT closeout check failed.'
}
if ($ClientSession -and $ClientSession.State -eq 'Opened') {
    $HasTrustRecord=Invoke-Command -Session $ClientSession { Test-Path -LiteralPath "$using:GuestWork\root-store-before.xml" }
    if ($HasTrustRecord) { Copy-Item -FromSession $ClientSession -LiteralPath "$GuestWork\root-store-before.xml" -Destination $Evidence -ErrorAction Stop }
}
$State18 | Export-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
@($ClientSession,$WebSession,$CvSession) | Where-Object { $_ -and $_.State -eq 'Opened' } | Remove-PSSession
$Evidence
```

For an early pause, copy only the evidence files that were actually created. Keep the new client, its trust and the narrow WEB rule for Day 19. Shut down unused lab VMs normally when finished; leave ROOT off. Do not delete the old client or rewrite historical context to pretend it was always the new one.

**Only if abandoning the replacement's WEB allowance:** reconnect to the recorded WEB and inspect the recorded rule first:

```powershell
Invoke-Command -Session $WebSession {
    Get-NetFirewallRule -Name $using:WebRuleName | Get-NetFirewallAddressFilter
}
```

After confirming it is the exact Day 18 rule for the abandoned client, this separate block removes only that allowance:

```powershell
Invoke-Command -Session $WebSession {
    Remove-NetFirewallRule -Name $using:WebRuleName
}
```

Retain the new VM and domain computer account for deliberate cleanup later if needed. Do not automate deletion from a name alone. Today's runbook contains no Commvault rollback execution because it makes no application configuration change.

### Compact results — fill privately, publish only a sanitized copy

```text
Day 18 — Commvault TLS preparation
Date:
Overall: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION
New client built, valid OS license/evaluation, joined and stable:
Exact new client identity/IP saved privately; old client preserved:
New client validates existing WEB name/chain/revocation/exact leaf/HTTPS marker:
ROOT off/disconnected; current CRL deadlines recorded:
Actual CommServe and web-host build verified (reported 11.36.72):
Browser endpoint / backend ownership and port mapping complete:
Selected Day 19 endpoint and 2024E procedure:
SAN / key owner / template compatibility / trust paths established:
Active configuration and key backups hash-verified:
Existing key/password access verified or specific limitation:
Applicable IIS/registry backups and exact rollback map:
Off-VM protected copy verified; restore test: NOT PERFORMED / actual result:
CommServe DR backup observed; no TLS-copy-as-DR claim:
Application behavior unchanged after preparation:
Commvault new certificate issuance/binding: NOT PERFORMED
Personal Azure deployments / Sentinel activation today: NONE
Day 19 readiness: READY / BLOCKED — reason:
Remaining time-sync issue / historical evidence gaps:
Last verified step / next step:
```

**COMPLETE** means replacement baseline, applicable Commvault inventory, verified recovery material and exact change plan all pass. **PARTIAL** means useful preparation with gaps; **BLOCKED** names an unavailable prerequisite; **FAILED EXPECTATION** identifies a tested control behaving contrary to the expected result. Backup success is not restore success. Record Day 19 BLOCKED for any missing prerequisite rather than promising readiness.

### Resume after closing a console

Discover existing Day 18 folders with `Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'CloudSecurityLab') -Directory -Filter 'day18-*'`. Copy the exact intended path before this HOST block:

```powershell
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$Evidence='' # Full EXISTING Day 18 HOST folder from discovery.
$State18=Import-Clixml -LiteralPath (Join-Path $Evidence 'resume.xml')
$Day16Evidence=$State18.Day16Evidence; $Day14Evidence=$State18.Day14Evidence
$Day16=Import-Clixml -LiteralPath (Join-Path $Day16Evidence 'resume.xml')
$Ctx=Import-Clixml -LiteralPath (Join-Path $Day14Evidence 'context.xml')
if ($Ctx.HostName -ine $env:COMPUTERNAME) { throw 'Wrong host.' }
Import-Module Hyper-V
$RootVM=$Ctx.RootVM; $WebVM=$Ctx.WebVM; $DcVM=$Ctx.DcVM; $IssuerVM=$Ctx.IssuerVM
$OldClientVM=$State18.OldClientVM; $ClientVM=$State18.ClientVM; $ClientIP=$State18.ClientIP
$WebFqdn=$Day16.WebFqdn; $WebIP=$Ctx.WebIP; $LeafThumb=$State18.LeafThumb; $RootThumb=$State18.RootThumb
$LabDomain=$Ctx.LabDomain; $DcIP=$Ctx.DcIP; $Prefix=[int]$Ctx.Prefix
$PublicLeaf=Join-Path $Day16Evidence 'web.cer'; $PublicRoot=Join-Path $Day14Evidence 'root.cer'
$GuestWork=$State18.GuestWork; $WebRuleName=$State18.WebRuleName
$State18 | Format-List
if ($State18.ClientVMId -and (Get-VM -Name $ClientVM).Id -ne $State18.ClientVMId) { throw 'Client VM identity mismatch.' }
```

Reconnect using the separate credential/session blocks above, with the current guest name. Check the guest name/domain, imported root and exact WEB rule before repeating a partial step. If a VM create returned an uncertain result before its ID was saved, inspect that VM and its disk path against the saved intent; never blindly adopt it or create a second replacement.

On CV-SERVER, discover `Get-ChildItem -LiteralPath (Join-Path $env:ProgramData 'CloudSecurityLab') -Directory -Filter 'day18-commvault-*'`, set `$CvEvidence` to the exact existing folder, reload `file-manifest.xml` and your recovery worksheet, and reestablish the selected installation paths. Do not create a second backup set to hide an incomplete first one.

### Git after the hands-on session

Keep runtime evidence and recovery material outside the repository. Publish just this generic runbook, the diagram, and a sanitized result if desired. Discover your download folder first in File Explorer and copy its full path.

```powershell
$Repo='C:\git\azure-secure-hub-spoke-lab' # Existing working repository; verify before use.
$Materials='' # Folder containing DAY-18-RUNBOOK.md and DAY-18-DIAGRAM.png.
if (-not (Test-Path -LiteralPath (Join-Path $Materials 'DAY-18-RUNBOOK.md'))) { throw 'Enter the actual materials folder.' }
Set-Location -LiteralPath $Repo
git status --short --branch
if ($LASTEXITCODE -ne 0) { throw 'Repository inspection failed.' }
git log -1 --oneline
if ($LASTEXITCODE -ne 0) { throw 'History inspection failed.' }
```

Review the current Day 17 history and preserve any existing changes. Then create one branch; if it exists, inspect/resume it instead:

```powershell
git switch -c feat/day18-commvault-tls-prep
if ($LASTEXITCODE -ne 0) { throw 'Inspect the existing branch or switch failure.' }
Copy-Item -LiteralPath (Join-Path $Materials 'DAY-18-RUNBOOK.md') -Destination 'docs\day18-runbook.md'
Copy-Item -LiteralPath (Join-Path $Materials 'DAY-18-DIAGRAM.png') -Destination 'docs\day18-diagram.png'
notepad.exe 'docs\day18-results.md'
```

Fill and save the sanitized result, close Notepad, then review/stage only these files:

```powershell
git add -- docs/day18-runbook.md docs/day18-diagram.png docs/day18-results.md
if ($LASTEXITCODE -ne 0) { throw 'Staging failed.' }
git diff --cached --name-only
git --no-pager diff --cached -- docs/day18-results.md
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Review staged content/formatting before committing.' }
```

After reviewing the staged files for private data:

```powershell
git commit -m 'docs: record Commvault TLS preparation and replacement client validation'
if ($LASTEXITCODE -ne 0) { throw 'Commit failed.' }
git push -u origin feat/day18-commvault-tls-prep
if ($LASTEXITCODE -ne 0) { throw 'Push failed; preserve the local commit.' }
```

## Future Azure plan — saved decision, no deployment today

**Adopt the three-environment model:** Hyper-V for persistent Windows/PKI/Commvault; Whizlabs for permitted expensive/disposable exercises; personal Azure for a deliberately small persistent telemetry and automation baseline. Target **under $20/month**, with the resting state as close to zero as practical. This is a design constraint, not a billing guarantee.

Before Day 23 logging, next week or as soon as that dependency is ready:

1. Inventory the personal subscription's existing billable resources. Establish a monthly $20 budget with actual-cost alerts at $5/$10/$15/$20 and a $15 forecast alert. Budget notifications do **not** stop consumption, and cost data/evaluation lag. Treat $15 as an operational stop-and-review point before starting more paid work. [Microsoft budget behavior](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets).
2. Price the exact region/SKUs, retention, log tables, alert rules and expected data volume before deployment. Candidate persistent services are a tiny Log Analytics workspace and later minimal Terraform-state storage; add Key Vault only when a lesson needs it. Diagnostic settings and saved configuration can lead to paid downstream ingestion. No blanket assumption that storage, telemetry, alerts or an idle resource is free.
3. Use deployment restrictions, selective data collection, short appropriate retention, teardown verification and cost review. A Log Analytics daily cap can overshoot and is not a precise spending limit. [Daily-cap limitations](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/daily-cap). Avoid persistent NAT Gateway, paid Bastion tiers, Azure Firewall, Application Gateway, VPN Gateway, private endpoints and paid compute. Deallocated VMs can still leave billable disks/public IPs and other dependencies; account for those explicitly.
4. Keep personal and Whizlabs tenant/subscription variables, authentication contexts and Terraform state separate. Validate the intended subscription before each deployment. Never apply the old sandbox state into the personal subscription. Configuration can be rebuilt; yesterday's telemetry/incident history cannot be recreated by Terraform.
5. Reserve Sentinel activation for the detection block around **Day 26**, when sources and exercises are ready. The current documented trial is **31 days**, with up to **10 GB/day of Analytics-plan ingestion and Sentinel analysis** waived, subject to eligibility/limits; extra automation and other services can still charge. Recheck terms at activation, record the actual expiry and plan shutdown/offboarding before it ends. Do not enable Sentinel today or size ingestion to the free ceiling. [Sentinel trial and billing](https://learn.microsoft.com/azure/sentinel/billing?tabs=simplified%2Ccommitment-tiers).

Commvault-to-Azure logging and backup-storage integrations remain future design choices; today creates no connector, agent, VPN, Azure storage target or paid cloud dependency.

## Tutor prompt and preparation checks

> Walk me through this Day 18 runbook one block at a time. My HOST is elevated 64-bit PowerShell 7.6.6; reuse the plain Day 14/17 PowerShell Direct pattern and verify guest engines. Commvault is reported as 11.36.72 (2024E). The old client needs replacement. Explain each command's machine, purpose, expected evidence and first stop condition. Discover paths before asking me to use them, isolate credential prompts, and update the saved runbook if a correction is needed. Preserve ROOT offline, the working PKI WEB certificate and public HTTP publication. Today prepares Commvault TLS; determine Tomcat/IIS ownership, back up exact active configuration/key material privately and record rollback. Do not start an upgrade, certificate replacement or Azure deployment as a workaround. Save partial progress when the timebox ends. Personal Azure under $20/month and strategic Sentinel-trial use are deferred planning requirements.

Preparation used the actual Day 15–17 result files, saved completion flags, the Day 17 working command pattern, your version/client replies, and the linked Microsoft/Commvault documentation. All 33 PowerShell blocks passed syntax checks in PowerShell 7.6.6 and Windows PowerShell 5.1. No live VM, application, certificate or Azure changes were performed while preparing these materials. Syntax checks do not establish live permissions, connectivity or product compatibility. The 2024E procedure must be matched to the actual endpoint and local tool in Phases 4–6.

**Diagram:** DAY-18-DIAGRAM.png. Built-in image generation; reviewed for separate IIS/Tomcat roles, private-key ownership, offline ROOT and future Azure boundaries. Prompt brief: “Day 18 Commvault TLS preparation; existing Hyper-V ROOT/issuer/PKI WEB; stable replacement client validation; discover Commvault machines and TLS terminator; private configuration/keystore backups and rollback; planned Day 19 CSR signing; deferred personal Azure under $20/month with budgets and a reserved 31-day Sentinel trial, separate Whizlabs context/state.” Blue is existing, green is today's planned work, dashed is future work; the drawing is not execution evidence.
