# Day 17 — Certificate troubleshooting results

Date: 2026-10-02

Status: COMPLETE
Days 15 and 16: completed on time, reported October 2, 2026.
Existing endpoint baseline before test: PASS
Correct-name certificate SSL policy: PASS
Wrong-name SSL policy: rejected with CERT_E_CN_NO_MATCH / 0x800B010F
Cause: requested identity was absent from the certificate SAN.
Correction: use the existing certified DNS identity.
Corrected-name SSL policy: PASS
Live TLS exact-leaf / HTTPS marker / public HTTP CRL checks after test: PASS
ROOT off and disconnected at closeout: PASS
Infrastructure configuration changes for the experiment: NONE
Scope: certificate-file hostname-policy experiment plus live endpoint validation.
Revoked-leaf behavior and CA recovery: NOT TESTED
Clock synchronization health: unresolved; manual accuracy remains a separate check.
Day 14 legacy-CA pre-change hash evidence gap: retained.
Private evidence retained outside Git; no private keys or raw logs included here.
Commit/push: see Git history for final status.
