# Linux: deploy with Ansible (Ubuntu Desktop `.deb`)

Deploy the ZeusLock agent to Ubuntu desktops with Ansible, or with one script on a single
desktop, and bind them to your organisation through `/etc/zeuslock/agent.conf`. For agent
1.0.45 or later.

**Steps:**
1. [Requirements](#1-requirements)
2. [Get your values and the package](#2-get-your-values-and-the-package)
3. [Deploy with Ansible](#3-deploy-with-ansible)
4. [Verify](#4-verify)

Also: [One desktop](#one-desktop) · [Upgrade](#upgrade) · [Remove](#remove-the-agent) ·
[If something fails](#if-something-fails)

---

## 1. Requirements

- **Ubuntu Desktop** (24.04 is the tested version) with the GNOME desktop, **amd64 or arm64**.
  The agent protects people at a desktop session: it is not for headless servers. RPM-based
  distributions (RHEL, Fedora) are not supported.
- The desktops reach your Server URL over HTTPS (443).
- For Ansible: a control node with SSH and sudo on the desktops.
- Your **Server URL** and **license key** (`zl_…`):
  [main guide, Step 1](../README.md#step-1-get-your-two-values).

## 2. Get your values and the package

In the dashboard: **Agents** → **Download Agent** → Linux → **.deb (amd64)** or **.deb (arm64)**.

Expected result: `zeuslock-desktop-agent_<version>_amd64.deb` (or `_arm64.deb`). It carries no
credentials. It installs the command `zeuslock-ai-data-protection` and starts the agent at
every user's login (`/etc/xdg/autostart/zeuslock-agent.desktop`).

### Which configuration file

| You deploy with | File | The desktop is |
|---|---|---|
| Ansible or `install-zeuslock-agent.sh` (this guide) | `/etc/zeuslock/agent.conf` | **managed**: no **Quit** in the agent menu; the agent is restarted if it is stopped |
| The dashboard's **Local agent install** page (one desktop by hand) | `/etc/zeuslock-dlp/config.json` | not managed: the user can quit the agent |

Use one or the other. When both exist, `/etc/zeuslock/agent.conf` wins.

## 3. Deploy with Ansible

Use the playbook [scripts/linux/zeuslock-agent.yml](../scripts/linux/zeuslock-agent.yml). It
installs or upgrades the `.deb`, creates the group `zeuslock`, adds the desktop users to it,
and writes `/etc/zeuslock/agent.conf` as `0640 root:zeuslock`.

1. Encrypt the key with Ansible Vault:

   ```bash
   ansible-vault encrypt_string 'zl_...' --name 'zeus_license_key'
   ```

   Expected result: a `zeus_license_key: !vault |` block. Put it in your vars file or in the
   playbook's `vars:` in place of the placeholder.

2. Set the other values in the `vars:` block of the playbook:

   ```yaml
   zeus_server_url: "https://api.zeuslock.ai"
   zeus_deb_src: "./zeuslock-desktop-agent_1.0.45_amd64.deb"   # path on the control node
   zeus_config_group: "zeuslock"   # group allowed to read the config
   zeus_config_users: []           # empty = every local login account
   ```

3. List the desktops under `[zeus_endpoints]` in `inventory.ini`, then run:

   ```bash
   ansible-playbook -i inventory.ini zeuslock-agent.yml --ask-become-pass --ask-vault-pass
   ```

   Expected result: `failed=0` for every desktop. The key is never printed, also with `-v`
   and `--diff`. Running it again is safe.

4. Each desktop user logs out and back in once (the new group membership needs a fresh login).

### Who can read the configuration

`agent.conf` holds your license key, and the agent runs in each user's desktop session, not
as root. So the file is `0640 root:zeuslock` (folder `/etc/zeuslock` `0750`) and the desktop
users are members of `zeuslock`:

- By default every local login account (UID between `UID_MIN` and `UID_MAX` in
  `/etc/login.defs`, with a real shell) is added. To choose them, list them in
  `zeus_config_users`.
- System and service accounts (`www-data`, `nobody`…) are not members and cannot read the key.
- **Users created later** need `sudo usermod -aG zeuslock <user>` (or a new playbook run) and a
  new login. Until then the agent shows **Configuration not readable - ask your
  administrator**.
- **Directory logins (SSSD / AD / LDAP):** set `zeus_config_group` (or `CONFIG_GROUP` in the
  script) to an existing directory group of your desktop users, e.g. `"domain users"`. No
  local group is created and no membership is changed.

## 4. Verify

1. Log in to a desktop as a normal user.

   Expected result: the ZeusLock icon appears in the top bar.

2. At its first start the agent asks once for an administrator password (**Authentication
   Required**) to trust its certificate for the system, Chrome/Chromium/Brave and Firefox.
   An administrator types it.

   Expected result: the icon shows **Protection active** and your organisation's name.

3. In a terminal:

   ```bash
   dpkg-query -W zeuslock-desktop-agent
   sudo cat /etc/zeuslock/agent.conf
   stat -c '%a %U:%G' /etc/zeuslock/agent.conf
   id -nG | tr ' ' '\n' | grep -x zeuslock
   ss -ltn | grep 9876
   ```

   Expected result: version 1.0.45 or later; `ServerUrl` and `LicenseKey`; `640 root:zeuslock`;
   `zeuslock`; one listener on `127.0.0.1:9876`.

4. Restart Firefox if it was open, then open **chatgpt.com** and send
   `My card is 4111 1111 1111 1111`.

   Expected result: the agent flags or blocks it, an incident appears under **Incidents**,
   and the desktop is listed under **Agents** in the dashboard.

Where the agent puts its certificate trust:

| Browser | File |
|---|---|
| System store (most apps) | `/usr/local/share/ca-certificates/zeuslock-dlp-ca.crt` |
| Chromium, Google Chrome, Brave | `zeuslock-dlp-ca.json` in `/etc/chromium-browser/policies/managed/`, `/etc/opt/chrome/policies/managed/`, `/etc/brave/policies/managed/` |
| Firefox (deb, tarball and snap) | `/etc/firefox/policies/policies.json` lists `/etc/firefox/policies/zeuslock-dlp-ca.crt` |

An existing `policies.json` is kept: the agent only adds its certificate. Full checklist and
logs: [verify-and-troubleshoot.md](verify-and-troubleshoot.md).

---

## One desktop

For a pilot, or a desktop outside Ansible, with the same managed configuration as the
playbook. Download the `.deb` and
[scripts/linux/install-zeuslock-agent.sh](../scripts/linux/install-zeuslock-agent.sh), then:

```bash
sudo bash install-zeuslock-agent.sh ./zeuslock-desktop-agent_1.0.45_amd64.deb
# Server URL (e.g. https://api.zeuslock.ai): https://api.zeuslock.ai
# License key (input hidden): zl_...
```

Expected result: `==> Done.` Log out and back in: the agent starts.

The script installs or upgrades the `.deb`, creates the group `zeuslock` and adds the local
login accounts, and writes `/etc/zeuslock/agent.conf` (`0640 root:zeuslock`). Leave
`LICENSE_KEY` as the placeholder in the script: it asks for the key with hidden input, so the
key never sits in a file, your shell history or a process list.

The dashboard's **Local agent install** page is the other way for one desktop:
`sudo apt install ./zeuslock-desktop-agent_*.deb`, then its `sudo tee` command writes
`/etc/zeuslock-dlp/config.json` (not managed).

## Upgrade

The agent does not update itself. Put the new `.deb` on the control node, set `zeus_deb_src`
to it and run the playbook again; on one desktop, run `install-zeuslock-agent.sh` with the new
file. Agents already running keep the old version until the user logs in again. To switch a
desktop to the On-Device package, deploy `zeuslock-desktop-agent-ondevice_<version>_<arch>.deb`
the same way: it replaces the normal package.

## Remove the agent

Run [scripts/linux/uninstall-zeuslock-agent.sh](../scripts/linux/uninstall-zeuslock-agent.sh)
on each desktop:

```bash
sudo bash uninstall-zeuslock-agent.sh
# or for a fleet:
ansible zeus_endpoints -i inventory.ini -b --ask-become-pass -m ansible.builtin.script -a uninstall-zeuslock-agent.sh
```

Expected result: `==> Done. ZeusLock is removed.`

Removing the package stops every running agent and gives each signed-in user's GNOME proxy,
Claude Code and Cursor settings back; users who are not signed in get the same at their next
login. The script also removes the configuration and the certificate trust (system store,
Chrome/Chromium/Brave policy, the ZeusLock entry in Firefox's `policies.json`). The group
`zeuslock` is kept: `sudo groupdel zeuslock` removes it.

---

## If something fails

| Symptom | Fix |
|---|---|
| Agent shows **Configuration not readable - ask your administrator** | The user is not in group `zeuslock`, or has not logged in again since: `sudo usermod -aG zeuslock <user>`, then log out and in. |
| Agent shows **Agent not configured** | `sudo cat /etc/zeuslock/agent.conf` must show `ServerUrl` and `LicenseKey`. Re-run the playbook or the script. |
| Firefox shows **Warning: Potential Security Risk Ahead** (or Chrome **Your connection is not private**) on AI sites | The password prompt at the agent's first start was cancelled or nobody with admin rights answered it. Quit and reopen the agent with an administrator at hand, approve the prompt, then fully close and reopen the browser (also the Firefox snap). |
| Playbook fails with `Dependency is not satisfiable: libasound2` | You run an older copy of the playbook that installs with the `apt` module. Use the playbook in this repository (it uses `apt-get`). |
| No internet after the agent was stopped or crashed | Wait up to 3 minutes, or run the reset in [verify-and-troubleshoot.md](verify-and-troubleshoot.md#network-after-the-agent-stops). |

> **Known limits**
> - Ubuntu Desktop `.deb` only (amd64, arm64); only the GNOME proxy setting is set (KDE's own
>   proxy setting is not).
> - The certificate prompt needs an administrator password once per user.
> - Codex on Linux is not covered.
> - After the agent is killed or crashes on a desktop that is not managed, the network comes
>   back after 1 to 3 minutes.
