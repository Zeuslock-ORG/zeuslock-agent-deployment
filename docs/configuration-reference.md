# Configuration Reference

The single source of truth for **how the ZeusLock agent is configured**. Every
platform guide points here for the exact keys and values. Read the two rules
below and you can configure the agent on any OS.

---

## Rule 1 — where the agent reads configuration (and in what order)

On startup (and every ~60 s), the agent loads configuration from these sources,
**highest priority first**:

1. **Managed policy scope** (GPO / MDM / managed conf) — the enterprise source.
   - Windows: Registry key `HKLM\SOFTWARE\Policies\ZeusLock`
   - macOS: managed-preferences domain `com.zeuslock.agent`
     (`/Library/Managed Preferences/com.zeuslock.agent.plist`)
   - Linux: `/etc/zeuslock/agent.conf`
2. **Admin config file** (system-wide JSON) — used when the managed scope did not
   supply a license key:
   - Windows: `C:\ProgramData\ZeusDLP\config.json`
   - macOS: `/Library/Application Support/ZeusDLP/config.json`
   - Linux: `/etc/zeus-dlp/config.json`
3. **Per-user config file** (a tester without admin rights):
   `zeus-config.json` in the agent's per-user data directory.

A key set in a higher source wins. In practice you use **either** the managed
policy (recommended for fleets) **or** the admin JSON file (simplest for a pilot /
single machine) — both are fully supported. Using both is fine; the managed
policy takes precedence per-key.

> **Why "managed scope" matters:** the agent only treats the enterprise scope as
> authoritative for keys it *actually read* there. A managed policy that is
> present but supplies no `LicenseKey` correctly **falls through** to the JSON
> file rather than leaving the endpoint unconfigured. This means you can safely
> layer a JSON fallback under an MDM/GPO policy.

---

## Rule 2 — the keys

The two keys that **must** be set to activate an endpoint:

| Key | Value | Example |
|-----|-------|---------|
| `ServerUrl` | Your tenant's API URL | `https://api.zeuslock.ai` |
| `LicenseKey` | Your org API key (from the dashboard) | `zl_xxxxxxxxxxxxxxxxxxxx` |

> **Legacy aliases:** in the **JSON file** sources you may instead use `apiUrl` /
> `apiKey` — they still work but are deprecated; prefer `ServerUrl` / `LicenseKey`
> so the vocabulary matches the GPO/MDM scope. The managed policy scope uses
> `ServerUrl` / `LicenseKey` only.

`OrganizationId` is **not required** — the server resolves your organization from
the license key automatically.

### Optional keys (all have safe defaults)

You normally set only `ServerUrl` + `LicenseKey`. These are available if you want
to override behavior centrally:

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `OrganizationName` | string | — | Cosmetic label shown in logs/UI |
| `AgentEnabled` | bool | `true` | Master on/off switch |
| `BlockingEnabled` | bool | `true` | Enforce blocks (vs. detect-only) |
| `ClipboardMonitoring` | bool | `true` | Monitor clipboard |
| `ScreenshotMonitoring` | bool | `true` | Monitor screenshots |
| `FileMonitoring` | bool | `true` | Monitor file uploads |
| `NetworkMonitoring` | bool | `true` | Monitor network/AI traffic |
| `ShadowAiDiscovery` | bool | `true` | Discover unsanctioned AI tools |
| `AutoUpdate` | bool | `true` | Allow agent self-update |
| `LogLevel` | string | `info` | `error` \| `warn` \| `info` \| `debug` |
| `HeartbeatInterval` | number (ms) | `300000` | Check-in interval (5 min) |
| `RulesSyncInterval` | number (ms) | `3600000` | Policy refresh (1 hr) |

> The **DLP policy itself** (which data types block vs. alert) is **not** set on
> the endpoint — it lives in your dashboard and is fetched from the server using
> the license key, then refreshed on `RulesSyncInterval`. Change a rule in the
> dashboard and every agent picks it up automatically.

---

## Value formats per source

The **key names are identical everywhere**; only the *encoding* differs by source.

### Windows registry (`HKLM\SOFTWARE\Policies\ZeusLock`)
- String keys → `REG_SZ`
- Boolean/number keys → `REG_DWORD` (booleans: `1` = true, `0` = false)

```
ServerUrl        REG_SZ     https://api.zeuslock.ai
LicenseKey       REG_SZ     zl_xxxxxxxxxxxxxxxxxxxx
AgentEnabled     REG_DWORD  0x1
BlockingEnabled  REG_DWORD  0x1
```

### macOS managed preferences (domain `com.zeuslock.agent`)
Delivered as an MDM configuration profile (a `.mobileconfig`) whose payload sets
the domain's keys. Booleans are real `<true/>`/`<false/>`; the agent also accepts
`1`/`0`. See [scripts/macos/com.zeuslock.agent.mobileconfig](../scripts/macos/com.zeuslock.agent.mobileconfig).

### Linux conf (`/etc/zeuslock/agent.conf`)
`KEY=VALUE`, one per line. `#` and `;` start comments. Quotes are optional.

```ini
ServerUrl=https://api.zeuslock.ai
LicenseKey=zl_xxxxxxxxxxxxxxxxxxxx
BlockingEnabled=true
```

### JSON file (all platforms — the fallback sources)
UTF-8, **no BOM** (a byte-order mark crashes the parser).

```json
{
  "ServerUrl": "https://api.zeuslock.ai",
  "LicenseKey": "zl_xxxxxxxxxxxxxxxxxxxx"
}
```

---

## The installer is generic (why Step 3 exists)

The installer downloaded from the dashboard is the **same file for every
customer** and contains **no credentials**. This is by design — it means you can
cache/redistribute one installer and bind machines to your org purely through
policy. It also means **an install alone does nothing** until `ServerUrl` +
`LicenseKey` are delivered by one of the sources above.

On Windows the installer is a **per-user** package; to deploy it machine-wide via
GPO you force a per-machine install (`ALLUSERS=1 MSIINSTALLPERUSER=""`) — the
[Windows guide](01-windows-gpo.md) does this for you. macOS `.pkg` and Linux
`.deb`/`.rpm` install system-wide normally.

---

## Runtime facts every admin should know

- **The agent runs in the user's interactive session.** It is a tray application
  that also sets a local inspection proxy (listening on `127.0.0.1:9876`). It must
  run while a user is **logged in** — it cannot protect a machine with no
  interactive session (e.g. a locked/logged-out server).
- **First run registers the endpoint** with the server using the license key; the
  machine then appears under **Agents** in your dashboard.
- **Policy is enforced server-side.** The agent forwards inspected content to the
  server, which applies your organization's policy and returns block/alert/allow.
- **Changing the bound org:** if you re-point an already-registered endpoint at a
  different org/key, clear the agent's per-user store so it re-registers cleanly
  (the platform guides show the exact path).
