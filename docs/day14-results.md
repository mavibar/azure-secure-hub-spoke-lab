# Day 14 — Establish lab certificate authority

Date: 2026-09-29–30

Status: COMPLETE WITH EVIDENCE GAP

Last successful phase / next exact step:
Day 14 PKI hierarchy built, published, independently validated and closed out. Continue with Day 15 certificate-template work.

Dedicated ROOT / ISSUER / WEB installed: YES

Existing DC CA identity unchanged: UNVERIFIED
Exact pre-Day-14 CA certificate hash was not preserved, so a cryptographic before/after comparison cannot be claimed.

Clock accuracy: VERIFIED within 60 seconds

Time synchronization health: MANUAL CHECK ONLY; source issue remains

ROOT: standalone, workgroup, NIC disconnected, correct CA certificate: PASS

ISSUER: enterprise subordinate of NEW root, correct constraints/validity: PASS

CSR approval: exact pending request reviewed

Four HTTP public files and source hashes: PASS

CLIENT issuer chain + root-CRL validation: PASS

Issuer CRL inspected/current: YES

New issuer published templates: ZERO VERIFIED

CA administration/issuance permissions reviewed: YES

Leaf certificate enrollment / HTTPS / leaf revocation:
NOT RUN — later days

CA configuration/private evidence retained: YES

Recovery:
Native CA backup taken for ROOT and ISSUER.
Restore tested: NO

ROOT disconnected and powered off: VERIFIED

CRL refresh deadlines recorded privately: YES

Azure / Terraform changed: NO

Unexpected changes / outstanding issues:
The intended pre-Day-14 legacy DC CA hash evidence was not captured.
The legacy CA name/type were known from prior inventory, but an exact before/after certificate hash comparison cannot be claimed.

Commit/push: PENDING
