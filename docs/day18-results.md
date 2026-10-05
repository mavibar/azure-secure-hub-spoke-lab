\# Day 18 — Commvault TLS Preparation



\*\*Date:\*\* 2026-10-05  

\*\*Overall:\*\* COMPLETE



\## Replacement Client



\- Built replacement validation client `LABCLIENT18`.

\- Windows Server 2022 evaluation installation validated.

\- Joined successfully to `Targaryen.local`.

\- Final computer name: `LABCLIENT18`.

\- Primary lab IP: `192.168.138.6/24`.

\- Added second NIC on `Home Lab Internal Switch` for Commvault validation.

\- Commvault-side client IP: `172.16.0.18/24`.

\- Existing/old validation client preserved.

\- Domain secure channel validated.



\## PKI Validation



\- Existing lab PKI remained operational.

\- Replacement client retained trust in the lab PKI.

\- PKI WEB certificate and HTTP CRL publication were preserved.

\- Offline Root CA remained offline/disconnected.

\- No existing PKI certificate or key material was replaced during Day 18.



\## Commvault Endpoint Discovery



Browser endpoint:



`https://commserve01.vibarinternal.com/commandcenter`



Commvault server:



`Commserve01`



Commvault IP:



`172.16.0.3`



TLS terminator:



`GxTomcatInstance001`



Observed listeners:



\- TCP 80

\- TCP 443



Active Tomcat configuration:



`C:\\Program Files\\Commvault\\ContentStore\\Apache\\conf\\Server.xml`



Active keystore:



`C:\\Program Files\\Commvault\\ContentStore\\Apache\\conf\\CV\_TempKeystoreFile.jks`



Keystore type:



`JKS`



Existing alias:



`selfsigned`



Existing key entry:



`PrivateKeyEntry`



Existing keystore password access:



\*\*VERIFIED\*\*



The password was not published or committed to the repository.



\## Client-to-Commvault Validation



`LABCLIENT18` successfully resolved:



`commserve01.vibarinternal.com -> 172.16.0.3`



TCP connectivity from the replacement client to:



`commserve01.vibarinternal.com:443`



was successful.



The existing Command Center page loaded successfully from the replacement client.



The existing certificate is still the pre-existing Commvault self-signed certificate. Replacement certificate trust was \*\*not tested because no replacement certificate was issued or bound during Day 18\*\*.



\## Recovery Preparation



The following active files were backed up before any future certificate change:



\- `Server.xml`

\- `CV\_TempKeystoreFile.jks`



Copies were SHA-256 verified against their sources.



A protected off-VM recovery copy was created on the Hyper-V host.



Existing keystore access was successfully validated with `keytool`.



Current alias `selfsigned` was confirmed as a `PrivateKeyEntry`.



Rollback plan:



1\. Stop only `GxTomcatInstance001`.

2\. Preserve the failed/new configuration for troubleshooting.

3\. Restore the original `Server.xml`.

4\. Restore the original `CV\_TempKeystoreFile.jks`.

5\. Restore original ACLs if required.

6\. Start `GxTomcatInstance001`.

7\. Validate TCP 443, previous certificate behavior, Command Center login, and application health.



A VM snapshot, SQL rollback, CommServe rollback, or CA rollback is \*\*not\*\* the planned TLS rollback method.



\## Day 19 Selected Procedure



Selected endpoint:



`commserve01.vibarinternal.com`



Selected procedure:



\*\*Commvault Tomcat / 2024E Certificate Tool workflow\*\*



Planned certificate characteristics:



\- DNS SAN: `commserve01.vibarinternal.com`

\- New Commvault-owned private key

\- RSA 3072

\- SHA-256-compatible issuance

\- Server Authentication

\- Full lab CA certificate chain

\- Signed by the lab issuing CA



The private key will be created for the Commvault endpoint and will not reuse PKIWEB01 key material.



\## Day 18 Change Status



Commvault new certificate issuance: \*\*NOT PERFORMED\*\*



Commvault new certificate binding: \*\*NOT PERFORMED\*\*



Commvault Tomcat TLS configuration change: \*\*NOT PERFORMED\*\*



Azure deployment: \*\*NONE\*\*



Sentinel activation: \*\*NONE\*\*



\## Day 19 Readiness



\*\*READY\*\*, subject to final confirmation of the existing CommServe DR-backup status and completion of the recovery-readiness worksheet.



Day 19 begins with generation of the new Commvault-owned key/CSR, lab-CA issuance, keystore validation, controlled Tomcat configuration change, and independent validation from `LABCLIENT18`.