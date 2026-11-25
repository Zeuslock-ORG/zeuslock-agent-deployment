# macOS: deploy with an MDM (Jamf Pro, Mosyle, Kandji, Intune)

Deploy the ZeusLock agent to your Macs and bind them to your organisation with your MDM: one
package, one start-at-login script and one configuration profile. Pilot on one Mac first. For
agent 1.0.45 or later.

**Steps:**
1. [Requirements](#1-requirements)
2. [Get your values and the package](#2-get-your-values-and-the-package)
3. [Deploy the package and the start-at-login script](#3-deploy-the-package-and-the-start-at-login-script)
4. [Push the configuration profile](#4-push-the-configuration-profile)
5. [Verify](#5-verify)

Also: [One Mac without MDM](#one-mac-without-mdm) · [Upgrade](#upgrade) ·
[Remove](#remove-the-agent) · [If something fails](#if-something-fails)

---

## 1. Requirements

- Macs with **Apple silicon** (M1 or later), enrolled in your MDM.
- The Macs reach your Server URL over HTTPS (443).
- Your **Server URL** and **license key** (`zl_…`):
  [main guide, Step 1](../README.md#step-1-get-your-two-values).

## 2. Get your values and the package

In the dashboard: **Agents** → **Download Agent** → macOS.

Expected result: `ZeusLock-<version>-arm64.pkg` (for the MDM) or `ZeusLock-<version>-arm64.dmg`.
Both are signed and notarised by Apple; upload the `.pkg` as it is, do not repackage it. It
installs `/Applications/ZeusLock - AI Data Protection.app` and carries no credentials.

## 3. Deploy the package and the start-at-login script

The app does not register itself to start at login. Your MDM delivers that with
[scripts/macos/install-launchagent.sh](../scripts/macos/install-launchagent.sh): it writes the
LaunchAgent `/Library/LaunchAgents/com.zeuslock.agent.plist`, which starts the agent in every
user's session at login, and starts it now for the user who is signed in.

1. Upload the `.pkg` and add the script, run as root **after** the package:
   - **Jamf Pro:** **Settings → Computer Management → Packages** → upload the `.pkg`.
     **Settings → Computer Management → Scripts → New** → paste `install-launchagent.sh`.
     **Computers → Policies → New**: trigger **Enrollment Complete** and **Recurring Check-in**,
     frequency **Once per computer**, payload **Packages** (the `.pkg`, **Install**) and
     **Scripts** (the script, priority **After**) → scope to a pilot group → **Save**.
   - **Kandji:** **Library → Add new → Custom App** → upload the `.pkg` (installation type
     **Installer package**) → paste the script in **Post-install script** → assign to a
     Blueprint.
   - **Mosyle:** **Management → Custom Apps** → upload the `.pkg`; **Management → Custom
     Commands** → paste the script, run after the app install → assign to the device group.
   - **Intune:** **Apps → macOS → Add → macOS app (PKG)** → upload the `.pkg` → paste the
     script as the **Post-install script** → assign.
2. Wait for the pilot Mac to check in.

Expected result: on the Mac, `/Applications/ZeusLock - AI Data Protection.app` and
`/Library/LaunchAgents/com.zeuslock.agent.plist` exist.

## 4. Push the configuration profile

1. Open [scripts/macos/com.zeuslock.agent.mobileconfig](../scripts/macos/com.zeuslock.agent.mobileconfig)
   and replace `YOUR_SERVER_URL` and `YOUR_LICENSE_KEY`.
2. Upload it as a custom configuration profile and scope it to the same Macs:
   - **Jamf Pro:** **Computers → Configuration Profiles → Upload**. (Or **New** →
     **Application & Custom Settings → Upload**, preference domain `com.zeuslock.agent`.)
   - **Kandji:** **Library → Add new → Custom Profile**.
   - **Mosyle:** **Management → Custom Profiles**.
   - **Intune:** **Devices → macOS → Configuration → Create → New policy → Templates →
     Custom**, deployment channel **Device channel**.

Expected result: on the Mac, `/Library/Managed Preferences/com.zeuslock.agent.plist` exists.

macOS writes and protects that file. Like every managed preference, the Mac's local accounts
can read it, which the agent needs because it runs as the signed-in user. The license key
there makes the Mac **managed**: the menu bar has no **Quit** and the agent is restarted if it
is stopped. Keep your filled-in `.mobileconfig` out of shared folders and repositories.

## 5. Verify

1. Sign in to the pilot Mac as a normal user.

   Expected result: the ZeusLock icon appears in the menu bar.

2. At its first start the agent asks to trust its certificate **ZeusLock DLP Proxy CA** in the
   user's login keychain: the user enters their password. It may also ask for an
   administrator password to set the Chrome, Edge and Brave proxy policy for the whole Mac; a
   standard user can cancel it (the policy for that user is set without it).

   Expected result: the menu bar icon shows **Protection active** and your organisation's name.

3. In Terminal:

   ```bash
   ls -d "/Applications/ZeusLock - AI Data Protection.app"
   sudo defaults read "/Library/Managed Preferences/com.zeuslock.agent"
   launchctl print "gui/$(id -u)/com.zeuslock.agent" | head -3
   lsof -iTCP:9876 -sTCP:LISTEN
   ```

   Expected result: the app path; `ServerUrl` and `LicenseKey`; the LaunchAgent; one listener
   on port 9876.

4. Open **chatgpt.com** in Chrome or Safari and send `My card is 4111 1111 1111 1111`.

   Expected result: the agent flags or blocks it, an incident appears under **Incidents**,
   and the Mac is listed under **Agents** in the dashboard.

Full checklist and logs: [verify-and-troubleshoot.md](verify-and-troubleshoot.md).

---

## One Mac without MDM

For a pilot or a single Mac. Download the whole `scripts/macos/` folder, then in Terminal:

```bash
sudo bash install-zeuslock-agent.sh ~/Downloads/ZeusLock-<version>-arm64.pkg
# Server URL (e.g. https://api.zeuslock.ai): https://api.zeuslock.ai
# License key (input hidden): zl_...
```

Expected result: `==> Done.` and the agent starts. Approve the certificate prompt.

The script installs or upgrades the app (`.pkg` or `.dmg`), writes
`/Library/Application Support/ZeusLockDLP/config.json` as `0640 root:staff` (folder `0750`: every
user account can read it, system daemons cannot), and runs `install-launchagent.sh`. Leave
`LICENSE_KEY` as the placeholder in the script: it asks for the key with hidden input, so the
key never sits in a file, your shell history or a process list.

The dashboard's **Local agent install** page does the same by hand (drag the app from the
`.dmg`, then a `sudo tee` command for `config.json`). It does not add the LaunchAgent: run
`sudo bash install-launchagent.sh` afterwards, or the agent will not start at login.

A Mac set up with `config.json` is not managed: the user can quit the agent.

## Upgrade

The agent does not update itself. Upload the new `.pkg` to your MDM and push it to the Macs
with the same script (for Jamf: a new policy, **Once per computer**). The LaunchAgent keeps
pointing at the same app path. Without MDM, run `install-zeuslock-agent.sh` with the new file:
it stops the running agent first and starts the new one.

To switch a Mac to the On-Device installer, push the On-Device `.pkg` the same way.

## Remove the agent

1. Remove the `com.zeuslock.agent` profile and the package policy in your MDM.
2. Run [scripts/macos/uninstall-zeuslock-agent.sh](../scripts/macos/uninstall-zeuslock-agent.sh)
   as root (MDM script, or `sudo bash uninstall-zeuslock-agent.sh`).

Expected result: `==> Done. ZeusLock is removed and the network settings are restored.`

The script stops the agent and its LaunchAgents, switches off any proxy that still points at
the agent, removes the agent's Chrome/Edge/Brave proxy policy and its Claude Code and Cursor
settings for every user, removes the certificate from the System keychain and from each user's
login keychain, then deletes the app, the configuration and each user's agent data. Do not
delete the app by hand: a Mac left pointing at the agent's proxy cannot reach the web until
the setting is switched off.

---

## If something fails

| Symptom | Fix |
|---|---|
| App installed but the agent does not start at login | `ls /Library/LaunchAgents/com.zeuslock.agent.plist`. Missing: run `install-launchagent.sh` as root (MDM script or `sudo bash`). |
| Menu bar shows **Agent not configured** | `sudo defaults read "/Library/Managed Preferences/com.zeuslock.agent"`. Empty: check the profile scope in your MDM; the payload domain must be `com.zeuslock.agent`. |
| Browsers show a certificate warning on AI sites | The user cancelled the certificate prompt. Quit and reopen the agent and approve it, then restart the browser. |
| Chrome closes when the agent starts or quits | Expected: Chrome is restarted so its proxy policy takes effect. |
| No internet after the agent was stopped or crashed | Wait up to 3 minutes, or run the reset in [verify-and-troubleshoot.md](verify-and-troubleshoot.md#network-after-the-agent-stops). |

> **Known limits**
> - Apple silicon only.
> - The ChatGPT and Gemini macOS desktop apps are not covered; use the web versions.
> - After the agent is killed or crashes, the network can stay off for up to 3 minutes until
>   its cleanup runs (managed Macs: until the agent is back).
