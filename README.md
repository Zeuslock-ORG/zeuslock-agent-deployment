# ZeusLock agent: deployment guide

Everything an administrator needs to roll out the **ZeusLock - AI Data Protection** endpoint
agent to Windows, macOS and Linux computers, and to check that each one is protected.
The guides are for agent **1.0.45 or later**. Follow them top to bottom; each step says what
you should see.

The agent runs on each computer, sends AI traffic (ChatGPT, Claude, Gemini, Copilot, coding
assistants…) through a local inspection proxy, and applies your organisation's policy:
sensitive data is anonymised or blocked before it leaves the computer.

---

## The four steps (the same on every OS)

| Step | What you do | Result |
|---|---|---|
| **1. Get your two values** | In the dashboard, note the **Server URL** and create an **API key** (the license key). | You have `https://api.zeuslock.ai` and a `zl_…` key. |
| **2. Deploy the installer** | Push the installer from the dashboard with GPO / Intune / MDM / Ansible. | The app is on every computer. |
| **3. Push the configuration** | Deliver the Server URL + license key as policy (registry / MDM profile / conf file). | Each computer is bound to your organisation. |
| **4. Verify** | Check one computer: installed, configured, **Protection active**, a test is caught. | The computer appears under **Agents** in the dashboard. |

> **The installer carries no credentials.** It is the same file for every customer. A
> computer is protected only once Step 3 has delivered the Server URL and license key.
> Without them the agent shows **Agent not configured**.

---

## Pick your platform

| Platform | Guide | Fleet method | Also in the guide |
|---|---|---|---|
| **Windows 10 / 11** (x64) | [docs/01-windows-gpo.md](docs/01-windows-gpo.md) | Active Directory **GPO** (startup script or Software Installation) | Intune / SCCM, one PC, upgrade, removal |
| **macOS** (Apple silicon) | [docs/02-macos-mdm.md](docs/02-macos-mdm.md) | **MDM** (Jamf Pro, Mosyle, Kandji, Intune): `.pkg` + profile + LaunchAgent | One Mac, upgrade, removal |
| **Linux** (Ubuntu Desktop, amd64 / arm64) | [docs/03-linux.md](docs/03-linux.md) | **Ansible** (`.deb`) | One desktop, upgrade, removal |

Supporting pages:

- [docs/configuration-reference.md](docs/configuration-reference.md): every setting, where the
  agent reads it, and which one wins.
- [docs/04-existing-corporate-proxy.md](docs/04-existing-corporate-proxy.md): running the agent
  alongside the forward proxy you already have.
- [docs/verify-and-troubleshoot.md](docs/verify-and-troubleshoot.md): the four checks, logs per
  OS, the network after the agent stops, and a symptom → fix table.

Ready-to-edit templates and scripts are in [scripts/](scripts/). Each guide says which one to use.

**One computer, no GPO or MDM?** Use the dashboard: **Agents** → **Installing on a single
machine?** → **Local agent install**. It gives the download and the commands with your values
already filled in.

---

## Step 1: get your two values

1. Sign in to the ZeusLock dashboard (`https://app.zeuslock.ai`).
2. **Server URL**: `https://api.zeuslock.ai`. On a ZeusLock server installed in your own
   network, use `https://<your API host>`.
3. **License key**: open **API Keys** in the left menu → **+ Create a key** → give it a name →
   copy the `zl_…` value. One key can serve the whole fleet.

Expected result: you have the Server URL and a key that starts with `zl_`.

> **Treat the license key like a password.** Deliver it through your management system
> (GPO, MDM, Ansible Vault). Never commit it to a repository, email or shared document. The
> templates in this repository use the placeholders `YOUR_SERVER_URL` and
> `YOUR_LICENSE_KEY`, and the scripts restrict the file or registry key that holds it on
> each computer. See
> [Protecting the license key](docs/configuration-reference.md#protecting-the-license-key-on-the-endpoint).
> If a key leaks: create a new one, deploy it, then **Revoke** the old one on the
> **API Keys** page.

## Step 2: get the installer

In the dashboard: **Agents** → **Download Agent**, or the download buttons on the **Local
agent install** page.

| OS | Fleet file | One-computer file |
|---|---|---|
| Windows | `ZeusLock-<version>.msi` (per machine, silent, no properties) | `ZeusLock-Setup-<version>.exe` |
| macOS | `ZeusLock-<version>-arm64.pkg` (signed and notarised) | `ZeusLock-<version>-arm64.dmg` |
| Linux | `zeuslock-desktop-agent_<version>_amd64.deb` or `_arm64.deb` | the same `.deb` |

---

## Where the agent reads its configuration

| OS | Managed (fleets: GPO / MDM / Ansible) | One computer (dashboard **Local agent install**) |
|---|---|---|
| Windows | Registry `HKLM\SOFTWARE\Policies\ZeusLock` | `C:\ProgramData\ZeusLockDLP\config.json` |
| macOS | Profile for domain `com.zeuslock.agent` | `/Library/Application Support/ZeusLockDLP/config.json` |
| Linux | `/etc/zeuslock/agent.conf` | `/etc/zeuslock-dlp/config.json` |

The managed location is read first. A license key there makes the computer **managed**: the
tray has no **Quit**, and the agent is restarted if it is stopped. Full detail:
[configuration reference](docs/configuration-reference.md).

---

## What "done" looks like

On a computer, with a user signed in:

- The agent is **installed** (1.0.45 or later).
- The **Server URL and license key** are in the managed location or the config file.
- The tray (Windows) or menu bar (macOS, Linux top bar) icon shows **Protection active** and
  your organisation's name.
- Sending a test card number (`My card is 4111 1111 1111 1111`) on **chatgpt.com** is
  flagged or blocked by the agent, and an **incident** appears under **Incidents** in the
  dashboard.

The [verification guide](docs/verify-and-troubleshoot.md) walks through these checks per OS.

---

## Updates

The agent does **not** update itself. To update, deploy the newer installer from the dashboard
the same way you deployed the first one:

- **Windows:** replace the MSI on the share. `Install-ZeusLockAgent.ps1` upgrades every older
  version at the next start-up. An MSI upgrade over a running agent restarts it in a few
  seconds.
- **macOS:** push the new `.pkg` with your MDM.
- **Linux:** re-run the playbook with the new `.deb`.

The **Agents** page shows an **update** badge next to every computer that runs an older version.

---

## ZeusLock On-Device

In an organisation that ZeusLock has switched to **On-Device**, each prompt is checked on the
computer itself by ZeusLock Ama; the text never reaches the ZeusLock server. Deployment is the
same as above, with two differences:

1. **Installer:** download it from the dashboard **On-Device** page (**.msi (GPO, Intune)**,
   **Setup .exe**, **.pkg (MDM)**, **.dmg**, **.deb x64**, **.deb ARM64**). It is about 700 MB
   (the agent and ZeusLock Ama, encrypted). Installed over the normal agent, it replaces it.
2. **Computer requirements:** x64 with AVX2 or Apple silicon / arm64, **8 GB RAM**, **2 GB free
   disk**, then a short speed test by the agent. ZeusLock Ama uses about 1.2 GB of memory while
   it runs. A computer below that blocks AI tools, unless the **On-Device** page is set to
   **Use the 188 checks only**.

The configuration (Server URL + license key, same locations) and every script in this
repository are the same. A normal agent in an On-Device organisation blocks AI tools and asks
for the On-Device installer.

**With a ZeusLock server in your own network (ZeusLock On-Premise 0.2.1 or later):** On-Device
works the same way. Your server needs an On-Device licence and the model key file from ZeusLock
(on-prem install guide, step 9); the installers come from your own dashboard's **On-Device**
page, and the Server URL is your own API address. Each computer renews its model key from your
server every 30 days.

---

> **Known limits**
> - Windows: x64 only. macOS: Apple silicon only. Linux: Ubuntu Desktop `.deb` only (no RPM,
>   no headless servers); only the GNOME proxy setting is managed.
> - The agent protects a computer only while a user is signed in.
> - No automatic update: new versions come with a new installer.
> - The ChatGPT and Gemini **macOS desktop apps** are not covered; use the web versions.
> - Codex on Linux is not covered.

## Support

If a computer does not come up protected, work through
[docs/verify-and-troubleshoot.md](docs/verify-and-troubleshoot.md) first. If you are still
stuck, contact ZeusLock support with the diagnostics that page tells you to collect.
