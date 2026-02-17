# Security Policy

## Supported Versions

We provide security updates for the [latest release](https://github.com/kypello-io/kypello/releases/latest).
Because Kypello follows a continuous delivery model, we do not backport fixes to older versions. If you are vulnerable, you must upgrade to the latest binary.

## Reporting a Vulnerability

Since Kypello is a fork of MinIO, security vulnerabilities generally fall into two categories. Please determine which category your issue falls into:

### 1. Core Server Vulnerabilities
If the vulnerability exists in the core object storage layer, S3 API, or erasure coding (and therefore affects standard MinIO as well):

*   **Primary:** Please report these strictly to the upstream MinIO security team at `security@min.io`. This ensures the issue is fixed at the source for the entire community.
*   **Secondary:** Once the upstream fix is public, we will merge it into Kypello immediately. If you believe the issue is critical and unpatched, you may privately notify us via [GitHub Private Reporting](https://github.com/kypello-io/kypello/security/advisories/new).

### 2. Kypello-Specific Vulnerabilities
If the vulnerability is specific to **Kypello features** (e.g., the restored Console UI, OIDC integration, or our specific Docker builds):

*   **DO NOT** report these to MinIO Inc; they do not support this code.
*   **Report to us directly** using the "Report a Vulnerability" button in the [Security tab](https://github.com/kypello-io/kypello/security) of this repository.

### Disclosure Process

1.  **Triage:** We will determine if the issue is specific to Kypello or upstream.
2.  **Fix:**
   *   For **Kypello bugs**, we will develop a patch and release a new binary.
   *   For **Upstream bugs**, we will monitor the upstream repository for a security fix and cherry-pick it immediately upon release.
3.  **Advisory:** We will publish a security advisory in the GitHub "Security" tab.

We ask that you allow us reasonable time to patch the issue before disclosing it publicly.