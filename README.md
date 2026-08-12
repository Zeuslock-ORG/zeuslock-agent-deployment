# ZeusLock Agent — Enterprise Deployment Guide

Everything an administrator needs to roll out the **ZeusLock DLP desktop agent** to
a fleet of Windows, macOS, or Linux endpoints — and to **verify it is actually
protecting them**. Each guide is written to be followed **step by step**, top to
bottom, on a real environment.

> **The agent's job:** it runs on each endpoint, routes browser/app traffic to AI
> services (ChatGPT, Claude, Gemini, Copilot, …) through a local inspection proxy,
> and enforces your organization's DLP policy — blocking or alerting on secrets,
> PII, source code, and other sensitive data before it leaves the device.

---

## The deployment model (read this first — it is the same on every OS)

Every platform follows the **same four steps**. Only the *tooling* changes.

| Step | What you do | Why |
|------|-------------|-----|
| **1. Get your values** | From the ZeusLock dashboard, copy your **Server URL** and create an **API key (license key)**. | These bind each endpoint to your organization + policy. |
| **2. Deploy the installer** | Push the installer (downloaded from the dashboard) to every endpoint via your management tool (GPO / MDM / Ansible). | Puts the agent binary on the machine. |
| **3. Push the configuration** | Deliver the Server URL + license key to each endpoint via a **managed policy** (registry / MDM profile / conf file) — *or* a config file. | **The installer is generic — it carries NO credentials.** The machine is bound to your org *after* install, by config. |
| **4. Verify** | Confirm the agent is installed, configured, **active**, and intercepting AI traffic. | A deployed-but-unconfigured agent is silently inactive. Always verify. |

> ⚠️ **The single most important fact:** the installer you download from the
> dashboard is **generic** — the same file for every customer, with **no baked-in
> credentials**. An endpoint only becomes protected once **Step 3** delivers the
> Server URL + license key. Skipping Step 3 leaves the agent installed but inert.

---

## Pick your platform

| Platform | Guide | Primary method | Also covers |
|----------|-------|----------------|-------------|
| 🪟 **Windows** | **[docs/01-windows-gpo.md](docs/01-windows-gpo.md)** | Active Directory **GPO** (Software Installation + Registry policy) | SCCM/Intune notes, standalone install |
| 🍎 **macOS** | **[docs/02-macos-mdm.md](docs/02-macos-mdm.md)** | **MDM** (Jamf, Mosyle, Kandji, Intune) managed profile | Manual install for a single Mac |
| 🐧 **Linux** | **[docs/03-linux.md](docs/03-linux.md)** | **Ansible** (`.deb` / `.rpm`) | Manual install, systemd notes |

Supporting references:

- **[docs/configuration-reference.md](docs/configuration-reference.md)** — every
  configuration key, where the agent reads it, and the precedence order. The
  authoritative source of truth for **Step 3** on all platforms.
- **[docs/verify-and-troubleshoot.md](docs/verify-and-troubleshoot.md)** — how to
  confirm protection is live, and a symptom→cause→fix table for every OS.

Ready-to-edit templates and one-shot scripts live under **[scripts/](scripts/)** —
each guide tells you which one to use.

---

## Before you start — get your two values (Step 1)

1. Sign in to your ZeusLock dashboard.
2. **Server URL** — your API endpoint, e.g. `https://api.zeuslock.ai` (or your
   staging/self-hosted URL). This is the value you were given for your tenant.
3. **License key** — go to **Settings → API Keys → Create key**. Copy the
   `zl_…` value. This is what binds an endpoint to your organization.

> 🔐 **Treat the license key like a password.** Deliver it to endpoints through
> your management system (GPO/MDM/Ansible-vault) — never commit it to a
> repository, email, or shared document. The templates in this repo use the
> placeholders `YOUR_SERVER_URL` and `YOUR_LICENSE_KEY`; you fill them in inside
> your own management tooling.

Where the agent looks for these values (summary — full detail in the
[configuration reference](docs/configuration-reference.md)):

| OS | Managed policy (recommended — GPO/MDM) | File fallback |
|----|----------------------------------------|---------------|
| Windows | Registry `HKLM\SOFTWARE\Policies\ZeusLock` | `C:\ProgramData\ZeusDLP\config.json` |
| macOS | Managed profile domain `com.zeuslock.agent` | `/Library/Application Support/ZeusDLP/config.json` |
| Linux | `/etc/zeuslock/agent.conf` | `/etc/zeus-dlp/config.json` |

---

## What "done" looks like (every platform)

You have succeeded when, on a target endpoint:

- ✅ The agent package is **installed** (correct version).
- ✅ The **Server URL + license key** are present in the managed policy or config file.
- ✅ The agent process is **running** and shows **"Protection active"** for the logged-in user.
- ✅ Pasting a test secret (e.g. a credit-card number) into a monitored AI site is
  **flagged/blocked**, and a matching **incident** appears in your dashboard.

The [verification guide](docs/verify-and-troubleshoot.md) walks each of these
checks per OS.

---

## Support

If an endpoint doesn't come up protected, work through
[docs/verify-and-troubleshoot.md](docs/verify-and-troubleshoot.md) first — it
covers the common causes (config not delivered, agent not started in the user's
session, proxy not trusted). If you're still stuck, contact ZeusLock support with
the diagnostic output that guide tells you to collect.
