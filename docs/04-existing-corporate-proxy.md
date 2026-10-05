# Existing corporate proxy

*Agent 1.0.18 and later.*

If your organisation already sends web traffic through a forward proxy (Squid, Blue Coat,
Forcepoint, Skyhigh, a cloud gateway reached by a proxy setting or PAC file), the ZeusLock
agent works alongside it. This page explains what the agent does, what it needs from your
network, and the settings that control it.

## How the two fit together

```
application ──► ZeusLock agent (127.0.0.1:9876) ──► your proxy ──► internet
                detects and anonymises               keeps control of egress
```

The agent takes the machine's proxy setting, as before, and then sends **its own outbound
traffic through your proxy** instead of connecting directly. In a network where only the
proxy may reach the internet, this is what lets the agent, and everything behind it, keep
working.

- **Your proxy stays in charge of egress.** Filtering, logging and access rules apply as
  they did.
- **Your proxy sees AI prompts after ZeusLock has anonymised them.** The agent is first in
  the chain. One exception to plan for: see *Exempt the ZeusLock platform from TLS
  inspection* below.
- **Internal addresses stay direct.** The agent follows your own bypass list or PAC rules,
  so intranet hosts are not sent to the proxy.

## What the agent detects by itself

With the default setting (`UpstreamProxy=auto`) the agent reads the proxy configuration the
machine had before the agent started, and follows it:

| Your configuration | What the agent does |
|---|---|
| Static proxy (`host:port`) with a bypass list | Sends outbound traffic to that proxy; bypass entries go direct |
| PAC file (`AutoConfigURL`, WPAD-style script) | Evaluates your PAC for each destination and follows its answer |
| No proxy | Connects directly, as in earlier versions |

It covers every outbound path: pass-through connections, inspected AI requests, WebSocket
connections, and the agent's own calls to the ZeusLock platform (license, policy, incidents).

**When Group Policy or MDM re-applies your proxy settings**, the agent notices within a
minute, adopts any change to your proxy configuration, and points the machine back at
itself so protection continues. Where policy enforces the setting outright (for example a
per-machine proxy policy), the agent cannot take it; see *ManageSystemProxy* below.

## TLS inspection

If your proxy decrypts and re-signs HTTPS, the agent must trust your certificate authority.
It does so by default: the agent trusts the **operating system's certificate store**, the
same store browsers use. If your CA is deployed to your machines (Group Policy, MDM,
`update-ca-certificates`), nothing more is needed.

If you would rather hand the agent a specific bundle, set `ExtraCaFile` to a PEM file.

### Exempt the ZeusLock platform from TLS inspection

To decide what to anonymise, the agent sends the text of a prompt to the ZeusLock platform
(your `ServerUrl`) for analysis. That call goes through your proxy like everything else. If
your proxy decrypts it, **the original, un-anonymised text is readable on the proxy and in
its logs**, even though the copy that later reaches the AI provider is anonymised.

Add your `ServerUrl` host to the proxy's do-not-inspect list (ZIA "Do Not Inspect",
Netskope do-not-decrypt, Squid `ssl_bump splice`, FortiGate `ssl-exempt`, Palo Alto
decryption exclusion). This is the same exemption security-agent vendors require for their
own traffic.

## Settings

All four are optional. Set them like any other key (see the
[configuration reference](configuration-reference.md)).

| Key | Default | Meaning |
|---|---|---|
| `UpstreamProxy` | `auto` | `auto`: follow the machine's own proxy configuration. `off`: always connect directly. `http://host:port` or `http://user:password@host:port`: always use this proxy. |
| `TrustSystemCa` | `true` | Trust the OS certificate store for the agent's outbound TLS. |
| `ExtraCaFile` | — | Path to a PEM bundle of additional CAs to trust. |
| `ManageSystemProxy` | `true` | `false`: the agent never changes system proxy settings. Your own PAC must send AI traffic to `127.0.0.1:9876`. |

### Proxy authentication

Basic authentication is supported: put the credentials in `UpstreamProxy`
(`http://user:password@proxy.corp:3128`), in the managed policy scope so that users cannot
read them. **NTLM and Kerberos proxy authentication are not supported.** If your proxy
requires them, allow the agent's traffic without authentication (by source address or
machine group), which is the same exemption proxy vendors ask for their own agents.

### ManageSystemProxy=false

Use this where your own policy must remain the only owner of the proxy setting (a
per-machine proxy policy on Windows, or an MDM proxy payload on macOS, which allows only
one). The agent then leaves the settings alone, and you add one rule to your PAC file so
that AI traffic reaches the agent:

```javascript
// at the top of FindProxyForURL — send AI services to the ZeusLock agent first,
// falling back to your proxy if the agent is not running
if (dnsDomainIs(host, "chatgpt.com") || dnsDomainIs(host, "claude.ai") /* … */)
    return "PROXY 127.0.0.1:9876; PROXY proxy.corp:3128";
```

Set `UpstreamProxy` to your proxy explicitly in this mode, so the agent's outbound leg does
not depend on reading the setting.

## What to ask your network team

1. **Allow the agent's platform traffic** (your ZeusLock `ServerUrl` host on 443) **and
   exempt it from TLS inspection**, so prompt text sent for analysis is not readable on the
   proxy.
2. **Either** deploy your inspection CA to the OS store (usual case, nothing else to do),
   **or** exempt the AI provider hosts from TLS inspection. ZeusLock already inspects those
   flows before they leave the machine.
3. **If the proxy requires NTLM/Kerberos**, exempt the agent's traffic from authentication.

## Verify

In the agent log (`logs/agent.log` in the agent's data directory) at start-up:

```
[Upstream] System proxy at start: foreign
[Upstream] Trusted CAs: 58 from the OS store, 0 from ExtraCaFile
[Upstream] Outbound route: PAC http://proxy.corp/corp.pac (system)
```

`foreign` means a proxy that is not the agent was found, which is your proxy. On your proxy,
requests from the machine continue to appear while the agent runs. If the route shows
`direct (no corporate proxy detected)` on a machine that has a proxy, set `UpstreamProxy`
explicitly.

| Symptom | Likely cause | Fix |
|---|---|---|
| Nothing loads while the agent runs; log shows `ETIMEDOUT` | Agent is going direct in a proxy-only network | Check the `Outbound route` line; set `UpstreamProxy` |
| Log shows `requires authentication (407)` | Proxy wants credentials | Add Basic credentials to `UpstreamProxy`, or exempt the agent |
| Log shows `unable to verify` / `self-signed certificate in certificate chain` | Inspection CA is not in the OS store | Deploy the CA, or set `ExtraCaFile` |
| Log repeats `settings are enforced by policy` | A policy owns the proxy setting | Use `ManageSystemProxy=false` and the PAC rule above |
