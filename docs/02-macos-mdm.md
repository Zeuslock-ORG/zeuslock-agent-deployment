# macOS — MDM Deployment (Jamf, Mosyle, Kandji, Intune)

Deploy the ZeusLock agent to your Macs and bind them to your organization using
your MDM. The same two ingredients as every platform: **install the app**, then
**deliver the config** (a managed-preferences profile for domain
`com.zeuslock.agent`).

> ℹ️ The **configuration mechanism** below (managed-preferences domain
> `com.zeuslock.agent`, and the JSON fallback at
> `/Library/Application Support/ZeusLockDLP/config.json`) is read directly by the
> agent and is exact. The **install/MDM upload** steps are standard macOS practice
> — run a **pilot on one Mac** (the [Manual section](#manual-install-single-mac))
> before a fleet push.

**You'll do:**
1. [Prerequisites](#1-prerequisites)
2. [Get your values + the installer](#2-get-your-values--the-installer)
3. [Deploy the app via MDM](#3-deploy-the-app-via-mdm)
4. [Push the config profile](#4-push-the-config-profile-the-important-part)
5. [Approvals the agent needs](#5-approvals-the-agent-needs)
6. [Verify](#6-verify) · [Manual install](#manual-install-single-mac)

---

## 1. Prerequisites

- Macs enrolled in your MDM (Jamf Pro, Mosyle, Kandji, Microsoft Intune, …).
- Endpoints can reach your **Server URL** over HTTPS (443).
- Your **Server URL** + **License key** ([main guide, Step 1](../README.md#before-you-start--get-your-two-values-step-1)).

---

## 2. Get your values + the installer

Download the macOS installer from your dashboard (**Agents → Download**, macOS).
You'll get a `.dmg` containing **ZeusLock - AI Data Protection.app**.

> For MDM fleet deployment, most tools deploy a **`.pkg`**. If your MDM can only
> deploy a `.pkg`, wrap the `.app` from the DMG into a component package (e.g.
> `pkgbuild --component "/path/ZeusLock - AI Data Protection.app" --install-location
> /Applications ZeusLock.pkg`), or use your MDM's "package a .app" / Composer
> workflow. Jamf/Kandji/Mosyle all support uploading a `.pkg`.

The app is **generic** — no embedded credentials. Binding happens in
[Step 4](#4-push-the-config-profile-the-important-part).

---

## 3. Deploy the app via MDM

Upload the `.pkg` (or `.app`) to your MDM and scope it to the target Macs:

- **Jamf Pro:** upload the `.pkg` to a Distribution Point → create a **Policy**
  (Trigger: Enrollment/Recurring) with a **Packages** payload → scope to a Smart
  Group → deploy.
- **Mosyle:** **Management → Apps → Custom Apps (macOS)** → upload the `.pkg` →
  assign to a device group.
- **Kandji:** **Library → Add → Custom App** → upload the `.pkg` (Install type:
  Installer package) → assign to a Blueprint.
- **Intune:** **Apps → macOS → Add → macOS app (PKG)** → upload → assign.

Installs to `/Applications/ZeusLock - AI Data Protection.app`.

---

## 4. Push the config profile (the important part)

Deliver `ServerUrl` + `LicenseKey` as a **managed-preferences** profile for the
domain **`com.zeuslock.agent`**. Use the ready template
**[scripts/macos/com.zeuslock.agent.mobileconfig](../scripts/macos/com.zeuslock.agent.mobileconfig)** —
open it, replace `YOUR_SERVER_URL` and `YOUR_LICENSE_KEY`, then upload it as a
**Configuration Profile / Custom Settings**:

- **Jamf Pro:** **Configuration Profiles → Upload** the `.mobileconfig`
  (or **Application & Custom Settings → External Applications**, domain
  `com.zeuslock.agent`, and paste the keys) → scope + deploy.
- **Mosyle:** **Management → Profiles → Custom Profile** → upload the `.mobileconfig`.
- **Kandji:** **Library → Add → Custom Profile** → upload the `.mobileconfig`.
- **Intune:** **Devices → Configuration → Create → Templates → Custom** → upload
  the `.mobileconfig`.

The profile lands at `/Library/Managed Preferences/com.zeuslock.agent.plist`, which
is the agent's managed scope (highest priority).

> **Prefer a plain file instead of a profile?** You can drop the JSON fallback at
> `/Library/Application Support/ZeusLockDLP/config.json` (template:
> [scripts/macos/config.json](../scripts/macos/config.json)) via an MDM script or
> Composer. The managed profile is preferred for fleets because it self-heals and
> is tamper-resistant. See the [configuration reference](configuration-reference.md).

---

## 5. Approvals the agent needs

The agent runs in the user session and inspects AI traffic, so macOS will want a
few approvals. Pre-approve them via MDM so users aren't prompted:

- **Login item / background item** — allow "ZeusLock - AI Data Protection" to run at
  login (a **Service Management – Managed Login Items** profile, or the app's own
  setting on first launch).
- **Proxy trust** — the agent uses a local inspection proxy; ensure its CA is
  trusted (the app installs it on first run; MDM can also push it as a
  **Certificate** payload to the System keychain and mark it trusted).
- **Privacy (TCC)** — if your policy monitors screenshots/files, grant the
  relevant **Privacy Preferences Policy Control (PPPC)** permissions via MDM.

> These pre-approvals are optional for a pilot (the user can click through the
> prompts on first launch) but recommended for a smooth fleet rollout.

---

## 6. Verify

On a target Mac, after the app + profile land and the user logs in:

```bash
# 1. Installed?
ls -d "/Applications/ZeusLock - AI Data Protection.app" && echo "app present"

# 2. Managed config delivered?
defaults read com.zeuslock.agent 2>/dev/null || \
  sudo defaults read /Library/Managed\ Preferences/com.zeuslock.agent

# 3. Agent running + inspection proxy up?
pgrep -fl "ZeusLock - AI Data Protection"
lsof -iTCP:9876 -sTCP:LISTEN

# 4. (fallback config, if you used it)
cat "/Library/Application Support/ZeusLockDLP/config.json"
```

Then the **live test**: as a normal user, open Chrome/Safari → **chatgpt.com** →
paste a test secret such as `4111 1111 1111 1111`. The agent should flag/block it
and an **incident** should appear under **Incidents** in your dashboard.

Full checklist + troubleshooting: **[verify-and-troubleshoot.md](verify-and-troubleshoot.md)**.

---

## Manual install (single Mac)

For a pilot or a one-off machine — this is also the recommended first test before a
fleet push. Use **[scripts/macos/install-zeus-agent.sh](../scripts/macos/install-zeus-agent.sh)**:

```bash
# Edit the two values at the top of the script first, then:
sudo bash install-zeus-agent.sh /path/to/ZeusLock.dmg
```

It mounts the DMG, copies the app to `/Applications`, and writes the config to
`/Library/Application Support/ZeusLockDLP/config.json`. Then launch the app from
Applications and complete any first-run approval prompts.

---

## Upgrading from 1.0.11 or earlier (app was "Zeus - AI Data Protection.app")

Version 1.0.12 renamed the bundle to **ZeusLock - AI Data Protection.app**. The bundle
identifier `com.zeuslock.desktop-agent` is unchanged, so login-item / background-item
approvals and the configuration profile carry over. Because macOS treats a renamed
`.app` as a new file, the **old bundle must be removed** or two copies exist:

- `install-zeus-agent.sh` does it (quits and deletes `Zeus - AI Data Protection.app`
  before copying the new one).
- MDM: add a pre-install step that removes `/Applications/Zeus - AI Data Protection.app`
  (`pkill -f "Zeus - AI Data Protection"; rm -rf "/Applications/Zeus - AI Data
  Protection.app"`), or push an uninstall of the old package first.
- The inspection certificate already trusted on the Mac stays valid; only *fresh*
  installs generate the new `ZeusLock DLP Proxy CA`.

## Upgrading from 1.0.12 or earlier (paths were "ZeusDLP")

Version 1.0.13 renamed the remaining paths:

| | 1.0.12 and earlier | 1.0.13+ |
|---|---|---|
| Admin config | `/Library/Application Support/ZeusDLP/config.json` | `/Library/Application Support/ZeusLockDLP/config.json` |
| Per-user data | `~/Library/Application Support/Zeus DLP Agent/` | `~/Library/Application Support/ZeusLock DLP Agent/` |

The agent **migrates the per-user directory itself** on first launch (registration
and the trusted certificate carry over) and still **reads the old admin config path**
as a fallback, so an upgrade keeps working untouched. To finish the move, write the
config to the new path and delete the old file — `install-zeus-agent.sh` does both.

## Removing the agent

```bash
sudo pkill -f "ZeusLock - AI Data Protection"
sudo rm -rf "/Applications/ZeusLock - AI Data Protection.app"
sudo rm -f "/Library/Application Support/ZeusLockDLP/config.json"
# and remove the com.zeuslock.agent configuration profile from your MDM
```
