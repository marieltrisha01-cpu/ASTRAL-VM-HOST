# Production Blueprint: Advanced Hardware-Independent RDP Architecture

This document serves as the official technical specification for the **Zero-Cost Distributed Windows Server 2025** environment.

## 1. System Architecture Diagram

```text
[ User Client (PC/iPad) ]
          │
          ▼
[ Tailscale Secure Tunnel ] <──── Peer-to-Peer Bridge
          │
          ▼
[ GitHub-Hosted Runner ] <──── Stateless Execution Node (WinServer 2025)
          │
          ├─── [ Persistence Engine ]
          │          ├── Layer 1: GHA Artifacts (Session Snapshots)
          │          └── Layer 2: Rclone Sync (Cloud Mirror)
          │
          └─── [ Automation Stack ]
                     ├── Ansible (IaC Provisioning)
                     ├── WinGet (Package Orchestration)
                     └── OpenSSH (Management Path)
```

## 2. Tool Stack Recommendation

| Category | Selection | Rationale |
| :--- | :--- | :--- |
| **VM Layer** | GitHub Actions (`windows-2025`) | 2 vCPU, 7GB RAM, High-performance ephemeral compute. |
| **Storage Layer** | GHA Artifacts + Rclone | Layered persistence with cloud-redundancy. |
| **Automation Layer** | Ansible + WinGet | Idempotent system state and automated setup. |
| **Networking Layer** | Tailscale (WireGuard) | Zero Trust P2P networking; bypasses CGNAT. |
| **Security Layer** | NLA + OpenSSH + Firewall | Hardened RDP; secure management over SSH. |
| **Backup Layer** | Zip Artifacts + Cloud Mirror | Multi-provider snapshot replication. |
| **Monitoring Layer** | GHA Logs + Tailscale Stats | Native execution logging and node health. |

## 3. Persistence Mechanisms

### Stateless-to-Stateful Recovery:
- **How state survives:** State is strictly isolated into `C:\State`. The `provision.ps1` script creates **Directory Junctions** that link standard user folders (Desktop, Documents, Downloads, Chrome User Data) directly into `C:\State`. Before process termination, the entire `C:\State` tree is compressed and uploaded.
- **How rebuild works:** Upon workflow trigger, the runner executes a "Restore" phase that downloads the latest `state.zip`, extracts it, and then the `provision.ps1` script re-establishes the junctions. This makes the persistence transparent to applications like Chrome.
- **Where data is stored:** Primary storage is GitHub's global artifact storage (7-day retention default). Secondary storage is a user-configured cloud drive (G-Drive/S3) accessed via Rclone.
- **Version control:** The infrastructure logic is versioned in Git; data state is versioned by Artifact timestamps.
- **Chrome Persistence:** By junctioning `AppData\Local\Google\Chrome\User Data`, your open tabs, history, and session tokens are preserved. *Note: Passwords may occasionally require re-entry due to DPAPI machine-key variations.*

## 4. Step-by-Step Deployment Blueprint

### Zero State to Operational:
1. **Initialize Control Repository:** Push `advanced-rdp-server` components to a private GitHub repo.
2. **Configure Overlay Network:** 
    - Install Tailscale on the local client.
    - Add `TAILSCALE_AUTHKEY` (reusable) to GitHub Secrets.
3. **Establish Identity:** Add `VM_PASSWORD` to GitHub Secrets.
4. **Boot Sequence:**
    - Trigger workflow via `workflow_dispatch`.
    - Script manually triggers "Restore" -> "Tailscale Up" -> "Provision".
5. **Hardening:**
    - `provision.ps1` disables Server Manager, enables NLA, and locks down the firewall to Tailscale ranges.
6. **Handover:** Connect via RDP or SSH using the private Tailscale IP provided in the workflow logs.

## 5. Backup & Disaster Recovery Plan

- **Backup Frequency:** Every session teardown (Automatic) + 30-minute incremental (Configurable).
- **Off-site Replication:** Continuous sync from `C:\State` to Remote Cloud via Rclone.
- **RTO (Recovery Time Objective):** < 10 minutes (Time to provision new GHA runner).
- **RPO (Recovery Point Objective):** 30 minutes (Last incremental sync).
- **Worst-case failure:** If GitHub Actions is down, use the Packer template (`windows.pkr.hcl`) to redeploy the environment to Azure/AWS using the same Ansible/WinGet logic.

## 6. Risk Analysis & Mitigation

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **GHA Timeout** | Loss of work since last sync. | Incremental sync script (every 30m). |
| **Account Ban** | Loss of Control Repo. | Mirror repository to GitLab; keep local IaC copies. |
| **Network Throttling** | Degraded RDP performance. | Use SSH management for heavy command-line tasks. |
| **Artifact Expiration** | Loss of snapshots. | Use Rclone sync to personal cloud storage (G-Drive). |

## 7. Scaling Path

- **Horizontal:** Deploy multiple "Worker Repositories" for different project environments, all connected to the same Tailnet.
- **Vertical:** Transition to GitHub "Larger Runners" (up to 64 vCPUs) for high-load workloads.
- **Cloud Migration:** Seamlessly move to Azure/AWS by running the Packer template against a CSP environment.
