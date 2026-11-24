# Configuration reference

How the ZeusLock agent is configured: where it reads its settings, which source wins, every
key that works, and how the license key is protected on the computer. Every platform guide
points here. For agent 1.0.45 or later.

---

## Rule 1: where the agent reads its configuration

The agent reads its configuration at start, and the managed policy again at most once a
minute. Two places, in this order:

1. **Managed policy** (GPO / MDM / Ansible). Read first.
   - Windows: registry key `HKLM\SOFTWARE\Policies\ZeusLock`
   - macOS: profile for domain `com.zeuslock.agent`
     (`/Library/Managed Preferences/com.zeuslock.agent.plist`)
   - Linux: `/etc/zeuslock/agent.conf`
2. **Admin config file** (JSON, one computer; the dashboard's **Local agent install** writes it).
   Used when the managed policy holds no `LicenseKey`.
   - Windows: `C:\ProgramData\ZeusLockDLP\config.json`
   - macOS: `/Library/Application Support/ZeusLockDLP/config.json`
   - Linux: `/etc/zeuslock-dlp/config.json`

With neither, the agent shows **Agent not configured**.

**Managed computers.** When the managed policy holds `ServerUrl` or `LicenseKey`, the computer
is managed: the tray or menu bar has no **Quit**, a watchdog restarts the agent if it is ended,
and `ManagedUncleanStop` applies. A computer configured only through the JSON file is not
managed.

**After a change**, restart the agent (or the computer) so it reads the new values for sure.

> A tester without admin rights can put the same JSON in `zeuslock-config.json` in the agent's
> data folder (Windows `%APPDATA%\ZeusLock DLP Agent\`, macOS
> `~/Library/Application Support/ZeusLock DLP Agent/`, Linux `~/.config/ZeusLock DLP Agent/`).
> It is read only when neither file above exists. Not for fleets.

---

## Rule 2: the keys

The two keys that **must** be set:

| Key | Value | Example |
|---|---|---|
| `ServerUrl` | Your ZeusLock API address | `https://api.zeuslock.ai` (your own server: `https://<your API host>`) |
| `LicenseKey` | Your organisation's API key (dashboard **API Keys**) | `zl_xxxxxxxxxxxxxxxxxxxx` |

The server finds your organisation from the key; nothing else is needed.

### Optional keys

You normally set only `ServerUrl` and `LicenseKey`. These change the agent's behaviour on the
computers that receive them. **Where** says which source the agent reads them from: "policy"
means the managed policy only (not the JSON file).

| Key | Type | Default | Where | Meaning |
|---|---|---|---|---|
| `UiLanguage` | string | not set | policy | Language of everything the agent shows (window, dialogs, tray, notifications, block messages written into AI tools): `fr`, `en`, `es` or `de`. Users cannot change it. Not set: the dashboard's **Settings → Protection → Agent language**, else the user's choice in the agent window, else the computer's language, else English. |
| `BlockFilesOnAlert` | bool | not set | policy | Forces the dashboard setting **Block file uploads on alert detections** (Settings → Protection) on or off on these computers. |
| `NetworkMonitoring` | bool | `true` | policy | `false` switches all inspection off: no local proxy, nothing checked. Use only to pause protection on a group of computers. |
| `ShadowAiDiscovery` | bool | `true` | policy | Local on/off switch for **Shadow AI** discovery (which AI tools are used, metadata only). It runs only when it is also switched on in the dashboard. |
| `ShadowAiDiscoveryExtraDomains` | string | empty | policy | Extra exact domains (your own AI gateways) for Shadow AI discovery. Comma, semicolon or newline separated. |
| `ShadowAiDiscoveryExtraWildcardDomains` | string | empty | policy | The same, for whole domains and their subdomains. |
| `ShadowAiDiscoveryExtraHostPatterns` | string | empty | policy | The same, as host patterns. |
| `ManagedUncleanStop` | string | `protect` | policy | Managed computers only: what happens when the agent is ended without its own cleanup (killed, crashed). `protect`: the agent is restarted and the browsers have no internet until it runs. `restore-network`: like computers that are not managed, the network comes back after a few minutes, unprotected until the agent starts again. |
| `UpstreamProxy` | string | `auto` | policy, then JSON | Your existing corporate proxy: `auto`, `off`, `http://host:port` or `http://user:password@host:port`. See [Existing corporate proxy](04-existing-corporate-proxy.md). |
| `TrustSystemCa` | bool | `true` | policy, then JSON | Trust the OS certificate store for the agent's outbound TLS (needed behind a TLS-inspecting proxy). |
| `ExtraCaFile` | string | none | policy, then JSON | Path to a PEM bundle of extra CAs to trust. |
| `ManageSystemProxy` | bool | `true` | policy, then JSON | `false`: the agent never changes the system proxy; your PAC must send AI traffic to `127.0.0.1:9876`. |
| `AllowContentLogging` | bool | `false` | policy | **Test computers only.** Lets the testing logs record prompt text, file text and file names. No effect while testing logs are off. Never on users' computers. |

The **policy itself** (which data is anonymised or blocked) is not set on the computer: it lives
in the dashboard (**Policies**). The agent fetches it with the license key and picks up changes
by itself.

### Reserved keys: no effect

The Windows ADMX template and older templates list these keys. In 1.0.45 the agent reads
**none** of them; setting them changes nothing. Leave them out.

`AgentEnabled`, `BlockingEnabled`, `AutoUpdate`, `ClipboardMonitoring`, `ScreenshotMonitoring`,
`FileMonitoring`, `LogLevel`, `HeartbeatInterval`, `RulesSyncInterval`, `OrganizationName`.

There is no automatic update: new versions come with a new installer
([README, Updates](../README.md#updates)). To pause protection, use `NetworkMonitoring=false`.

---

## Value formats per source

The key names are the same everywhere; only the encoding differs.

### Windows registry (`HKLM\SOFTWARE\Policies\ZeusLock`)

Strings are `REG_SZ`. On/off keys are `REG_DWORD` (`1` = on, `0` = off).

```
ServerUrl    REG_SZ     https://api.zeuslock.ai
LicenseKey   REG_SZ     zl_xxxxxxxxxxxxxxxxxxxx
UiLanguage   REG_SZ     fr
```

### macOS profile (domain `com.zeuslock.agent`)

A configuration profile (`.mobileconfig`) whose payload sets the keys. On/off keys are
`<true/>` / `<false/>` (`1` / `0` also work). Template:
[scripts/macos/com.zeuslock.agent.mobileconfig](../scripts/macos/com.zeuslock.agent.mobileconfig).

### Linux (`/etc/zeuslock/agent.conf`)

`KEY=VALUE`, one per line. `#` and `;` start comments. Quotes are optional. On/off keys are
`true` / `false`. Template: [scripts/linux/agent.conf](../scripts/linux/agent.conf).

```ini
ServerUrl=https://api.zeuslock.ai
LicenseKey=zl_xxxxxxxxxxxxxxxxxxxx
UiLanguage=fr
```

### JSON file (all platforms)

UTF-8, with or without a byte-order mark. `apiUrl` / `apiKey` are still read as old names for
`ServerUrl` / `LicenseKey`; use the new names.

```json
{
  "ServerUrl": "https://api.zeuslock.ai",
  "LicenseKey": "zl_xxxxxxxxxxxxxxxxxxxx"
}
```

On Windows, write it without a byte-order mark as the dashboard command does
(`[System.IO.File]::WriteAllText(..., (New-Object System.Text.UTF8Encoding($false)))`).

---

## Protecting the license key on the endpoint

The license key binds computers to your organisation, so every place that holds it is locked
down. One constraint shapes the permissions: **the agent runs in each user's session, not as
root or SYSTEM**, so the signed-in user must keep read access. Everything else (service and
daemon accounts, network logons, sandboxed apps) is shut out. The scripts in this repository
set these permissions and re-assert them on every run:

| OS | Where the key is | Permissions the scripts set | Who can read it |
|---|---|---|---|
| Windows | `HKLM\SOFTWARE\Policies\ZeusLock` | inheritance removed; SYSTEM + Administrators full control; **INTERACTIVE** read | signed-in users (where the agent runs), administrators, SYSTEM |
| Windows | `C:\ProgramData\ZeusLockDLP\` (JSON file) | the same, set with `icacls` | the same |
| macOS | `/Library/Application Support/ZeusLockDLP/config.json` | `0640 root:staff`, folder `0750` | local and mobile user accounts (all in group `staff`), root |
| macOS | `/Library/Managed Preferences/com.zeuslock.agent.plist` (profile) | written by macOS | managed by macOS; readable by local accounts, like every managed preference |
| Linux | `/etc/zeuslock/agent.conf` (and the JSON file, if present) | `0640 root:zeuslock`, folder `0750` | members of group `zeuslock` (your desktop users), root |

What to know:

- **A user who runs the agent can read the key.** The agent needs it, and it runs as that user.
  Treat the key as an organisation credential present on every computer: if one leaks, create a
  new key on the **API Keys** page, deploy it, then **Revoke** the old one.
- **Keep the key out of shared places on the way.** The scripts ask for the key with hidden
  input instead of taking it on the command line. On Windows, a GPO startup script is stored in
  SYSVOL, which every domain user can read: point the script at a key file only domain
  computers can read ([Windows guide, A.1](01-windows-gpo.md#a1-put-your-values-in-the-script)).
  With Ansible, keep the key in Ansible Vault.
- **Linux: users added later** must join the `zeuslock` group
  (`sudo usermod -aG zeuslock <user>`, effective at their next login). Until then the agent
  shows **Configuration not readable - ask your administrator**
  ([Linux guide](03-linux.md#who-can-read-the-configuration)).
- **If you deliver the configuration another way** (your own scripts, a GPO Registry
  preference, the JSON file), apply the same permissions. The agent never changes them itself.

---

## The installer is generic

The installer from the dashboard is the **same file for every customer** and contains **no
credentials**. You can cache and redistribute it, and bind computers to your organisation only
through configuration. It also means **an install alone does nothing** until `ServerUrl` and
`LicenseKey` arrive from one of the sources above.

| OS | Installer | Installs |
|---|---|---|
| Windows | `ZeusLock-<version>.msi` | per machine, `C:\Program Files\ZeusLock - AI Data Protection\`; silent with `/qn`, no properties; starts at every sign-in |
| Windows | `ZeusLock-Setup-<version>.exe` | per machine, `C:\Program Files\ZeusLock\ZeusLock - AI Data Protection\`; starts the agent at the end and at every sign-in |
| macOS | `ZeusLock-<version>-arm64.pkg` / `.dmg` | `/Applications/ZeusLock - AI Data Protection.app`; start at login comes from a LaunchAgent ([macOS guide](02-macos-mdm.md)) |
| Linux | `zeuslock-desktop-agent_<version>_<arch>.deb` | `/opt/ZeusLock/`, command `zeuslock-ai-data-protection`; starts at every user's login |

On-Device organisations use the On-Device installers from the dashboard **On-Device** page
(file names with `OnDevice` / `-ondevice`). They take the same configuration.

---

## Runtime facts every admin should know

- **The agent runs in the user's session.** It is a tray (menu bar) application with a local
  inspection proxy on `127.0.0.1:9876`. It protects a computer only while a user is signed in.
- **First start registers the computer** with the server; it then appears under **Agents** in
  the dashboard.
- **Where prompts are checked.** In the normal (cloud) mode the agent sends the text it
  inspects to the ZeusLock server, which applies your policy and answers anonymise, block or
  allow. If the server cannot be reached, the request is blocked, never sent unchecked. In an
  **On-Device** organisation the check runs on the computer with ZeusLock Ama, and only the
  incidents reach the dashboard.
- **Pointing a computer at another organisation:** change `LicenseKey` (and `ServerUrl` if
  needed) where you set it, quit the agent, delete the agent's cached registration
  (`config.json` in its data folder: Windows `%APPDATA%\ZeusLock DLP Agent\`, macOS
  `~/Library/Application Support/ZeusLock DLP Agent/`, Linux `~/.config/ZeusLock DLP Agent/`),
  then start it again.
