# Kypello Object Storage


### The Open Source, S3-Compatible Object Store.
**High Performance. Enterprise Identity. Fully AGPLv3.**

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://github.com/kypello-io/kypello/blob/master/LICENSE)
[![Go Version](https://img.shields.io/github/go-mod/go-version/kypello-io/kypello)](https://github.com/kypello-io/kypello)


---

**Kypello** is a high-performance, S3-compatible object storage server. It is a community-maintained fork of MinIO designed to preserve critical enterprise functionality—specifically **OpenID Connect (OIDC)**, **SSO**, and the **comprehensive Admin UI**—within the open-source ecosystem.

Designed for speed and scalability, Kypello powers AI/ML, analytics, and data-intensive workloads while keeping identity management free and open.

### 🚀 Key Features

*   **S3 API Compatible:** Seamless integration with existing S3 tools and SDKs.
*   **Restored OIDC/SSO:** Built-in support for Keycloak, Okta, Active Directory, and Google Workspace (features removed from upstream MinIO).
*   **Full Admin UI:** A fully functional web console for managing buckets, users, and groups.
*   **High Performance:** Optimized for large-scale data pipelines and bare metal.

### ⚠️ Legal & Fork Disclaimer

**Kypello is a fork.**
This project is based on the open-source code from MinIO Inc. but is **not affiliated with, endorsed by, or sponsored by MinIO Inc.**

*   All original code is retained under the GNU AGPLv3 license.
*   "MinIO" is a registered trademark of MinIO, Inc.
*   Kypello respects upstream intellectual property; all branding in this fork has been updated to reflect the new project name.

---

## Quickstart

### Option 1: Install from Source (Recommended)

Kypello is written in Go. Ensure you have [Go 1.25+](https://golang.org/dl/) installed.

```bash
# Install the server binary (automatically embeds the Kypello UI)
go install github.com/kypello-io/kypello@latest
```

Start the server:
```bash
# Run Kypello on a local folder
~/go/bin/kypello server ./data
```

### Option 2: Build with Docker

You can build a Kypello container image directly from this repository.

```bash
# Build the image
docker build -t kypello/server .

# Run the container
docker run -p 9000:9000 -p 9001:9001 \
  -e "KYPELLO_ROOT_USER=admin" \
  -e "KYPELLO_ROOT_PASSWORD=password" \
  kypello/server server /data --console-address ":9001"
```

## Accessing the Console

Once Kypello is running, open your browser to `http://localhost:9001`.
You will see the **Kypello Console**, where you can log in with your root credentials or configure OIDC for external identity providers.

## Connecting with Clients

Kypello is fully compatible with the AWS S3 SDKs and the MinIO Client (`mc`).

```bash
# Example using mc (MinIO Client)
mc alias set mykypello http://localhost:9000 admin password
mc admin info mykypello
```

## Documentation

*   **Core Logic:** Since Kypello is API-compatible with MinIO, you can refer to the [upstream documentation](https://min.io/docs) for standard S3 operations and erasure coding concepts.
*   **Identity & UI:** For OIDC configuration, refer to the [Kypello Wiki](https://github.com/kypello-io/kypello/wiki) (Coming Soon).

## License & Compliance

Kypello is strictly **Open Source Software** licensed under the **GNU AGPLv3**.

*   [License Text](https://github.com/kypello-io/kypello/blob/master/LICENSE)
*   [Compliance Guide](https://github.com/kypello-io/kypello/blob/master/COMPLIANCE.md)

**Note:** Unlike the upstream project, Kypello does not offer a commercial license exception. All usage must comply with the AGPLv3.

## Security

*   **Core Vulnerabilities:** Security issues affecting the underlying S3/Storage layer should be reported to the upstream MinIO team (`security@min.io`) so they can be fixed at the source.
*   **Kypello Vulnerabilities:** Issues specific to the Kypello UI, OIDC integration, or build process should be reported via our [GitHub Security Tab](https://github.com/kypello-io/kypello/security).

See [SECURITY.md](SECURITY.md) for details.
