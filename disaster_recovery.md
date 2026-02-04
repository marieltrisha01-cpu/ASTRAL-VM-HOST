# Disaster Recovery Plan: Distributed Windows Server 2025

This plan details the protocols for recovering the RDP environment in the event of infrastructure failure, account suspension, or data corruption.

## 1. Objectives & Metrics
- **RTO (Recovery Time Objective):** < 30 Minutes.
- **RPO (Recovery Point Objective):** 30 Minutes (Last successful Rclone sync).
- **Critical Data:** All content within `C:\State`.

## 2. Failure Scenarios & Responses

### Scenario A: GitHub Runner Execution Failure
**Symptom:** Workflow fails during "Restore" or "Provision" steps.
- **Response:** 
    1. Inspect GHA logs for specific error (e.g., WinGet timeout).
    2. Re-run job with `cleanup` parameter or fresh state.
    3. If persistence artifact is corrupted, trigger "Emergency Cloud Restore".

### Scenario B: GitHub Account / Repository Suspension
**Symptom:** Repository is inaccessible or GHA is disabled.
- **Response:**
    1. Push local IaC backup (the `advanced-rdp-server` folder) to GitLab or a secondary GitHub account.
    2. Update `main.yml` with the new environment's secrets.
    3. Use Rclone to pull the last known-good state from G-Drive/S3 to the local machine or a new runner.

### Scenario C: Tailscale Connectivity Loss
**Symptom:** RDP/SSH connections time out; node is "Offline" in Tailscale dashboard.
- **Response:**
    1. Check GHA logs to see if the "Keep VM Alive" step is still running.
    2. If Tailscale crashed, the `HealthAgent` (in `provision.ps1`) will attempt to restart the service automatically.
    3. Final resort: Kill the current workflow and start a new one to force a network reset.

## 3. Emergency Restore Procedure (Manual)

To restore the environment to a local machine or a different cloud provider:
1. **Clone Repo:** `git clone <backup-repo-url>`
2. **Setup Networking:** Ensure Tailscale is installed and joined to the tailnet.
3. **Pull State:**
   ```powershell
   rclone sync "remote:rdpdev-state" "C:\State"
   ```
4. **Apply Config:**
   ```powershell
   ./provision.ps1
   ansible-playbook site.yml
   ```

## 4. Continuity Maintenance
- **Weekly Audit:** Verify that `rclone sync` logs show successful mirrors.
- **Bi-Weekly Rebuild:** Trigger a manual workflow to ensure the "Golden Snapshot" is still functional with newest Windows 2025 patches.
