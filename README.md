# ASTRAL-VM-HOST: Advanced Hardware-Independent RDP Architecture

This repository hosts a production-grade, zero-cost distributed Windows Server 2025 environment. Engineered for high performance and supreme reliability, it uses ephemeral GitHub-hosted runners with a stateless-to-stateful persistence model.

## 🚀 Key Features
- **OS:** Windows Server 2025 (Native WinGet & OpenSSH support).
- **Network:** Secure P2P overlay via Tailscale (WireGuard).
- **Persistence:** Multi-layered snapshotting (GitHub Artifacts + Rclone Cloud Mirror).
- **IaC:** Fully automated via Ansible and Packer HCL templates.
- **Security:** Hardened RDP with NLA and firewall restrictions.

## 📖 Documentation
- [**Technical Blueprint**](blueprint.md): Deep dive into the architecture and persistence layers.
- [**Disaster Recovery Plan**](disaster_recovery.md): Protocols for recovery, RTO/RPO targets, and emergency restore steps.

## 🛠️ Quick Start
1. **Repository Setup:** Fork or clone this repo.
2. **Secrets:** Add `TAILSCALE_AUTHKEY` and `VM_PASSWORD` to your GitHub repository secrets.
3. **Trigger:** Go to **Actions** -> **Advanced RDP Server (WinServer 2025)** -> **Run workflow**.
4. **Access:** Connect via RDP or SSH using the Tailscale IP displayed in the logs.

---
*Part of the /rdpdev architectural framework.*
