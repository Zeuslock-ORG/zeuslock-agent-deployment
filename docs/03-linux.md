# Linux — Ansible Deployment (Debian/Ubuntu `.deb`)

Deploy the ZeusLock agent to Linux **desktops/workstations** with Ansible (or by
hand for a single machine), and bind them to your organization via
`/etc/zeuslock/agent.conf`.

> ℹ️ **Scope:** the agent protects **interactive desktop** use of AI tools in a
> browser — it runs as a tray app + local proxy in the user's graphical session.
> It is not meant for headless servers (no desktop session = nothing to protect).
> As with macOS, the **config mechanism** below is exact (read from the agent
> source); pilot the **install** on one machine before a fleet push.

**You'll do:**
1. [Prerequisites](#1-prerequisites)
2. [Get your values + the installer](#2-get-your-values--the-installer)
3. [Deploy with Ansible](#3-deploy-with-ansible-recommended)
4. [Verify](#4-verify) · [Manual install](#manual-install-single-machine)

---

## 1. Prerequisites

- Target machines run a Debian-family desktop (Ubuntu, Debian, Linux Mint…) with a
  graphical session, and can reach your **Server URL** over HTTPS (443).
- An Ansible control node with SSH + sudo to the targets (for the Ansible path).
- Your **Server URL** + **License key**
  ([main guide, Step 1](../README.md#before-you-start--get-your-two-values-step-1)).

---

## 2. Get your values + the installer

Download the Linux installer from your dashboard (**Agents → Download**, Linux) —
you'll get a `.deb` (e.g. `zeus-desktop-agent_<version>_amd64.deb`; an `arm64`
build is also available). The package is **generic** — no embedded credentials;
binding happens through the config file.

---

## 3. Deploy with Ansible (recommended)

Use the ready playbook **[scripts/linux/zeuslock-agent.yml](../scripts/linux/zeuslock-agent.yml)**.
It copies + installs the `.deb`, writes `/etc/zeuslock/agent.conf`, and adds a
desktop autostart entry so the agent launches in each user's session.

### 3.1 — Set your values

Edit the `vars:` block at the top of the playbook (or pass with `-e`):

```yaml
vars:
  zeus_server_url: "YOUR_SERVER_URL"     # https://api.zeuslock.ai
  zeus_license_key: "YOUR_LICENSE_KEY"   # zl_...
  zeus_deb_src: "./zeus-desktop-agent_amd64.deb"   # path on the control node
```

> 🔐 Keep the license key in an **Ansible Vault** variable, not in plain text:
> `ansible-vault encrypt_string 'zl_...' --name 'zeus_license_key'`.

### 3.2 — Run it

```bash
ansible-playbook -i inventory.ini zeuslock-agent.yml --ask-become-pass
# inventory.ini lists your target desktops under a [zeus_endpoints] group.
```

The playbook is **idempotent** — re-running only changes what drifted.

---

## 4. Verify

On a target machine (with a user logged into the desktop):

```bash
# 1. Installed?
dpkg -l | grep -i zeus

# 2. Config delivered?
sudo cat /etc/zeuslock/agent.conf

# 3. Agent running + inspection proxy up? (run inside the user's session)
pgrep -fa zeus | head
ss -ltnp 2>/dev/null | grep 9876 || sudo lsof -iTCP:9876 -sTCP:LISTEN
```

Then the **live test**: as the desktop user, open the browser → **chatgpt.com** →
paste a test secret such as `4111 1111 1111 1111`. The agent should flag/block it
and an **incident** should appear under **Incidents** in your dashboard.

Full checklist + troubleshooting: **[verify-and-troubleshoot.md](verify-and-troubleshoot.md)**.

---

## Manual install (single machine)

For a pilot or one-off — also the recommended first test. Use
**[scripts/linux/install-zeus-agent.sh](../scripts/linux/install-zeus-agent.sh)**:

```bash
# Edit the two values at the top of the script, then:
sudo bash install-zeus-agent.sh ./zeus-desktop-agent_amd64.deb
```

It installs the `.deb`, writes `/etc/zeuslock/agent.conf`, and adds the autostart
entry. Log out/in (or launch "Zeus - AI Data Protection" from your app menu) to
start the agent in your desktop session.

> **Config file options.** The managed scope `/etc/zeuslock/agent.conf`
> (`KEY=VALUE`) is used here. A JSON fallback at `/etc/zeus-dlp/config.json` is
> also supported — see [scripts/linux/config.json](../scripts/linux/config.json)
> and the [configuration reference](configuration-reference.md).

---

## Removing the agent

```bash
sudo pkill -f "zeus" || true
sudo apt-get remove -y zeus-desktop-agent   # or: sudo dpkg -r zeus-desktop-agent
sudo rm -f /etc/zeuslock/agent.conf /etc/zeus-dlp/config.json
sudo rm -f /etc/xdg/autostart/zeuslock-agent.desktop
```
