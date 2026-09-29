# Day 13 — prepare your Hyper-V certificate lab

Prepared September 28, 2026. **No Whizlabs session is needed. No new helper script.** Work through the numbered steps using direct PowerShell commands. Budget 90–120 minutes, including review and documentation.

## Today's result

Produce a verified map of your home-lab AD/DNS and Hyper-V resources, select isolated certificate-test systems, record their recovery points, and agree on a trust design before installing a certification authority (CA). This is the original Day 13 curriculum. Day 14 establishes the CA; Day 15 covers templates; Day 16 issues a web-server certificate. Commvault certificate changes come later.

Your hypervisor is **Hyper-V**. Existing domain controllers, spare server VMs, operating-system versions and backup readiness still need to be checked. Proposed roles in the diagram are **not deployed resources**.

### Continuity from last week

- Day 10 remains complete and fully cleaned, checkpoint `3b41920`.
- Saved Day 11 evidence reports same-principal `403 ForbiddenByRbac → Secrets User grant → 200`, exact version/hash match, and no printed secret/token.
- Day 12's workload revocation succeeded; human security-defaults/CA/PIM visibility was unavailable. That does not mean those controls were disabled.
- Saved ACI and active-vault absence flags are true, but final `CleanupVerified` is false and both final grant-absence flags are false. Those flags mean final verification is missing, not proof that the grants still exist. The tutor reports successful grant removal earlier; **final cleanup remains unverified in the saved record**. Do not relabel it complete or reuse an expired sandbox to verify another subscription's resources.
- The previous helper incorrectly supplied `--no-wait` to `az container delete`. The project copy and downloadable Days 11–12 pack have been corrected; copies already installed elsewhere are not automatically updated. Today's lab does not use that helper.

Day 13 is independent of that Azure evidence gap. Record it; proceed with home-lab preparation. Terraform source/state remains untouched.

## Design to prepare

| Role label used in public notes | Intended system | Domain/network choice |
|---|---|---|
| LAB-DC | Existing **owned lab** AD DS/DNS server, if available | Existing isolated lab domain; inventory only. |
| ROOT | Dedicated Windows Server VM | Standalone root CA later; workgroup; disconnected while operating as the offline root. |
| ISSUER | Separate dedicated Windows Server VM | Enterprise subordinate CA later; joined to the lab domain. |
| WEB | Disposable Windows web-test VM | Later serves test HTTPS and public CA/CRL files; combining these roles is a lab simplification. |
| CLIENT | Owned lab Windows client or test VM | Later validates names, certificate chains and revocation. |

These labels are aliases, not commands to rename existing machines. Use current runtime names only in private records. If you already have a CA, inventory it and mark it **existing**; do not replace/reconfigure it to match this proposal. If no suitable lab domain or spare VMs exist, complete the design and record the missing capacity instead of installing CA services on a DC or Commvault server.

The proposed two-tier hierarchy separates the offline trust anchor from routine issuance. Enterprise CAs use AD and templates; standalone CAs do not require AD. Future enterprise-CA publication can affect trust throughout the **lab forest**, so this must be your isolated lab directory. [Microsoft CA roles and hierarchy](https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/certification-authority-role).

### Where commands run

| Label | Open this console |
|---|---|
| **MANAGEMENT PC** | Your normal PowerShell terminal with `C:\git\azure-secure-hub-spoke-lab`. |
| **HYPER-V HOST** | Elevated Windows PowerShell on the actual node that owns the selected VM. |
| **GUEST** | Elevated **Windows PowerShell** inside the selected Windows guest, using VMConnect. |
| **LAB DC/DNS** | Elevated Windows PowerShell on the existing owned lab DC/DNS server. |

Variables do not carry between consoles. Run each console's setup block where indicated. Windows PowerShell avoids unnecessary ServerManager-module compatibility work today. No remoting, RSAT installation, firewall changes, certificate imports or new CA installation are prescribed.

## 1. Prepare notes and one branch — 0–10 minutes

**Purpose:** keep public learning notes separate from private infrastructure details.

**MANAGEMENT PC**

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'C:\git\azure-secure-hub-spoke-lab'
$Pack = 'C:\Users\Mark\.codex\.chatgpt-projects\g-p-6aa9a64566988191bf43c7cb9228820b\day13'
Set-Location $Repo
git status --short --branch
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect repository.' }
$Changes = git status --porcelain
if ($LASTEXITCODE -ne 0 -or $Changes) { throw 'Resolve existing work before switching branches. Do not discard it.' }
git switch -c feat/day13-pki-preparation
if ($LASTEXITCODE -ne 0) { throw 'If resuming, inspect and switch to the existing Day 13 branch.' }
git check-ignore --quiet -- local-evidence/day13/check.txt
if ($LASTEXITCODE -ne 0) { throw 'Private evidence must be ignored by Git.' }
if (git ls-files -- local-evidence) { throw 'Private evidence is already tracked; resolve before copying evidence here.' }
$Evidence = Join-Path $Repo ('local-evidence\day13-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $Evidence -ErrorAction Stop | Out-Null

@'
Role,ActualVMName,OwnerNode,GuestOS,DomainOrWorkgroup,VirtualSwitch,VLAN,ExistingOrPlanned,RecoveryEvidence,ReadyForDay14
LAB-DC,,,,,,,UNKNOWN,,NO
ROOT,,,,,,,PLANNED,,NO
ISSUER,,,,,,,PLANNED,,NO
WEB,,,,,,,PLANNED,,NO
CLIENT,,,,,,,UNKNOWN,,NO
'@ | Set-Content -LiteralPath (Join-Path $Evidence 'private-inventory.csv') -Encoding UTF8
notepad (Join-Path $Evidence 'private-inventory.csv')
```

Fill the CSV gradually. The public result at the end uses role aliases; actual VM names, domain names, addresses, thumbprints, VM IDs and backup paths remain private. Do not export passwords or private keys.

**Success:** clean branch selected; private inventory created. **Stop:** unexpected repository changes or tracked evidence. **Recovery:** only local files/branch changed; preserve them and resolve the issue without touching Azure.

## 2. Map Hyper-V capacity and isolation — 10–30 minutes

**Purpose:** identify where the VMs run and how their virtual networks connect.

**HYPER-V HOST — run on each relevant owner node.** This block creates a private evidence folder on that host.

```powershell
$ErrorActionPreference = 'Stop'
$HostEvidence = Join-Path $env:LOCALAPPDATA ('CloudSecurityLab\Day13\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $HostEvidence -Force -ErrorAction Stop | Out-Null
Get-VM | Select-Object Name,State,Generation,ProcessorCount,MemoryAssigned,CheckpointType |
    Export-Csv -LiteralPath (Join-Path $HostEvidence 'vms.csv') -NoTypeInformation
Get-VMSwitch | Select-Object Name,SwitchType,NetAdapterInterfaceDescription |
    Export-Csv -LiteralPath (Join-Path $HostEvidence 'switches.csv') -NoTypeInformation
Get-VM | Select-Object Name,State,Generation,CheckpointType | Format-Table
Get-VMSwitch | Select-Object Name,SwitchType,NetAdapterInterfaceDescription | Format-Table -Wrap
Get-Volume | Where-Object DriveLetter |
    Select-Object DriveLetter,FileSystemLabel,Size,SizeRemaining | Format-Table

if (Get-Module -ListAvailable -Name FailoverClusters) {
    Import-Module FailoverClusters
    # Run the next command only if this host is a member of your lab cluster.
    # Get-ClusterGroup | Where-Object GroupType -EQ 'VirtualMachine' |
    #     Select-Object Name,OwnerNode,State | Format-Table
}
```

On a clustered host, run the commented `Get-ClusterGroup` command to locate current owners, then use each owner node for local `Get-VM`. A local VM list is not automatically the whole cluster. `Get-Volume` also is not a complete capacity report for SMB-backed storage; check the VM storage location/CSV or share's actual free space before choosing targets.

Inspect **one selected existing VM at a time**:

```powershell
$VMName = (Read-Host 'Exact existing lab VM name on THIS Hyper-V owner node').Trim()
$Selected = @(Get-VM | Where-Object Name -CEQ $VMName)
if ($Selected.Count -ne 1) { throw 'Exactly one local VM must match; check owner node/name.' }
$VM = $Selected[0]
$VM | Select-Object Name,Id,State,Generation,Path,CheckpointType,AutomaticStartAction |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $HostEvidence 'selected-vm.json') -Encoding UTF8
Get-VMNetworkAdapter -VM $VM |
    Select-Object Name,SwitchName,MacAddress,IPAddresses | Format-List
Get-VMNetworkAdapter -VM $VM | Get-VMNetworkAdapterVlan | Format-List
Get-VMHardDiskDrive -VM $VM | Select-Object ControllerType,Path | Format-Table -Wrap
Get-VMSnapshot -VM $VM | Select-Object Name,CreationTime,SnapshotType | Format-Table
```

Record the selected VM's mapping in the private inventory; repeat for the actual candidate VMs. The single `selected-vm.json` is a convenience view overwritten when selecting another VM; the completed private inventory is the consolidated map.

**Interpretation:** private switches connect guests to guests; internal switches also connect the host; external switches connect to a physical network. Switch names such as “Lab” do not prove isolation. Inspect VLAN, physical-switch/router rules, host routing/NAT and any second guest NIC. A private switch is not proof against a dual-homed guest bridging networks. Do not change switches or host adapters during inventory. [Hyper-V switch types](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/create-a-virtual-switch-for-hyper-v-virtual-machines).

**Success:** exact VM-to-owner/switch/VLAN map and enough storage/capacity for the chosen test systems. **Stop:** ownership or network boundary is unclear; mark that target NOT READY. **Recovery:** these reads change no VM/network configuration.

## 3. Inventory the guests and existing directory — 30–50 minutes

**Purpose:** distinguish a blank test server from an existing identity/application server.

**GUEST — repeat on each existing selected Windows VM using VMConnect.** Do not run against employer/customer systems.

```powershell
$ErrorActionPreference = 'Stop'
$GuestEvidence = Join-Path $env:LOCALAPPDATA ('CloudSecurityLab\Day13\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $GuestEvidence -Force -ErrorAction Stop | Out-Null
$Computer = Get-CimInstance Win32_ComputerSystem
$OS = Get-CimInstance Win32_OperatingSystem
[pscustomobject]@{
    ComputerName=$Computer.Name; Domain=$Computer.Domain
    PartOfDomain=$Computer.PartOfDomain; DomainRole=$Computer.DomainRole
    OS=$OS.Caption; Version=$OS.Version; Build=$OS.BuildNumber
    MemoryGiB=[math]::Round($Computer.TotalPhysicalMemory/1GB,1)
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $GuestEvidence 'computer.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $GuestEvidence 'computer.json')
Get-NetIPConfiguration | Format-List
Get-DnsClientServerAddress | Select-Object InterfaceAlias,AddressFamily,ServerAddresses | Format-Table -Wrap
Get-Date
w32tm /query /status
if ($LASTEXITCODE -ne 0) { Write-Warning 'Time-service status unavailable; record and investigate before CA setup.' }

if (Get-Module -ListAvailable -Name ServerManager) {
    Import-Module ServerManager
    Get-WindowsFeature -Name AD-Domain-Services,DNS,ADCS-Cert-Authority,Web-Server |
        Select-Object Name,InstallState |
        Export-Csv -LiteralPath (Join-Path $GuestEvidence 'roles.csv') -NoTypeInformation
    Import-Csv -LiteralPath (Join-Path $GuestEvidence 'roles.csv') | Format-Table
} else {
    Write-Host 'ServerManager unavailable here. On a client this is expected; do not claim server-role inventory succeeded.'
}
Get-Service -Name CertSvc,NTDS,DNS,W3SVC -ErrorAction SilentlyContinue |
    Select-Object Name,Status | Format-Table
```

An installed ADCS role, `CertSvc`, domain-controller role, IIS site or application dependency needs investigation before classifying the VM as disposable. Missing service output alone does not prove a blank server. For the future offline root, workgroup membership is intentional; it does not need a healthy domain secure channel.

**LAB DC/DNS — only if an existing owned lab directory is present:**

```powershell
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop
Get-ADDomain | Select-Object DNSRoot,NetBIOSName,DomainMode | Format-List
Get-ADForest | Select-Object RootDomain,ForestMode,Domains | Format-List
Get-ADDomainController -Filter * | Select-Object HostName,Site,IsGlobalCatalog | Format-Table
Import-Module DnsServer -ErrorAction Stop
Get-DnsServerZone | Select-Object ZoneName,ZoneType,IsDsIntegrated | Format-Table
```

Record only the lab roles and private domain mapping. These are inventory reads, not a full AD health check. If modules/permissions are unavailable, record the missing evidence; don't install roles just to make an inventory command work.

**Success:** actual OS, role, domain/workgroup, DNS and time status recorded for existing candidates; missing candidates labeled PLANNED. **Stop:** an existing DC/CA/Commvault server is mistakenly selected for a fresh CA install. **Recovery:** no guest roles, identities, services or bindings changed.

## 4. Verify the existing DNS path and inspect certificate anatomy — 50–65 minutes

**Purpose:** check the dependencies a future issuing CA/client will need and learn what a certificate contains.

**GUEST — an existing domain-joined lab member or CLIENT, not the offline root.**

```powershell
$LabDomain = (Read-Host 'Existing owned LAB AD DNS domain').Trim()
$LabDC = (Read-Host 'Existing LAB domain controller FQDN').Trim()
$Computer = Get-CimInstance Win32_ComputerSystem
if ($Computer.PartOfDomain -and $Computer.Domain -ine $LabDomain) { throw 'Guest belongs to a different domain; check the console and scope.' }
Resolve-DnsName -Name $LabDC -DnsOnly -ErrorAction Stop
Resolve-DnsName -Name ('_ldap._tcp.dc._msdcs.' + $LabDomain) -Type SRV -DnsOnly -ErrorAction Stop
Test-NetConnection -ComputerName $LabDC -Port 389 -InformationLevel Detailed
$Computer = Get-CimInstance Win32_ComputerSystem
if ($Computer.PartOfDomain -and $Computer.DomainRole -lt 4) {
    Test-ComputerSecureChannel -Verbose
} else {
    Write-Host 'Skip member secure-channel test on workgroup machines and domain controllers.'
}
```

Successful DNS and TCP389 prove only those paths, not all AD/CA enrollment dependencies. A future issuer also needs the normal lab-domain services and enrollment paths; do not create broad firewall exceptions from this one test. `Test-ComputerSecureChannel` is for domain members and can give false errors on DCs; no `-Repair` is used here. [Microsoft command guidance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-computersecurechannel?view=powershell-5.1).

**GUEST — CLIENT or WEB, certificate metadata only:**

```powershell
Get-ChildItem Cert:\LocalMachine\My |
    Select-Object Subject,Issuer,NotBefore,NotAfter,Thumbprint,HasPrivateKey |
    Format-Table -Wrap

$Thumbprint = (Read-Host 'Optional: exact thumbprint to inspect; press Enter if store is empty').Replace(' ','')
if ($Thumbprint) {
    if ($Thumbprint -notmatch '^[0-9A-Fa-f]{40}$') { throw 'Use an exact SHA-1 certificate thumbprint from this store.' }
    $Certificate = Get-Item -LiteralPath ('Cert:\LocalMachine\My\' + $Thumbprint) -ErrorAction Stop
    $Certificate | Select-Object Subject,Issuer,DnsNameList,EnhancedKeyUsageList,NotBefore,NotAfter,HasPrivateKey | Format-List
}
```

**Read it:** Subject/issuer identify certificate parties; SAN/DNS names identify the endpoint names a client should validate; dates bound validity; EKU restricts intended use. A thumbprint identifies a certificate, not whether you trust it. `HasPrivateKey=True` reports local key association; this command does not export the key. An empty `My` store is a valid inventory result. Do not create a self-signed certificate merely to fill it.

**Success:** known DNS/domain-member readiness, plus a certificate metadata observation or an explicitly empty store. **Stop:** wrong domain, failed secure channel or DNS mismatch means not ready for enterprise CA configuration. **Recovery:** record the finding; no repair, certificate import, export, deletion or trust change today.

## 5. Select recovery points — 65–90 minutes

**Purpose:** have a concrete way back before Day 14 changes a test VM.

For each candidate, record backup product/job, latest successful recovery point, where it is stored, restore method, and whether restoration has actually been tested. “Job succeeded” and “restore tested” are separate evidence. Use your backup console for the existing DC and Commvault systems; inspect status without starting an unplanned backup or restore.

A VM checkpoint is a convenience rollback point on the same storage, **not an independent backup**. Standard checkpoints can also be unsuitable for replicated systems. Future CA recovery must protect the CA private key/certificate, database/logs and configuration; reverting a CA after issuance can roll back issuance/revocation history. Do not apply a blanket snapshot/revert workflow to existing DCs, CAs, or Commvault/SQL servers. [Hyper-V checkpoints](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints), [CA recovery components](https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/migrate-certification-authority).

### Optional concrete checkpoint — dedicated pre-CA test VM only

If ROOT/ISSUER/WEB already exists as an owned, dedicated test VM and Step 3 confirmed it has **no installed CA, DC role or important application**, create one checkpoint before future changes. If those VMs don't exist yet, record the requirement as pending; don't checkpoint a different server as a substitute.

**HYPER-V HOST — actual owner node.**

```powershell
$VMName = (Read-Host 'Exact dedicated PRE-CA test VM name; not DC/CA/Commvault').Trim()
$Selected = @(Get-VM | Where-Object Name -CEQ $VMName)
if ($Selected.Count -ne 1) { throw 'Exactly one VM must match on this owner node.' }
$VM = $Selected[0]
$CheckpointName = 'day13-pre-ca-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
if (Get-VMSnapshot -VM $VM | Where-Object Name -CEQ $CheckpointName) { throw 'Checkpoint name already exists; inspect before retrying.' }
$RecoveryDir = Join-Path $env:LOCALAPPDATA 'CloudSecurityLab\Day13\recovery'
New-Item -ItemType Directory -Path $RecoveryDir -Force -ErrorAction Stop | Out-Null
$RecoveryFile = Join-Path $RecoveryDir ($VM.Id.ToString() + '-' + $CheckpointName + '.json')
$Recovery = [pscustomobject]@{
    VMName=$VM.Name; VMId=$VM.Id.ToString(); OwnerHost=$env:COMPUTERNAME
    OriginalCheckpointType=$VM.CheckpointType.ToString()
    CheckpointName=$CheckpointName; CheckpointId=$null
    State='INTENT RECORDED; CREATION NOT VERIFIED'
    Purpose='Dedicated test VM before CA/application changes; not an independent backup'
}
$Recovery | ConvertTo-Json | Set-Content -LiteralPath $RecoveryFile -Encoding UTF8 -ErrorAction Stop

Set-VM -VM $VM -CheckpointType ProductionOnly -ErrorAction Stop
Checkpoint-VM -VM $VM -SnapshotName $CheckpointName -ErrorAction Stop
$Created = @(Get-VMSnapshot -VM $VM | Where-Object Name -CEQ $CheckpointName)
if ($Created.Count -ne 1) { throw 'Checkpoint result uncertain. Inspect original VM/name; do not keep creating replacements.' }
$Recovery.CheckpointId = $Created[0].Id.ToString()
$Recovery.State = 'CHECKPOINT CREATED; RESTORE NOT TESTED'
$Recovery | ConvertTo-Json | Set-Content -LiteralPath $RecoveryFile -Encoding UTF8 -ErrorAction Stop
$Created | Select-Object Name,Id,CreationTime,SnapshotType | Format-List
```

`ProductionOnly` refuses a fallback to a standard checkpoint. It is intentionally retained on this **dedicated test VM**, and the original setting is recorded before the change. Creating the checkpoint does not prove a restore works. A failed or uncertain create means inspect that exact VM/checkpoint using `Get-VMSnapshot`; do not loop through new checkpoint names. Do not disable guest protection or VSS safeguards to force success.

Keep a useful pre-change checkpoint into Day 14, alongside the independent recovery plan. Before eventually applying one, reassess what changed in the guest **and externally**, including AD computer-account state. No restore command is supplied today because no restore is required by this inventory exercise.

**Success:** an actual recovery point and restore procedure are recorded for each selected existing test VM, with tested/untested distinctions; any temporary checkpoint setting change has a private before-record. **Stop:** low storage, unknown ownership, application dependency or failed checkpoint. **Recovery:** leave the original record intact; inspect the exact VM. Do not delete checkpoints or disks to solve storage pressure blindly.

## 6. Write the trust design — 90–105 minutes

**Purpose:** settle the stable names and trust/publication boundaries that are hard to change after issuance.

**MANAGEMENT PC** — return to the terminal from Step 1. Create a private decision file, then fill it using your inventory:

```powershell
@'
DAY 13 PRIVATE PKI DESIGN
Lab forest/domain (existing, owned, isolated):
Hyper-V owner nodes / switch / VLAN boundary:
ROOT VM and workgroup status:
ISSUER VM and intended lab-domain membership:
WEB test VM and CLIENT:
Existing CA discovered? If yes, describe; do not overwrite it:
Independent backup/recovery locations and latest job evidence:
Pre-change test VM checkpoints / exact private record files:
Restore tested: YES / NO (per VM):

Proposed root CA display name: Mark Lab Root CA
Proposed issuing CA display name: Mark Lab Issuing CA
These are CA display names, not hostnames. Validate final names before installation.
Proposed root: offline standalone, dedicated workgroup VM
Proposed issuer: enterprise subordinate, dedicated lab member server
Future test endpoint FQDN and exact DNS SAN:
Future stable public-file hostname (for example, pki.<actual-lab-domain>):
Future HTTP AIA base URL:
Future HTTP CDP base URL:
Exact CA certificate/CRL filenames: finalize before first issuance
Public-file publication owner and refresh procedure:
Lab-only root trust distribution: who/where/how; no employer/customer systems
Private-key storage / protected independent backup location:
Missing systems, permissions, storage, backup or isolation:
Day 14 readiness: READY / NOT READY, with reason:
'@ | Set-Content -LiteralPath (Join-Path $Evidence 'private-pki-design.txt') -Encoding UTF8
notepad (Join-Path $Evidence 'private-pki-design.txt')
```

Use this compact decision guide while filling it:

| Decision | Proposed lab choice / evidence needed |
|---|---|
| Hierarchy | Offline standalone root → online enterprise issuing CA → disposable server certificate. |
| Root isolation | Dedicated workgroup VM; disconnected operation after provisioning; controlled offline signing/file transfer. A CA host need not serve AIA/CDP files. |
| Key ownership | Root signs with its root key; issuer signs with its issuing key; WEB owns its leaf key. A CSR carries a public key and request information, not the private key. |
| Trust | Root public certificate becomes a trust anchor only where deliberately distributed. Merely possessing a certificate does not make it trusted. Enterprise publication/trust must remain in the owned lab forest. |
| Names | Finalize CA display names separately from hostnames. Leaf SAN must match the FQDN the test client actually uses. Don't rename an established CA casually. |
| Public files | AIA helps clients find issuer certificates; CDP locates signed certificate revocation lists (CRLs). Use stable lab HTTP paths reachable by validation clients. HTTP retrieval of signed public files does not publish private keys. |
| Availability | Offline root need not be online for routine validation if required public CA certificates/valid CRLs are published elsewhere. Define who refreshes these files before they expire. |
| Next-day choices | Record Windows Server version, key-provider/algorithm compatibility and proposed validity hierarchy for Day 14. No cryptographic settings or certificate validity periods are changed today. |

Plan AIA/CDP locations **before issuing certificates**; changing a CA's settings later does not rewrite URLs embedded in already-issued certificates. For this training topology, WEB can host static public files as well as the disposable HTTPS service; record this as a lab simplification, not a production separation-of-duties design. [Microsoft PKI design considerations](https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/pki-design-considerations).

**Success:** a complete private role/recovery/trust map with remaining unknowns explicit. **Stop:** unresolved namespace, missing directory, insufficient spare systems, unclear isolation or no recovery path means NOT READY for CA installation. **Recovery:** this phase only writes a plan. Do not create DNS records, distribute root trust, change IIS bindings or configure a CA to fill gaps hurriedly.

## 7. Close Day 13 and save public evidence — 105–120 minutes

**Purpose:** preserve the readiness decision without exposing your internal infrastructure.

**MANAGEMENT PC**

```powershell
Set-Location $Repo
Copy-Item -LiteralPath (Join-Path $Pack 'DAY-13-RUNBOOK.md') -Destination 'docs\day13-runbook.md'
Copy-Item -LiteralPath (Join-Path $Pack 'DAY-13-DIAGRAM.png') -Destination 'docs\day13-diagram.png'
notepad (Join-Path $Repo 'docs\day13-results.md')
# Fill and save the sanitized template below before running the next commands.
git diff -- infra/terraform
git add -- docs/day13-runbook.md docs/day13-diagram.png docs/day13-results.md
if ($LASTEXITCODE -ne 0) { throw 'Staging failed.' }
git diff --cached --name-only
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Resolve staged whitespace/errors before commit.' }
git --no-pager diff --cached -- docs/day13-results.md
# Review only these three intended files; no private inventory/keys/backup details.
git commit -m "docs: prepare isolated Hyper-V certificate lab"
if ($LASTEXITCODE -ne 0) { throw 'Commit failed.' }
git push -u origin feat/day13-pki-preparation
if ($LASTEXITCODE -ne 0) { throw 'Push failed; local commit remains.' }
git status --short --branch
```

**Success:** Terraform diff empty; sanitized result and diagram/runbook committed. Raw host/guest evidence remains under the private local folders or ignored `local-evidence/` when copied through your normal secure lab workflow. Do not introduce a new public share for collecting it.

**Stop:** unexpected staged files, private infrastructure values, a key/PFX/password, or an unsupported completion claim. **Recovery:** unstage only the exact unintended path using `git restore --staged -- <path>`; preserve private evidence. Do not use `git add .`.

**Today's cleanup:** no Azure resources or certificates were created. Leave useful, explicitly recorded test checkpoints for Day 14; close admin consoles when finished. No CA role, trust-store, AD or web binding changes are expected. If you changed anything outside these steps, record it and its recovery consequence separately.

## Completion and results template

**COMPLETE** = current lab inventory verified, actual isolated targets selected, recovery evidence recorded and trust design finished. **PARTIAL** = meaningful inventory/design finished but systems/recovery/isolation still missing. **BLOCKED** = cannot access the owned lab or necessary inventory. A complete design document alone does not mean a CA has been deployed or that Day 14 is ready.

```text
Day 13 — Hyper-V certificate-lab preparation
Date:
Status: COMPLETE / PARTIAL / BLOCKED
Hypervisor: Hyper-V (single host / cluster)
Existing owned lab AD/DNS inventory: VERIFIED / MISSING / UNVERIFIED
Selected ROOT, ISSUER, WEB and CLIENT roles: VERIFIED / PLANNED / INCOMPLETE
Actual switch/VLAN/network boundary verified: YES / NO
Guest OS/roles/domain/DNS/time checked: YES / PARTIAL / NO
Existing CA found: YES / NO / UNKNOWN (no configuration changed)
Certificate metadata inspected: YES / EMPTY STORE / NOT RUN
Recovery points documented: YES / PARTIAL / NO
Independent backup evidence: VERIFIED / UNVERIFIED
Restore tested: YES / NO (do not infer from successful backup/checkpoint creation)
Optional pre-change checkpoints: CREATED / NOT NEEDED / PENDING
ProductionOnly setting changes recorded: YES / NONE
Two-tier trust and public-file publication design recorded: YES / NO
CA installed / certificate issued / root trust imported today: NO
Azure / Terraform changed today: NO
Day14 readiness: READY / NOT READY
Remaining dependency and next action:
Day11–12 historical final-cleanup evidence gap remains recorded: YES
Private data kept out of Git: YES / NO
Commit/push: see Git history / PENDING
```

## Tutor prompt

> Walk me through DAY-13-RUNBOOK.md one step at a time, explaining each direct PowerShell command before I run it. My hypervisor is Hyper-V. Distinguish the management PC, Hyper-V owner node, guest and lab DC consoles; variables do not cross consoles. Today's objective is inventory, isolation, recovery readiness and PKI trust design. Use actual lab observations; do not invent existing VMs or a domain. Do not install AD CS, distribute a root certificate, change DNS/IIS, restore a checkpoint, or modify an existing DC/CA/Commvault server today. Explain root versus issuer, public certificate versus private key, SAN, AIA, CDP and CRL only when relevant. Help me fill the private worksheet and sanitized result. If capacity/recovery is missing, record PARTIAL rather than extending into unplanned deployment.

## Preparation checks and diagram

The preparing assistant reviewed current Microsoft documentation and the saved lab results. All 10 PowerShell blocks passed syntax checks; no command has been executed against your Hyper-V hosts, guests or Azure. The diagram is a proposed design, not evidence of deployed CAs. Readiness is determined by your observations today.

**Diagram prompt / reproducible brief:** built-in image generation, landscape white-background Hyper-V PKI architecture. Show an owned isolated home-lab boundary; AD DS/DNS if present, to inventory; proposed offline standalone workgroup root, online domain-joined enterprise issuing CA, disposable HTTPS/public-file server and validation client. Root-to-issuer is offline signing/file transfer, not a network link. Client later validates HTTPS names/chain/revocation and retrieves public AIA/CRL files by HTTP. Private keys stay with their owners. Mark design only, no CA installed today, no existing domain/spare VM assumed, no Whizlabs needed and Terraform unchanged. Footer: inventory → select isolated targets → verify recovery → record trust design; Day 14 establishes the CA.
