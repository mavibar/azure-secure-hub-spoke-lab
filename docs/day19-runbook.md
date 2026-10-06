# Day 19 — Put the lab CA certificate on Commvault Tomcat

**Starting point:** Day 18 completed October 5, 2026; commit `0f4c8f8`, branch `feat/day18-commvault-tls-prep`. This is the next change, not a report of work already performed.

**Today’s result:** Command Center presents a new Commvault-owned RSA 3072 certificate, signed by your existing lab issuing CA. LABCLIENT18 verifies the exact hostname, certificate, chain and revocation, then opens the application successfully.

## Read this first

Follow one block at a time. Read the success and stop checks before moving on. You can follow this runbook directly; a tutor chat is optional. When asking for help, give the phase, command and sanitized error—not a password, properties file, raw XML or keystore.

**For OneNote:** copy from the rendered document, section by section. Keep code blocks as plain text with straight quotes. Copy commands from the original runbook if OneNote changes quotation marks or line breaks. Do not paste the entire runbook into a terminal.

**One console:** elevated, 64-bit PowerShell **7.6.6 on the Hyper-V host**. Commands inside `Invoke-Command` run in the named guest’s Windows PowerShell 5.1. Only certificate approval and browser checks use guest GUI windows.

**Timebox: about 2–3 hours.** Context and recovery: 30 minutes. Key/CSR: 20 minutes. Approval/import: 35 minutes. Change and validation: 35 minutes. Reserve 25 minutes for recovery and closeout. Stop investigating any one unexpected problem after 15 minutes. Do not stop Tomcat unless at least 40 minutes remain. PARTIAL with the old working endpoint is a useful result.

### What yesterday established

- LABCLIENT18 is built and joined to the lab domain. Its two existing NICs reach the PKI network and the separate Commvault network. Its second NIC has no default gateway and does not register in DNS. It is not a router.
- Its scoped hosts-file mapping and the narrow Commvault firewall allowance already work. Keep them.
- Commvault reports **11.36.72 / 2024E**. `GxTomcatInstance001` serves the Command Center endpoint. The active `Apache\conf\Server.xml` references `conf/CV_TempKeystoreFile.jks`, type JKS, alias `selfsigned`.
- **The password was found in the active Tomcat XML and successfully used with keytool.** Yesterday’s procedure was XML inspection → local password access → authenticated keytool listing. It was not a guessed default or a SQL stored procedure. Phase 2 repeats that procedure without displaying the secret or using the clipboard.
- Original XML and JKS were hash-verified and copied to protected storage on the host. The remaining readiness item is confirmation of the existing CommServe DR backup and recovery worksheet.
- No replacement Commvault certificate was issued or installed yesterday. PKI WEB already has working HTTPS. Its key and bindings stay unchanged; ROOT stays off and disconnected.

**Scope:** one Tomcat browser certificate. This does not replace Commvault’s internal client certificates or prove backup data-channel encryption. Keep the installed Commvault build. Personal Azure persistence, budgets and the strategic Sentinel trial remain deferred; no sandbox, Terraform or Azure login is required today.

## 1. Recover context and connect to the existing guests

**Purpose:** identify the completed records and reuse yesterday’s machines.

### 1A — HOST: discover the saved folder

```powershell
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if ($PSVersionTable.PSEdition -ne 'Core' -or
    $PSVersionTable.PSVersion.ToString() -ne '7.6.6' -or
    -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell 7.6.6.' }
$Principal = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as administrator.' }
Import-Module Hyper-V
$EvidenceRoot = Join-Path $env:LOCALAPPDATA 'CloudSecurityLab'
Get-ChildItem -LiteralPath $EvidenceRoot -Directory -Filter 'day18-*' |
    Select-Object FullName
Get-ChildItem -LiteralPath $EvidenceRoot -Directory -Filter 'day19-*' |
    Select-Object FullName
```

Copy the completed **October 5 Day 18** path into the next block. If Day 19 already exists, use **Resume** near the end; do not generate another workspace or key.

### 1B — HOST: load records; make today’s private record

Fill the two blank values before running. The FQDN is the exact existing browser name recorded yesterday, without `https://` or `/commandcenter`.

```powershell
$Day18Evidence = '' # Paste the completed Day 18 folder.
$CvFqdn = ''        # Exact existing Command Center DNS name.
if (-not (Test-Path -LiteralPath "$Day18Evidence\resume.xml")) { throw 'Select Day 18.' }
if ($CvFqdn -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9-]+$') { throw 'Enter the existing FQDN.' }
$D18 = Import-Clixml -LiteralPath "$Day18Evidence\resume.xml"
$Ctx = Import-Clixml -LiteralPath "$($D18.Day14Evidence)\context.xml"
$D16 = Import-Clixml -LiteralPath "$($D18.Day16Evidence)\resume.xml"
if ($Ctx.HostName -ine $env:COMPUTERNAME) { throw 'Wrong Hyper-V host.' }
$ClientVM = 'LABCLIENT18'
$IssuerVM = $Ctx.IssuerVM
$RootVM = $Ctx.RootVM
$IssuerCA = $Ctx.IssuerCA
$TemplateName = $D16.TemplateName
if ($TemplateName -ne 'LabWebTLS15') { throw 'Inspect the existing approved template record.' }
$Transfers = @($D18.CvTransfers | Where-Object VM -ieq 'Commserve01')
if ($Transfers.Count -ne 1) { throw 'Recover the exact Day 18 Commvault transfer record.' }
$CvVM = $Transfers[0].VM
$OldHostCopy = $Transfers[0].HostCopy
if (-not (Test-Path -LiteralPath "$OldHostCopy\file-manifest.xml")) { throw 'Missing Day 18 recovery manifest.' }
if ((Get-VM -Name $ClientVM).Id -ne $D18.ClientVMId) { throw 'Replacement client identity mismatch.' }
foreach ($VM in @($RootVM,$IssuerVM,$Ctx.WebVM)) {
    $Saved = Import-Clixml -LiteralPath "$($D18.Day14Evidence)\$VM-vm.xml"
    if ((Get-VM -Name $VM).Id -ne $Saved.Id) { throw "Wrong recorded VM: $VM" }
}
if ((Get-VM -Name $RootVM).State -ne 'Off' -or
    @(Get-VMNetworkAdapter -VMName $RootVM | Where-Object SwitchName).Count) {
    throw 'ROOT must remain off and disconnected.'
}
$Stamp = Get-Date -Format yyyyMMdd-HHmmss
$Evidence = Join-Path $EvidenceRoot "day19-$Stamp"
New-Item -ItemType Directory -Path $Evidence | Out-Null
icacls.exe $Evidence /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
if ($LASTEXITCODE -ne 0) { throw 'Private-folder ACL failed.' }
$GuestWork = "C:\LabPKI\day19-$Stamp"
$State19 = [ordered]@{ Evidence=$Evidence; Day18Evidence=$Day18Evidence
    CvVM=$CvVM; CvVMId=(Get-VM -Name $CvVM).Id; CvFqdn=$CvFqdn
    ClientVM=$ClientVM; IssuerVM=$IssuerVM; GuestWork=$GuestWork
    Stamp=$Stamp; Phase='Context'; RequestId=$null; NewThumb=$null }
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
$Evidence
Get-VM -Name $CvVM,$ClientVM,$IssuerVM,$Ctx.DcVM,$Ctx.WebVM |
    Select-Object Name,State,Id
```

Write down `$Evidence`. Start only any stopped DC, issuer, WEB, client or CommServe shown above through Hyper-V Manager; wait for Windows to boot. Do not start ROOT.

### 1C — HOST: credentials, one prompt per block

Use the existing accounts. Explicit `LABCLIENT18\Administrator` avoids yesterday’s ambiguity between local and domain Administrator. On ISSUER, use the existing lab domain administrator authorized for the template and CA—not a newly created account.

```powershell
$CvCred = Get-Credential -UserName "$CvVM\Administrator" -Message 'Existing Commvault VM administrator'
```

```powershell
$ClientCred = Get-Credential -UserName "$ClientVM\Administrator" -Message 'Existing replacement client local administrator'
```

```powershell
$IssuerCred = Get-Credential -Message 'Existing authorized lab domain administrator for ISSUER'
```

```powershell
$CvS = New-PSSession -VMName $CvVM -Credential $CvCred
$ClientS = New-PSSession -VMName $ClientVM -Credential $ClientCred
$IssuerS = New-PSSession -VMName $IssuerVM -Credential $IssuerCred
Invoke-Command -Session $CvS,$ClientS,$IssuerS {
    $ErrorActionPreference = 'Stop'
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5) { throw 'Expected guest Windows PowerShell 5.1.' }
    [pscustomobject]@{Computer=$env:COMPUTERNAME; Engine=$PSVersionTable.PSVersion.ToString(); UTC=[datetime]::UtcNow}
}
```

**Success:** recorded VMs match; three sessions work; clocks agree closely with the host. **Stop:** identity mismatch, missing recovery records, wrong client or substantial clock error. **Recovery:** only a private evidence directory and sessions were created. Do not rebuild yesterday’s networking or recreate the client.

## 2. Confirm the baseline, recover password access and verify rollback

**Purpose:** ensure the old service works and the exact working key/configuration remain recoverable.

### 2A — HOST → CLIENT: prove the existing network and PKI

```powershell
Copy-Item -ToSession $ClientS -LiteralPath "$($D18.Day16Evidence)\web.cer" -Destination 'C:\LabPKI\day19-baseline-web.cer'
Invoke-Command -Session $ClientS {
    Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer
    if (@(Get-NetIPInterface -AddressFamily IPv4 | Where-Object Forwarding -eq 'Enabled').Count) {
        throw 'Unexpected IP forwarding; investigate. Do not use CLIENT as a router.'
    }
    $Names = [Net.Dns]::GetHostAddresses($using:CvFqdn) | ForEach-Object IPAddressToString
    $Names
    if (-not (Test-NetConnection $using:CvFqdn -Port 443 -InformationLevel Quiet)) { throw 'Existing Commvault TCP443 path failed.' }
    certutil.exe -verify -urlfetch 'C:\LabPKI\day19-baseline-web.cer'
    if ($LASTEXITCODE -ne 0) { throw 'Existing PKI chain/revocation failed.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Web = Invoke-WebRequest -UseBasicParsing -Uri "https://$($using:D16.WebFqdn)/day16.txt"
    if ($Web.StatusCode -ne 200 -or $Web.Content -notmatch 'Day16 HTTPS baseline OK') { throw 'Existing PKI WEB baseline failed.' }
    foreach ($File in @('root.crl','issuer.crl')) {
        $Out = Join-Path 'C:\LabPKI' "day19-$File"
        Invoke-WebRequest -UseBasicParsing -Uri "http://$($using:D16.WebFqdn)/pki/$File" -OutFile $Out
        certutil.exe -dump $Out
        if ($LASTEXITCODE -ne 0) { throw 'CRL inspection failed.' }
    }
}
```

Confirm the resolved Commvault address matches yesterday’s record. Inspect **This Update / Next Update** for both CRLs: they must be current throughout today’s work. Yesterday the issuer CRL was approaching its October 8 deadline; do not assume it refreshed itself. If stale, pause for the established issuer-CRL publication procedure before this certificate change. Do not enable routing or bring ROOT online as a shortcut.

Open the existing Command Center in LABCLIENT18’s browser. Record the current self-signed certificate fingerprint and application behavior using the established Day 18 access path. Do not call the old certificate trusted. Verify login and a read-only existing job-history view. In the product interface, confirm the installed build and the latest **existing CommServe DR backup job/date/location/status**. These TLS file copies are not a database backup or a restore test.

### 2B — HOST → CV: discover active files and recover the password privately

This reuses yesterday’s successful discovery. The XML can hold either legacy `keystorePass` or modern `certificateKeystorePassword`. The code requires one active TLS connector and a literal password; it does not print XML, password or key material. A `${...}` reference requires its actual source to be investigated.

```powershell
$CvRecord = Invoke-Command -Session $CvS {
    $Svc = Get-CimInstance Win32_Service -Filter "Name='GxTomcatInstance001'"
    if (-not $Svc -or $Svc.State -ne 'Running') { throw 'Expected running Tomcat service.' }
    if ($Svc.PathName -notmatch '^"?(.+?\\Apache\\bin\\tomcat\.exe)"?(?:\s|$)') { throw 'Inspect actual Tomcat executable path.' }
    $CvInstall = Split-Path (Split-Path (Split-Path $Matches[1] -Parent) -Parent) -Parent
    $Apache = Join-Path $CvInstall 'Apache'
    $XmlPath = Join-Path $Apache 'conf\Server.xml'
    $CvTool = Join-Path $CvInstall 'Base\cvCertTool.cmd'
    $KeyTool = Join-Path $CvInstall 'jre\bin\keytool.exe'
    Get-Item -LiteralPath $XmlPath,$CvTool,$KeyTool | Select-Object FullName,Length | Out-Host
    [xml]$Xml = Get-Content -LiteralPath $XmlPath -Raw
    $TlsNodes = @($Xml.SelectNodes('//Service/Connector') | Where-Object { $_.GetAttribute('port') -eq '443' })
    if ($TlsNodes.Count -ne 1) { throw 'Expected one TLS connector on 443.' }
    $C = $TlsNodes[0]
    $CertNodes = @($C.SelectNodes('.//Certificate') | Where-Object { $_.HasAttribute('certificateKeystoreFile') })
    if ($C.HasAttribute('keystoreFile') -and $CertNodes.Count -eq 0) {
        $Ref = $C.GetAttribute('keystoreFile')
        $OldPassword = $C.GetAttribute('keystorePass')
    } elseif (-not $C.HasAttribute('keystoreFile') -and $CertNodes.Count -eq 1) {
        $Ref = $CertNodes[0].GetAttribute('certificateKeystoreFile')
        $OldPassword = $CertNodes[0].GetAttribute('certificateKeystorePassword')
    } else { throw 'Ambiguous TLS keystore configuration.' }
    if ([string]::IsNullOrWhiteSpace($OldPassword) -or $OldPassword.Contains('${') -or $Ref.Contains('${')) {
        throw 'A literal recovered password/path is required; inspect its exact source privately.'
    }
    $OldStore = if ([IO.Path]::IsPathRooted($Ref)) { [IO.Path]::GetFullPath($Ref) }
                else { [IO.Path]::GetFullPath((Join-Path $Apache $Ref)) }
    if ((Split-Path $OldStore -Leaf) -ne 'CV_TempKeystoreFile.jks') { throw 'Active store differs from yesterday.' }
    if (@(Get-NetTCPConnection -State Listen -LocalPort 443 | Where-Object OwningProcess -eq $Svc.ProcessId).Count -eq 0) {
        throw 'Tomcat no longer owns 443.'
    }
    $CvEvidence = Join-Path $env:ProgramData "CloudSecurityLab\day19-$using:Stamp"
    if (Test-Path -LiteralPath $CvEvidence) { throw 'Existing Day 19 CV evidence: resume it.' }
    New-Item -ItemType Directory -Path $CvEvidence | Out-Null
    icacls.exe $CvEvidence /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CV evidence ACL failed.' }
    $PriorEap = $ErrorActionPreference
    try {
        $env:LAB_D19_STOREPASS = $OldPassword
        $ErrorActionPreference = 'Continue'
        & $KeyTool -list -v -storetype JKS -keystore $OldStore -alias selfsigned `
            -storepass:env LAB_D19_STOREPASS *> "$CvEvidence\old-keytool.txt"
        $Code = $LASTEXITCODE
        if ($Code -ne 0) { throw 'Recovered password did not open the old key store.' }
        & $KeyTool -exportcert -storetype JKS -keystore $OldStore -alias selfsigned `
            -storepass:env LAB_D19_STOREPASS -file "$CvEvidence\old-leaf.cer" *> "$CvEvidence\old-export.txt"
        $ExportCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $PriorEap
        Remove-Item Env:\LAB_D19_STOREPASS -ErrorAction SilentlyContinue
        $OldPassword = $null; $Xml = $null; $C = $null; $CertNodes = $null; $TlsNodes = $null
    }
    if ($ExportCode -ne 0) { throw 'Public old-certificate export failed.' }
    $OldCert = New-Object Security.Cryptography.X509Certificates.X509Certificate2("$CvEvidence\old-leaf.cer")
    $R = [pscustomobject]@{ Evidence=$CvEvidence; Install=$CvInstall; Tool=$CvTool; KeyTool=$KeyTool
        Xml=$XmlPath; OldStore=$OldStore; Service=$Svc.Name; ServiceAccount=$Svc.StartName
        OldThumb=$OldCert.Thumbprint; OldExpiry=$OldCert.NotAfter; PasswordVerified=$true }
    $R | Export-Clixml -LiteralPath "$CvEvidence\context.xml"
    $OldCert.Dispose()
    $R
}
$CvRecord | Export-Clixml -LiteralPath "$Evidence\cv-context.xml"
$CvRecord | Select-Object Service,ServiceAccount,OldThumb,OldExpiry,PasswordVerified
$State19.CvEvidence = $CvRecord.Evidence
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
```

Compare `OldThumb` with the browser’s current certificate. Read `old-keytool.txt` privately on CV if needed: require alias `selfsigned`, `PrivateKeyEntry`, and no “integrity has NOT been verified” warning. A nonempty password was supplied here; empty-password listing is not proof. Separate private-key password attributes, if present, remain preserved in the original XML; a store listing alone does not test a separate key password. [Java keytool password options](https://docs.oracle.com/en/java/javase/17/docs/specs/man/keytool.html).

### 2C — HOST: verify yesterday’s off-VM copies against today’s active files

```powershell
$OldManifest = @(Import-Clixml -LiteralPath "$OldHostCopy\file-manifest.xml")
foreach ($Source in @($CvRecord.Xml,$CvRecord.OldStore)) {
    $Row = @($OldManifest | Where-Object Source -ieq $Source)
    if ($Row.Count -ne 1) { throw 'Exact active file missing from Day 18 manifest.' }
    $Copy = Join-Path "$OldHostCopy\files" (Split-Path $Row[0].Backup -Leaf)
    if ((Get-FileHash -LiteralPath $Copy -Algorithm SHA256).Hash -ne $Row[0].SHA256) { throw 'Old backup hash mismatch.' }
    $LiveHash = Invoke-Command -Session $CvS -ArgumentList $Source {
        param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    if ($LiveHash -ne $Row[0].SHA256) { throw 'Live TLS file drifted since Day 18. Investigate before continuing.' }
}
@'
Installed Commvault build verified:
Old browser certificate matches old-leaf.cer:
Existing UI login and read-only job history work:
Latest existing CommServe DR backup: job/date/location/status:
DR restore test: VERIFIED separately / NOT TESTED:
Old password access and alias verified:
Day 18 XML/JKS copies hash-match the current files:
Current CRL expiry dates:
Remaining gaps:
'@ | Set-Content -LiteralPath "$Evidence\readiness.txt"
notepad.exe "$Evidence\readiness.txt"
```

Fill and save the private worksheet. Missing DR evidence means **BLOCKED before deployment**; key/CSR preparation may be retained, but do not stop Tomcat until the gap is resolved. Do not claim a new DR backup succeeded merely because these files exist.

**Success:** same functioning old endpoint, password access proved, verified rollback files, current PKI and recorded readiness. **Stop:** any mismatch, stale CRL, unknown password, changed owner or failed baseline. **Recovery:** no service settings changed. Preserve the evidence; never convert the old JKS in place.

## 3. Create the new Commvault key and public CSR

**Purpose:** give Tomcat its own key. Only the public request goes to the CA. This is the documented 2024E workspace workflow. A new certificate uses one new workspace; repeating key generation is not a resume strategy. [Create workspace](https://documentation.commvault.com/2024e/commcell-console/creating_workspace.html).

### 3A — HOST → CV: create once and define the settings

This small wrapper records intent before each vendor action, captures potentially sensitive vendor output privately, and checks its exit code. It never passes a password as a command-line argument.

```powershell
Invoke-Command -Session $CvS {
    $Ws = Join-Path $CvEvidence 'certificate-workspace'
    $NewStoreName = "day19-$using:Stamp.pfx"
    function global:Invoke-Day19CvAction {
        param([Parameter(Mandatory=$true)][string]$Action)
        $Intent = Join-Path $CvEvidence "$Action-intent.txt"
        if (Test-Path -LiteralPath $Intent) { throw 'Action already attempted. Inspect existing results before any retry.' }
        "Action=$Action; Workspace=$Ws; UTC=$([datetime]::UtcNow.ToString('o'))" |
            Set-Content -LiteralPath $Intent
        $SavedEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $CvTool -workspace $Ws $Action *> "$CvEvidence\$Action.log"
            $Exit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $SavedEap }
        if ($Exit -ne 0) { throw "Vendor action $Action failed. Read its private log; do not force/repeat it." }
        "$Action : exit 0"
    }
    if (Test-Path -LiteralPath $Ws) { throw 'Workspace already exists.' }
    Invoke-Day19CvAction 'create-workspace'
    $Properties = Join-Path $Ws 'cvct.properties'
    Copy-Item -LiteralPath $Properties -Destination "$CvEvidence\cvct.properties.original"
    $Bytes = New-Object byte[] 32
    $Rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
    $NewPassword = [BitConverter]::ToString($Bytes).Replace('-','')
    $Values = [ordered]@{
        workspace=$Ws.Replace('\','/'); instance='instance001'
        'keystore-password'=$NewPassword; 'keystore-alias'='day19-tomcat'
        'keystore-filename'=$NewStoreName; 'keystore-type'='PKCS12'
        keyalg='RSA'; keysize='3072'; 'keytool-executable-path'=$KeyTool.Replace('\','/')
        'distinguished-name'="CN=$using:CvFqdn"; extension="SAN=dns:$using:CvFqdn"
        'csr-filename'='commvault.csr'; 'days-valid'='397'
        'ca-root-cert-filename'='root.cer'; 'ca-intermediate-cert-filename'='issuer.cer'
        'ca-server-cert-filename'='commvault.cer'
        'allow-invalid-certs'='false'; 'force-actions'='false'
        'skip-validate-keystore'='false'; 'log-stacktraces'='false'
    }
    $Lines = foreach ($Pair in $Values.GetEnumerator()) { '{0}={1}' -f $Pair.Key,$Pair.Value }
    [IO.File]::WriteAllLines($Properties,[string[]]$Lines,[Text.Encoding]::ASCII)
    $NewPassword=$null; $Values=$null; $Lines=$null; $Bytes=$null
    [pscustomobject]@{Workspace=$Ws; NewStoreName=$NewStoreName; Alias='day19-tomcat'} |
        Export-Clixml -LiteralPath "$CvEvidence\new-key-context.xml"
    Get-Acl -LiteralPath $Ws | Select-Object Owner,AccessToString
}
```

The generated password is random and alphanumeric. It resides in the vendor’s protected properties file, which is **secret recovery material**. Preserve it privately with the new store. Do not display or commit it. Java properties use forward-slash paths and unquoted values. `extension` supplies the DNS SAN; `domain-name` and `server-ip` are deliberately absent because the vendor prohibits combining them with that override. The CA controls final validity. [Settings reference](https://documentation.commvault.com/2024e/commcell-console/settings_for_workspace_configuration_file.html).

### 3B — HOST → CV: generate once, then inspect the public request

```powershell
Invoke-Command -Session $CvS {
    Invoke-Day19CvAction 'generate-keys'
    if (-not (Test-Path -LiteralPath (Join-Path $Ws $NewStoreName))) { throw 'New keystore missing.' }
}
```

```powershell
Invoke-Command -Session $CvS {
    Invoke-Day19CvAction 'generate-csr'
    certutil.exe -dump "$Ws\commvault.csr"
    if ($LASTEXITCODE -ne 0) { throw 'CSR inspection failed.' }
}
$Ws = Join-Path $CvRecord.Evidence 'certificate-workspace'
Copy-Item -FromSession $CvS -LiteralPath "$Ws\commvault.csr" -Destination "$Evidence\commvault.csr"
$CsrHash = (Get-FileHash -LiteralPath "$Evidence\commvault.csr" -Algorithm SHA256).Hash
$RemoteHash = Invoke-Command -Session $CvS { (Get-FileHash -LiteralPath "$Ws\commvault.csr" -Algorithm SHA256).Hash }
if ($CsrHash -ne $RemoteHash) { throw 'CSR transfer mismatch.' }
$State19.CsrSHA256=$CsrHash; $State19.Phase='CSR generated'
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
```

**Success:** CSR has the exact existing DNS name as its only SAN, matching CN, RSA 3072, SHA-256 or stronger RSA signature, and no CA request. The new key is in the Commvault workspace; the old live JKS is untouched. [Key generation](https://documentation.commvault.com/2024e/commcell-console/generating_key_pair.html), [CSR generation](https://documentation.commvault.com/2024e/commcell-console/generating_csr.html).

**Stop:** unexpected subject, extra SAN, weak algorithm, missing file or vendor error. **Recovery:** retain this exact key/workspace and intent logs. No service rollback is needed. Do not regenerate keys to fix an uncertain response.

## 4. Submit once, approve the exact request and retrieve the certificate

**Purpose:** exercise the existing narrow enrollment and manual-approval policy. HOST transfers the public CSR using PowerShell Direct; ISSUER does not need a second NIC or a route to Commvault.

### 4A — HOST → ISSUER: check policy and submit once

On ISSUER, open `certsrv.msc` and `certtmpl.msc` through VMConnect. Confirm the existing **Lab Web TLS / LabWebTLS15** template is published on the intended lab issuer; Server Authentication only; supply subject in request; RSA minimum 3072; existing narrow Read/Enroll permissions; manager approval enabled. Preserve its existing key policy. This Java request does not make a Java keystore noncopyable merely because Windows enrollment marks keys non-exportable. If policy rejects an external CSR, preserve the rejection; do not alter template/CA security to force issuance.

```powershell
vmconnect.exe localhost $IssuerVM
Invoke-Command -Session $IssuerS {
    $CaKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
    if ((Get-ItemProperty $CaKey).Active -ne $using:IssuerCA) { throw 'Wrong issuing CA.' }
    if ((Get-Service CertSvc).Status -ne 'Running') { throw 'Issuer service is not running.' }
    certutil.exe -catemplates
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect published templates.' }
    if (Test-Path -LiteralPath $using:GuestWork) { throw 'Existing issuer work: inspect/resume.' }
    New-Item -ItemType Directory -Path $using:GuestWork | Out-Null
}
Copy-Item -ToSession $IssuerS -LiteralPath "$Evidence\commvault.csr" -Destination "$GuestWork\commvault.csr"
Invoke-Command -Session $IssuerS {
    if ((Get-FileHash "$using:GuestWork\commvault.csr" -Algorithm SHA256).Hash -ne $using:CsrHash) { throw 'Issuer CSR differs.' }
    certutil.exe -dump "$using:GuestWork\commvault.csr"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect copied CSR.' }
}
```

Read the CSR and template before the next block. **Run submission once.**

```powershell
if (Test-Path -LiteralPath "$Evidence\submit-intent.txt") { throw 'Submission already attempted. Inspect CA records.' }
"CA=$IssuerVM\$IssuerCA; Template=$TemplateName; CSR-SHA256=$CsrHash" |
    Set-Content -LiteralPath "$Evidence\submit-intent.txt"
$Submit = Invoke-Command -Session $IssuerS {
    $OldEap=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $Output = & certreq.exe -submit -config "$env:COMPUTERNAME\$using:IssuerCA" `
            -attrib "CertificateTemplate:$using:TemplateName" `
            "$using:GuestWork\commvault.csr" "$using:GuestWork\commvault.cer" 2>&1
        $Code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$OldEap }
    $Output | Out-File -LiteralPath "$using:GuestWork\submit-output.txt"
    [pscustomobject]@{ExitCode=$Code; Output=($Output | Out-String)}
}
$Submit | Export-Clixml -LiteralPath "$Evidence\submit-result.xml"
$Submit.Output
"certreq exit code: $($Submit.ExitCode)"
```

Expected disposition is **pending**, with a Request ID. Do not treat an exit code alone as issuance proof. An error, timeout or unknown disposition requires inspecting this CA’s Pending/Failed/Issued records before any retry. Automatic issuance contradicts the expected approval gate: mark **FAILED EXPECTATION** and stop deployment.

### 4B — HOST: record the exact ID before approval

Replace `0` with the ID returned for this CSR. Save it with the next block **before issuing anything**.

```powershell
$RequestId = 0 # Exact ID from this submission, not an older WEB request.
if ($RequestId -lt 1) { throw 'Enter the exact pending Request ID.' }
$State19.RequestId=$RequestId; $State19.Phase='Pending request recorded'
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
```

Now, in `certsrv.msc` → **Pending Requests**, inspect that saved ID’s requester, template, subject, SAN and public key against this CSR. Only then right-click that exact request → **All Tasks → Issue**. After the GUI review and issuance:

```powershell
"Approved exact request $RequestId after requester/template/SAN/public-key review" |
    Set-Content -LiteralPath "$Evidence\approval-record.txt"
Invoke-Command -Session $IssuerS {
    certreq.exe -retrieve -config "$env:COMPUTERNAME\$using:IssuerCA" `
        $using:RequestId "$using:GuestWork\commvault.cer"
    if ($LASTEXITCODE -ne 0) { throw 'Retrieve failed. Preserve this Request ID.' }
    certutil.exe -dump "$using:GuestWork\commvault.cer"
    if ($LASTEXITCODE -ne 0) { throw 'Issued-certificate inspection failed.' }
}
Copy-Item -FromSession $IssuerS -LiteralPath "$GuestWork\commvault.cer" -Destination "$Evidence\commvault.cer"
$Leaf = [Security.Cryptography.X509Certificates.X509Certificate2]::new("$Evidence\commvault.cer")
$NewThumb=$Leaf.Thumbprint
$Leaf | Select-Object Subject,Issuer,NotBefore,NotAfter,Thumbprint
$Leaf.Extensions | ForEach-Object { [pscustomobject]@{OID=$_.Oid.Value;Value=$_.Format($true)} }
$State19.NewThumb=$NewThumb; $State19.Phase='Certificate issued'
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
$Leaf.Dispose()
```

Check exact single DNS SAN, Server Authentication only (`1.3.6.1.5.5.7.3.1`), CA=false, RSA 3072, SHA-256-or-stronger signature, expected issuer and valid dates. AIA/CDP must point to the existing public PKI HTTP files. Do **not** run `certreq -accept`: this key belongs to Java, not a pending Windows key container. [Microsoft certreq](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certreq_1).

**Success:** observed pending gate, reviewed approval, one issued leaf associated with the original request. **Stop:** wrong policy/name/key, rejection or unrecognized disposition. **Recovery:** save the exact Request ID. Removing a file does not cancel or revoke a CA request/certificate; preserve it for resume. Enrollment and approval by the same lab administrator is not a separation-of-duties test.

## 5. Import the full chain and prove it before changing Tomcat

**Purpose:** attach the signed certificate to the original new Java key and validate it independently.

### 5A — HOST: copy only public certificates into the workspace

```powershell
$PublicFiles = [ordered]@{
    'root.cer' = "$($D18.Day14Evidence)\root.cer"
    'issuer.cer' = "$($D18.Day14Evidence)\issuer.cer"
    'commvault.cer' = "$Evidence\commvault.cer"
}
foreach ($Pair in $PublicFiles.GetEnumerator()) {
    Copy-Item -ToSession $CvS -LiteralPath $Pair.Value -Destination "$Ws\cacerts\$($Pair.Key)"
    $LocalHash=(Get-FileHash -LiteralPath $Pair.Value -Algorithm SHA256).Hash
    $RemoteHash=Invoke-Command -Session $CvS -ArgumentList "$Ws\cacerts\$($Pair.Key)" {
        param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    if ($LocalHash -ne $RemoteHash) { throw 'Public certificate transfer mismatch.' }
}
Copy-Item -ToSession $ClientS -LiteralPath "$Evidence\commvault.cer" -Destination 'C:\LabPKI\day19-commvault.cer'
Invoke-Command -Session $ClientS {
    certutil.exe -verify -urlfetch -sslpolicy $using:CvFqdn 'C:\LabPKI\day19-commvault.cer'
    if ($LASTEXITCODE -ne 0) { throw 'New certificate name/chain/revocation verification failed.' }
}
```

Require the chain to end at the recorded lab root, with the recorded issuing CA, and successful revocation verification. LABCLIENT18 already trusts that root; do not import a new root to make an unexpected chain pass. Commvault itself need not gain a route to PKI for this transfer: explicit public chain files reach it through HOST.

### 5B — HOST → CV: import and validate the new store

```powershell
Invoke-Command -Session $CvS { Invoke-Day19CvAction 'import-ca-certs' }
```

```powershell
Invoke-Command -Session $CvS { Invoke-Day19CvAction 'validate-keystore' }
```

Inspect the new alias without exposing its password:

```powershell
Invoke-Command -Session $CvS {
    $PassLine = @(Get-Content -LiteralPath "$Ws\cvct.properties" | Where-Object { $_ -match '^keystore-password=' })
    if ($PassLine.Count -ne 1) { throw 'Ambiguous store password setting.' }
    $OldEap=$ErrorActionPreference
    try {
        $env:LAB_D19_STOREPASS = $PassLine[0].Substring('keystore-password='.Length)
        $ErrorActionPreference='Continue'
        & $KeyTool -list -v -storetype PKCS12 -keystore (Join-Path $Ws $NewStoreName) `
            -alias day19-tomcat -storepass:env LAB_D19_STOREPASS *> "$CvEvidence\new-keytool.txt"
        $Code=$LASTEXITCODE
        if ($Code -ne 0) { throw 'New store listing failed.' }
        & $KeyTool -exportcert -storetype PKCS12 -keystore (Join-Path $Ws $NewStoreName) `
            -alias day19-tomcat -storepass:env LAB_D19_STOREPASS -file "$CvEvidence\new-store-leaf.cer" *> "$CvEvidence\new-export.txt"
        $ExportCode=$LASTEXITCODE
    } finally {
        $ErrorActionPreference=$OldEap
        Remove-Item Env:\LAB_D19_STOREPASS -ErrorAction SilentlyContinue
        $PassLine=$null
    }
    if ($ExportCode -ne 0) { throw 'New public leaf export failed.' }
    $Cert=New-Object Security.Cryptography.X509Certificates.X509Certificate2("$CvEvidence\new-store-leaf.cer")
    try { if ($Cert.Thumbprint -ne $using:NewThumb) { throw 'Store does not contain the approved leaf.' } }
    finally { $Cert.Dispose() }
    Get-Content -LiteralPath "$CvEvidence\new-keytool.txt"
}
$State19.Phase='New store validated'
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
```

Read the public certificate listing: alias `day19-tomcat`, **PrivateKeyEntry**, chain length **3**, ordered leaf → issuing CA → root. Compare the issuer/root fingerprints to your saved public files, not just their display names. It is normal for this new PKCS12 file to be copyable as a file; its password and filesystem ACLs protect it. It is a different key from PKI WEB’s non-exportable Windows key.

**Success:** import and vendor validation passed; exact issued leaf is linked to the new private key with the expected chain; CLIENT’s name/trust/revocation check passed. **Stop:** mismatch, incomplete chain or validation failure. Never enable `allow-invalid-certs`, `force-actions` or `skip-validate-keystore`. **Recovery:** old Tomcat still serves the old JKS. Preserve this workspace for diagnosis. [Commvault certificate import](https://documentation.commvault.com/2024e/commcell-console/importing_ca_signed_certificate.html).

## 6. Take the final backup, then change only Tomcat

**Purpose:** enter a short maintenance window with both old and new recovery material preserved.

### 6A — HOST → CV: capture the immediate pre-change files

Proceed only after the readiness worksheet is complete and at least 40 minutes remain. A new filename avoids the vendor’s existing-file rename behavior. An unexpected existing destination means stop, not overwrite.

```powershell
$Before = Invoke-Command -Session $CvS {
    $DestinationStore=Join-Path $Apache "conf\$NewStoreName"
    if (Test-Path -LiteralPath $DestinationStore) { throw 'Planned destination already exists.' }
    $Backup=Join-Path $CvEvidence 'before-change'
    if (Test-Path -LiteralPath $Backup) { throw 'Existing pre-change backup: inspect/resume.' }
    New-Item -ItemType Directory -Path $Backup | Out-Null
    $Manifest=@()
    foreach ($Source in @($XmlPath,$OldStore)) {
        $Hash=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $Target=Join-Path $Backup (Split-Path $Source -Leaf)
        $Sddl=(Get-Acl -LiteralPath $Source).Sddl
        Copy-Item -LiteralPath $Source -Destination $Target
        if ((Get-FileHash $Target -Algorithm SHA256).Hash -ne $Hash -or
            (Get-FileHash $Source -Algorithm SHA256).Hash -ne $Hash) { throw 'Backup changed during capture.' }
        $Manifest += [pscustomobject]@{Source=$Source; Backup=$Target; SHA256=$Hash; Sddl=$Sddl}
        $Manifest | Export-Clixml -LiteralPath "$CvEvidence\before-manifest.xml"
    }
    Get-ChildItem -LiteralPath "$Apache\conf" -File |
        Select-Object FullName,Length,LastWriteTime | Export-Clixml "$CvEvidence\conf-before.xml"
    Get-CimInstance Win32_Service -Filter "Name='GxTomcatInstance001'" |
        Select-Object Name,State,StartMode,StartName,PathName | Export-Clixml "$CvEvidence\service-before.xml"
    $Manifest
}
foreach ($Item in $Before) {
    $Old=@($OldManifest | Where-Object Source -ieq $Item.Source)
    if ($Old.Count -ne 1 -or $Old[0].SHA256 -ne $Item.SHA256) { throw 'Original configuration drifted. Investigate before stopping.' }
}
$OffVM=Join-Path $Evidence 'commvault-before-change'
if (Test-Path -LiteralPath $OffVM) { throw 'Off-VM destination already exists.' }
$Hashes=Invoke-Command -Session $CvS {
    Get-ChildItem -LiteralPath $CvEvidence -File -Recurse | ForEach-Object {
        [pscustomobject]@{Relative=$_.FullName.Substring($CvEvidence.Length+1)
            SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    }
}
Copy-Item -FromSession $CvS -LiteralPath $CvRecord.Evidence -Destination $OffVM -Recurse
foreach ($Item in $Hashes) {
    if ((Get-FileHash -LiteralPath (Join-Path $OffVM $Item.Relative) -Algorithm SHA256).Hash -ne $Item.SHA256) {
        throw 'Off-VM recovery copy mismatch.'
    }
}
$Hashes | Export-Clixml -LiteralPath "$Evidence\before-off-vm-hashes.xml"
"Stop only $($CvRecord.Service); old files in before-manifest.xml; new store planned in Apache/conf" |
    Set-Content -LiteralPath "$Evidence\change-intent.txt"
$State19.Phase='Pre-change backup verified'
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
```

This protected off-VM copy includes the new password-bearing properties and new private-key store as well as the old recovery files. That is deliberate recovery material, not material to send to ISSUER or Git. File backups are not a successful restore test.

### 6B — HOST → CV: stop, configure, inspect; then start

First run this block by itself. From here, any error takes you to **Rollback** below.

```powershell
Invoke-Command -Session $CvS {
    $Manifest=Import-Clixml -LiteralPath "$CvEvidence\before-manifest.xml"
    foreach ($Item in $Manifest) {
        if ((Get-FileHash -LiteralPath $Item.Source -Algorithm SHA256).Hash -ne $Item.SHA256) { throw 'Live file changed after backup.' }
    }
    $Service=Get-Service -Name 'GxTomcatInstance001'
    if ($Service.Status -ne 'Running') { throw 'Unexpected service state before change.' }
    Stop-Service -Name $Service.Name -ErrorAction Stop
    $Service.WaitForStatus('Stopped',[timespan]::FromSeconds(60))
    Invoke-Day19CvAction 'configure-tomcat'
}
```

The vendor requires Tomcat stopped for this action. It validates and deploys the workspace store into `Apache\conf`; a conflicting filename can be renamed, so inspect the actual result. [Commvault Tomcat configuration](https://documentation.commvault.com/2024e/commcell-console/configuring_tomcat_service.html).

```powershell
$Deployed = Invoke-Command -Session $CvS {
    [xml]$AfterXml=Get-Content -LiteralPath $XmlPath -Raw
    $Rows=@(foreach ($Node in $AfterXml.SelectNodes('//Service/Connector')) {
        $Cert=@($Node.SelectNodes('.//Certificate'))
        [pscustomobject]@{Port=$Node.GetAttribute('port'); Protocol=$Node.GetAttribute('protocol')
            LegacyStore=$Node.GetAttribute('keystoreFile'); LegacyAlias=$Node.GetAttribute('keyAlias')
            Stores=(@($Cert | ForEach-Object { $_.GetAttribute('certificateKeystoreFile') }) -join ';')
            Aliases=(@($Cert | ForEach-Object { $_.GetAttribute('certificateKeyAlias') }) -join ';')}
    })
    $Rows | Export-Clixml -LiteralPath "$CvEvidence\connectors-after.xml"
    $Rows | Format-Table -AutoSize | Out-Host
    $R=@($Rows | Where-Object Port -eq '443')
    if ($R.Count -ne 1) { throw 'Unexpected TLS connector count.' }
    $Ref=if ($R[0].Stores) { $R[0].Stores } else { $R[0].LegacyStore }
    if ($Ref.Contains(';') -or -not $Ref) { throw 'Ambiguous deployed store.' }
    $DeployedStore=if ([IO.Path]::IsPathRooted($Ref)) { [IO.Path]::GetFullPath($Ref) }
                   else { [IO.Path]::GetFullPath((Join-Path $Apache $Ref)) }
    $Planned=[IO.Path]::GetFullPath((Join-Path $Apache "conf\$NewStoreName"))
    if ($DeployedStore -ine $Planned) { throw 'Vendor deployed to an unexpected path; inspect before start.' }
    if ((Get-FileHash -LiteralPath $DeployedStore -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $Ws $NewStoreName) -Algorithm SHA256).Hash) { throw 'Deployed store differs.' }
    if ((Get-FileHash -LiteralPath $OldStore -Algorithm SHA256).Hash -ne
        (@(Import-Clixml "$CvEvidence\before-manifest.xml" | Where-Object Source -ieq $OldStore)[0].SHA256)) {
        throw 'Old JKS changed unexpectedly.'
    }
    # Restrict this NEW key file to administrators, SYSTEM and its actual service.
    $NewAcl=New-Object Security.AccessControl.FileSecurity
    $NewAcl.SetAccessRuleProtection($true,$false)
    foreach ($SidText in @('S-1-5-18','S-1-5-32-544')) {
        $Sid=New-Object Security.Principal.SecurityIdentifier($SidText)
        $Rule=New-Object Security.AccessControl.FileSystemAccessRule($Sid,'FullControl','Allow')
        $NewAcl.AddAccessRule($Rule)
    }
    $Account=(Get-CimInstance Win32_Service -Filter "Name='GxTomcatInstance001'").StartName
    if ($Account -ine 'LocalSystem' -and $Account -ine 'NT AUTHORITY\SYSTEM') {
        $Name=New-Object Security.Principal.NTAccount($Account)
        $Sid=$Name.Translate([Security.Principal.SecurityIdentifier])
        $Rule=New-Object Security.AccessControl.FileSystemAccessRule($Sid,'Read','Allow')
        $NewAcl.AddAccessRule($Rule)
    }
    Set-Acl -LiteralPath $DeployedStore -AclObject $NewAcl
    Get-Acl -LiteralPath $DeployedStore | Select-Object AccessToString | Out-Host
    [pscustomobject]@{Store=$DeployedStore; Alias=($R[0].Aliases+$R[0].LegacyAlias)} |
        Export-Clixml -LiteralPath "$CvEvidence\deployed.xml"
    [pscustomobject]@{Store=$DeployedStore; Alias=($R[0].Aliases+$R[0].LegacyAlias)}
}
$Deployed | Export-Clixml -LiteralPath "$Evidence\deployed.xml"
```

Privately compare the saved `before-change\Server.xml` with the new XML on CV. Do not paste either into a chat. Only the intended TLS certificate/store settings should differ; ports, other connectors, hosts and unrelated application settings must remain unchanged. The new alias must be `day19-tomcat` if explicitly set. If omitted, there must be exactly one private-key entry and it must be that alias. Require service-account read access and no broad Users/Everyone access to the new private-key file; do not broaden permissions to cure a startup failure.

Then start only Tomcat:

```powershell
Invoke-Command -Session $CvS {
    Start-Service -Name 'GxTomcatInstance001' -ErrorAction Stop
    (Get-Service 'GxTomcatInstance001').WaitForStatus('Running',[timespan]::FromSeconds(60))
    $Svc=Get-CimInstance Win32_Service -Filter "Name='GxTomcatInstance001'"
    $Listening=$false
    for ($i=0; $i -lt 12; $i++) {
        $Listening=@(Get-NetTCPConnection -State Listen -LocalPort 443 -ErrorAction SilentlyContinue |
            Where-Object OwningProcess -eq $Svc.ProcessId).Count -gt 0
        if ($Listening) { break }
        Start-Sleep -Seconds 5
    }
    if (-not $Listening) { throw 'Tomcat failed to regain 443; use rollback.' }
    Get-Service 'GxTomcatInstance001' | Select-Object Name,Status
}
$State19.Phase='Tomcat changed; validation pending'
$State19 | Export-Clixml -LiteralPath "$Evidence\resume.xml"
```

**Success:** same service owns 443; intended new store deployed; old JKS preserved. **Stop:** unexpected XML changes, ACL issue, configuration error or failed restart. **Recovery:** execute the exact file rollback below. A running service is not proof of successful TLS or application behavior.

## 7. Validate from LABCLIENT18, then close out

**Purpose:** prove the actual network endpoint presents the approved leaf and remains usable.

### 7A — HOST → CLIENT: strict live TLS and HTTP

No certificate bypass, global trust callback or `-SkipCertificateCheck` is used. Revocation is explicitly requested for the live handshake. The file check uses Microsoft’s documented URL-fetch and hostname-policy options. [Certutil verification](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil#-verify).

```powershell
$Proof = Invoke-Command -Session $ClientS {
    certutil.exe -verify -urlfetch -sslpolicy $using:CvFqdn 'C:\LabPKI\day19-commvault.cer'
    if ($LASTEXITCODE -ne 0) { throw 'Name/chain/revocation validation failed.' }
    $Tcp=New-Object Net.Sockets.TcpClient
    $Tls=$null; $Presented=$null
    try {
        $Tcp.Connect($using:CvFqdn,443)
        $Tls=New-Object Net.Security.SslStream($Tcp.GetStream(),$false)
        $Tls.ReadTimeout=15000; $Tls.WriteTimeout=15000
        $Tls.AuthenticateAsClient($using:CvFqdn,$null,[Security.Authentication.SslProtocols]::Tls12,$true)
        $Presented=New-Object Security.Cryptography.X509Certificates.X509Certificate2($Tls.RemoteCertificate)
        if ($Presented.Thumbprint -ne $using:NewThumb) { throw 'Live server presents a different certificate.' }
        $TlsProof=[pscustomobject]@{DNS=$using:CvFqdn; Thumbprint=$Presented.Thumbprint
            Protocol=$Tls.SslProtocol.ToString(); RevocationRequested=$true; StrictHandshake='PASS'}
    } finally {
        if ($Presented) { $Presented.Dispose() }
        if ($Tls) { $Tls.Dispose() }
        $Tcp.Dispose()
    }
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::CheckCertificateRevocationList=$true
    $Page=Invoke-WebRequest -UseBasicParsing -Uri "https://$using:CvFqdn/commandcenter" -TimeoutSec 30
    $FinalUri=$Page.BaseResponse.ResponseUri
    if ($Page.StatusCode -ne 200 -or $FinalUri.Scheme -ne 'https' -or $FinalUri.DnsSafeHost -ine $using:CvFqdn) {
        throw 'Unexpected HTTP status or redirect destination; inspect before claiming success.'
    }
    $TlsProof
    [pscustomobject]@{HTTP=$Page.StatusCode; FinalUri=$FinalUri.AbsoluteUri}
}
$Proof | Export-Clixml -LiteralPath "$Evidence\client-proof.xml"
$Proof | Format-List
vmconnect.exe localhost $ClientVM
```

An HTTP 401/403 or a different legitimate login redirect may be application-specific; record it and inspect the browser rather than changing authentication to manufacture HTTP 200. The strict TLS proof is separate from successful application login.

In LABCLIENT18’s browser, open the same existing URL. Require no certificate warning, the correct SAN and new fingerprint, successful existing-account login, and the same read-only job-history view. Do not launch a restore or backup merely to test a browser certificate. Confirm the original PKI WEB marker still opens, and HTTP `/pki/issuer.crl` remains available.

### 7B — HOST: save a compact result and close the sessions

Fill the private result; do not set COMPLETE until the evidence above exists.

```powershell
@'
Day 19 status: COMPLETE / PARTIAL / BLOCKED / FAILED EXPECTATION
Existing Commvault build and baseline verified:
DR-backup readiness recorded (restore test stated separately):
Old password verified without disclosure; rollback hashes verified:
One new RSA3072 key; exact DNS SAN; request ID recorded privately:
Pending approval gate observed and exact request approved:
New PrivateKeyEntry and three-certificate chain validated:
Tomcat-only change; old XML/JKS retained; service healthy:
CLIENT strict name/trust/revocation/live-fingerprint test:
Browser login and read-only application health:
Existing PKI WEB / HTTP publication preserved; ROOT off:
Rollback performed? Outcome:
Open issue and exact next step:
Issuer/root CRL Next Update dates and next maintenance action:
Private recovery locations (keep out of Git):
'@ | Set-Content -LiteralPath "$Evidence\results-private.txt"
notepad.exe "$Evidence\results-private.txt"
Get-VM -Name $RootVM | Select-Object Name,State
Get-VMNetworkAdapter -VMName $RootVM | Select-Object Name,SwitchName
Remove-PSSession -Session $CvS,$ClientS,$IssuerS
Remove-Variable CvCred,ClientCred,IssuerCred -ErrorAction SilentlyContinue
```

**Success / COMPLETE:** approved leaf + linked key + expected chain + strict live validation + working application + preserved recovery. **PARTIAL:** useful work remains, with known stable endpoint and exact resume state. **BLOCKED:** a dependency prevents safe progress. **FAILED EXPECTATION:** an asserted control behaves incorrectly, such as approval bypass or a supposedly correct endpoint serving the wrong certificate. A failed expectation remains recorded even if rollback restores service.

Keep the successful new certificate and Commvault service for the next lab. Keep old XML/JKS and protected new-key recovery files through the next stable session; do not delete recovery material to “clean up.” Clear any password clipboard/history left from yesterday through Windows clipboard settings; today’s commands do not use the clipboard. Review certificate renewal and the approaching issuer-CRL refresh separately. Actual clock accuracy was checked; time-synchronization health remains an open item.

For Git later: use one Day 19 documentation branch. After the lab is stable, save the two delivered files into a normal local delivery folder. Set its path below. These commands deliberately refuse a dirty working tree; inspect existing work instead of stashing or overwriting it automatically.

```powershell
$DeliveryFolder = '' # Folder containing the two delivered Day 19 files.
Get-Item -LiteralPath "$DeliveryFolder\DAY-19-RUNBOOK.md","$DeliveryFolder\DAY-19-DIAGRAM.png" | Out-Null
Set-Location 'C:\git\azure-secure-hub-spoke-lab'
$GitState = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $GitState.Count) { throw 'Review repository status before starting this documentation branch.' }
git switch -c feat/day19-commvault-tls
if ($LASTEXITCODE -ne 0) { throw 'Branch creation failed; inspect an existing branch rather than resetting it.' }
Copy-Item -LiteralPath "$DeliveryFolder\DAY-19-RUNBOOK.md" -Destination 'docs\day19-runbook.md'
Copy-Item -LiteralPath "$DeliveryFolder\DAY-19-DIAGRAM.png" -Destination 'docs\day19-diagram.png'
git add -- docs/day19-runbook.md docs/day19-diagram.png
if ($LASTEXITCODE -ne 0) { throw 'Staging failed.' }
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Fix staged whitespace errors before committing.' }
git diff --cached --stat
git diff --cached -- docs/day19-runbook.md
```

Review those exact staged files. Then:

```powershell
git commit -m 'docs: add Day 19 Commvault TLS runbook and diagram'
if ($LASTEXITCODE -ne 0) { throw 'Commit failed.' }
git push -u origin feat/day19-commvault-tls
if ($LASTEXITCODE -ne 0) { throw 'Push failed; keep the local commit and inspect the error.' }
```

Keep the result in your private note or existing sanitized results workflow; the commit above makes no claim that deployment succeeded. Never use `git add .` around private evidence. Do not commit passwords, `Server.xml`, properties, JKS/PFX, raw logs, runtime IDs, private recovery paths or unreviewed output. No Git task should consume the recovery window.

**Recovery consequence:** success retains the new endpoint. Partial issuance retains its key and Request ID for resume. If abandoning a pending request, deny that exact ID through the CA console. If abandoning an issued certificate, record it for exact revocation and issuer-CRL publication; deleting its files does not revoke it. Do not revoke a certificate you are retaining as the new working baseline.

## Rollback — only if the Tomcat change failed

**Purpose:** restore the known Day 18 endpoint without reverting a VM, SQL database or CA. Run before closing the sessions. If disconnected, reconnect to the recorded CV VM and recover `$CvEvidence` from `cv-context.xml` as described under Resume.

First preserve failed files and restore the exact pre-change bytes and ACLs:

```powershell
Invoke-Command -Session $CvS {
    $CvEvidence=$using:CvRecord.Evidence
    $Manifest=@(Import-Clixml -LiteralPath "$CvEvidence\before-manifest.xml")
    if ($Manifest.Count -ne 2) { throw 'Expected exact XML and old JKS recovery entries.' }
    foreach ($Item in $Manifest) {
        if ((Get-FileHash -LiteralPath $Item.Backup -Algorithm SHA256).Hash -ne $Item.SHA256) { throw 'Recovery copy failed verification.' }
    }
    $Failed=Join-Path $CvEvidence ('failed-'+(Get-Date -Format yyyyMMdd-HHmmss))
    New-Item -ItemType Directory -Path $Failed | Out-Null
    Stop-Service -Name 'GxTomcatInstance001' -ErrorAction Stop
    (Get-Service 'GxTomcatInstance001').WaitForStatus('Stopped',[timespan]::FromSeconds(60))
    foreach ($Item in $Manifest) {
        if (Test-Path -LiteralPath $Item.Source) {
            Copy-Item -LiteralPath $Item.Source -Destination (Join-Path $Failed (Split-Path $Item.Source -Leaf))
        }
    }
    if (Test-Path -LiteralPath "$CvEvidence\deployed.xml") {
        $Installed=Import-Clixml -LiteralPath "$CvEvidence\deployed.xml"
        if (Test-Path -LiteralPath $Installed.Store) { Copy-Item -LiteralPath $Installed.Store -Destination $Failed }
    }
    foreach ($Item in $Manifest) {
        Copy-Item -LiteralPath $Item.Backup -Destination $Item.Source -Force
        $Acl=Get-Acl -LiteralPath $Item.Source
        $Acl.SetSecurityDescriptorSddlForm($Item.Sddl)
        Set-Acl -LiteralPath $Item.Source -AclObject $Acl
        if ((Get-FileHash -LiteralPath $Item.Source -Algorithm SHA256).Hash -ne $Item.SHA256) { throw 'Restored file hash mismatch.' }
    }
    Start-Service -Name 'GxTomcatInstance001' -ErrorAction Stop
    (Get-Service 'GxTomcatInstance001').WaitForStatus('Running',[timespan]::FromSeconds(60))
    Get-Service 'GxTomcatInstance001' | Select-Object Name,Status
}
Invoke-Command -Session $ClientS {
    Test-NetConnection $using:CvFqdn -Port 443
}
```

From LABCLIENT18, confirm the old fingerprint matches `$CvRecord.OldThumb`, the previous self-signed warning is back, and the established application login/job-history view works. That is **successful rollback**, not successful deployment or trusted TLS. Keep the unused new store protected for diagnosis; do not delete or reissue it while recovering. If file restoration or service start fails, stop further changes and use the verified off-VM recovery copy with targeted troubleshooting. Never restart every Commvault service or restore a whole VM as a TLS shortcut.

## Resume after a pause

**Purpose:** recover the exact attempted operation instead of generating another identity or key.

Open elevated HOST PowerShell 7.6.6 and set `$Evidence` to the exact saved Day 19 directory. These commands are read-only:

```powershell
$Evidence = '' # Exact existing Day 19 evidence path.
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$State19=Import-Clixml -LiteralPath "$Evidence\resume.xml"
$CvRecord=Import-Clixml -LiteralPath "$Evidence\cv-context.xml"
$Day18Evidence=$State19.Day18Evidence
$D18=Import-Clixml -LiteralPath "$Day18Evidence\resume.xml"
$Ctx=Import-Clixml -LiteralPath "$($D18.Day14Evidence)\context.xml"
$D16=Import-Clixml -LiteralPath "$($D18.Day16Evidence)\resume.xml"
$Transfers=@($D18.CvTransfers | Where-Object VM -ieq $State19.CvVM)
if ($Transfers.Count -ne 1) { throw 'Resolve the exact Day 18 transfer record.' }
$OldHostCopy=$Transfers[0].HostCopy
$OldManifest=@(Import-Clixml -LiteralPath "$OldHostCopy\file-manifest.xml")
foreach ($Item in $OldManifest) {
    $Copy=Join-Path "$OldHostCopy\files" (Split-Path $Item.Backup -Leaf)
    if ((Get-FileHash -LiteralPath $Copy -Algorithm SHA256).Hash -ne $Item.SHA256) { throw 'Old recovery copy hash mismatch.' }
}
$CvVM=$State19.CvVM; $ClientVM=$State19.ClientVM; $IssuerVM=$State19.IssuerVM
$CvFqdn=$State19.CvFqdn; $GuestWork=$State19.GuestWork; $Stamp=$State19.Stamp
$IssuerCA=$Ctx.IssuerCA; $RootVM=$Ctx.RootVM; $TemplateName=$D16.TemplateName
$RequestId=$State19.RequestId; $NewThumb=$State19.NewThumb; $CsrHash=$State19.CsrSHA256
$Ws=Join-Path $CvRecord.Evidence 'certificate-workspace'
$State19 | Select-Object Phase,RequestId,NewThumb
if ((Get-VM -Name $CvVM).Id -ne $State19.CvVMId) { throw 'CV VM identity changed.' }
```

Recreate only the three sessions using Phase 1C. Restore CV variables without creating anything:

```powershell
Invoke-Command -Session $CvS {
    $R=$using:CvRecord
    $CvEvidence=$R.Evidence; $CvInstall=$R.Install; $CvTool=$R.Tool; $KeyTool=$R.KeyTool
    $XmlPath=$R.Xml; $OldStore=$R.OldStore; $Apache=Join-Path $CvInstall 'Apache'
    $Ws=Join-Path $CvEvidence 'certificate-workspace'
    if (Test-Path -LiteralPath "$CvEvidence\new-key-context.xml") {
        $NewStoreName=(Import-Clixml "$CvEvidence\new-key-context.xml").NewStoreName
    }
    Get-ChildItem -LiteralPath $CvEvidence -File | Select-Object Name,LastWriteTime
    Get-Service 'GxTomcatInstance001' | Select-Object Name,Status
}
```

Recreate only the `Invoke-Day19CvAction` function definition from Phase 3A if needed; do **not** rerun that block’s workspace creation or password-setting commands. Inspect the action intent/log, actual files and CA disposition. Continue after the last verified result. Intent exists + result uncertain means inspect/reconcile, not remove the marker and retry. If Tomcat is stopped or changed with validation pending, recovery takes precedence over further issuance. A tutor can help resume from these exact records without changing the workflow.

## Diagram and preparation notes

The companion **DAY-19-DIAGRAM.png** shows the planned change in green. CLIENT’s two NICs connect to separate networks; it does not forward traffic. CSR and signed certificate transfer through HOST is administrative file transfer, not a route between the networks. Public HTTP AIA/CDP remains available; ROOT remains offline. Green means planned change, not proof of completion.

Prepared from the Day 18 results and the October 5 **“Reserve IP and Create VM”** chat, including its successful XML-password/keytool procedure, plus the linked version-specific vendor and Microsoft documentation. PowerShell blocks were syntax-checked in host 7.6.6 and guest-compatible Windows PowerShell 5.1; that is not a live deployment test. No additional professor notes or Azure work are included.

<details>
<summary>Diagram generation record — optional reference, no lab action</summary>

Generated with the built-in image tool and saved beside this runbook as `DAY-19-DIAGRAM.png`. Final prompt:

Use case: diagram
Asset type: polished technical lab architecture diagram, landscape 16:10 high resolution, readable in OneNote.
Primary request: "DAY 19 — TRUSTED TLS FOR COMMVAULT", subtitle "Planned change • Validate before marking complete". Precise clean Azure-style server, shield, certificate, browser and offline-vault icons; white background, dark navy typography, blue existing components, green today's changes, dashed gray recovery/control paths. No real IP addresses, personal names, domains, passwords or runtime IDs.
Layout: top horizontal slim band labelled "Hyper-V host • PowerShell 7.6.6" with two labeled operations "PowerShell Direct: administration + public CSR/certificate transfer" and "Protected recovery copies: original XML + JKS". Below, two distinctly separated network zones. LEFT: "PKI lab network", contains "DC / DNS", "Issuing CA" with sublabels "Existing approval-gated template", "Manual CSR approval", and "PKI WEB" with sublabels "Existing HTTPS unchanged", "HTTP: public CA certificates + CRLs". RIGHT: "Commvault lab network", contains big green "CommServe / Tomcat" node, sublabels "Commvault 11.36.72", "New RSA 3072 key + CA-signed certificate", "Command Center • HTTPS 443". Label green node as "TODAY'S CHANGE". Beneath both zones central browser workstation "LABCLIENT18 • Existing validation client" with left network interface shown attached to left network zone and right interface attached to right network zone. Very explicit label "Two NICs • No routing or bridging". An arrow from client left NIC to PKI WEB labelled "HTTP chain / revocation checks"; an arrow from client right NIC to CommServe labelled "HTTPS: name + trust + live certificate". Neither arrow runs through the CA. Small offline root icon outside both zones, "Offline root CA • OFF / disconnected", no active network cable. Thin dashed arrows from Commvault up to host then down to Issuing CA represent public CSR transfer; return dashed arrows public signed certificate back via host. Label dashed path "Public CSR / certificate only". No direct CA-to-Commvault network route. Certificate private key stays in Commvault, except protected recovery backup; NEVER suggest CA key or PKI WEB key is copied. Footer flow 4 short numbered steps "1 New key + CSR   2 Approve + sign   3 Import + restart Tomcat   4 Validate from client". Bottom footnote: "Retain rollback files. Personal Azure, budgets and Sentinel: deferred."
Use generous whitespace, clear orthogonal connectors, correct labels, no decorative 3D scene. No success checkmarks implying work already ran.

</details>
