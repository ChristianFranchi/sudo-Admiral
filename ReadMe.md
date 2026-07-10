# sudo-Admiral

**A menu-bar "lock" for passwordless `sudo` across your whole fleet — that re-locks itself after N minutes of inactivity, like a screensaver.**

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-black) ![license](https://img.shields.io/badge/license-MIT-blue) ![status](https://img.shields.io/badge/FOSS-100%25-green)

sudo-Admiral turns passwordless `sudo` into a **deliberate, time-boxed, fleet-wide switch** with a menu-bar app:

- 🔓 **Open** the lock (with **Touch ID**) → passwordless `sudo` is enabled on your Mac **and** on every device in your fleet, at once.
- ⏳ **Idle auto-relock** → each device closes its own lock after **N minutes of inactivity** (configurable), so an unused machine secures itself.
- 🔒 **Close** any time from the menu bar.
- 🖥️ **One controller drives them all** over SSH (works great over [Tailscale](https://tailscale.com)).

It is built entirely from FOSS / built-in pieces: `sudo` · `ioreg` (idle) · `launchd` · SSH · [SwiftBar](https://github.com/swiftbar/SwiftBar).

---

## ⚠️ Security — read this first

sudo-Admiral **intentionally lowers a security boundary**: while the lock is *open*, `sudo` needs no password. That is a real reduction. It is designed to be acceptable only because:

- it is **opt-in** and **off by default** (the lock starts closed);
- opening it is a **deliberate act** gated by **Touch ID** on the controller;
- every device **auto-relocks on inactivity** (the core mitigation — an idle machine does not stay open);
- every write to `/etc/sudoers.d/` is **validated with `visudo` before install**, so a bad rule can never lock you out.

There is an **optional "trusted-controller" mode** that lets the controller open *remote* devices with no prompt (frictionless fleet). This is **more convenient and less safe**: anyone who can `ssh` as your user (or run code locally on a remote) can open root there. Enable it only on trusted machines/networks. **Use at your own risk.**

---

## How it works

| Piece | Role |
|---|---|
| `fleet-lock-apply` | root helper: creates/removes `/etc/sudoers.d/fleet-nopasswd` (the "lock"), validated with `visudo`. Invoked only via a narrow sudoers rule. |
| `fleet-lock-agent` | per-device LaunchAgent: reads idle time from `ioreg` (`HIDIdleTime`) and **re-locks after N minutes of inactivity**. Headless devices are time-boxed from the moment they were opened. |
| `fleet-lock` | controller CLI on your main machine: `open` / `close` / `set N` / `status`, fanned out to the fleet over SSH. |
| `sudo-Admiral.30s.sh` | SwiftBar menu-bar app: the lock toggle, per-device status, an N selector, and a language menu. |

The "lock" is just a file (`/etc/sudoers.d/fleet-nopasswd` = `NOPASSWD: ALL`). "Idle re-lock" removes it; `timestamp_timeout` is also set as defense-in-depth.

---

## Requirements

- **macOS 14+** (Apple Silicon or Intel).
- [**SwiftBar**](https://github.com/swiftbar/SwiftBar) for the menu-bar app: `brew install --cask swiftbar`.
- **Key-based SSH** to each fleet device (a [Tailscale](https://tailscale.com) tailnet is the easy way).
- Touch ID for a passwordless *open* on the controller (optional; falls back to password).

---

## Install

Get the code:

```bash
git clone https://github.com/ChristianFranchi/sudo-Admiral
cd sudo-Admiral
```

### On every fleet device (the "client")

Run once, as an administrator (this is the single authenticated step per device):

```bash
sudo ./install-client.sh <username> <trust>
```

- `<username>` — the local user to grant when the lock is open.
- `<trust>` — `0` = opening requires auth on this device (secure); `1` = "trusted-controller", the controller can open this device with no prompt (frictionless — see Security).

It installs the root helper, the idle agent (LaunchAgent), a `visudo`-validated sudoers rule, and sets a default of **10 min**.

### On the controller (your main Mac, the "server")

```bash
./install-controller.sh
```

Installs the `fleet-lock` CLI + `sudo-Admiral` menu-bar app, and creates empty inventory files.

> To lock/unlock the **controller's own Mac**, run `install-client.sh` on it too (it is a device like any other). Otherwise the controller only drives the remote hosts.

### (Optional) Touch ID for `sudo`

To open the local lock with Touch ID instead of a typed password:

```bash
printf 'auth       sufficient     pam_tid.so\n' | sudo tee /etc/pam.d/sudo_local
```

---

## Configure the fleet

Edit `~/.config/fleet-lock/hosts` — one **SSH alias** per line (as in your `~/.ssh/config`):

```
host1
host2
```

Windows devices (managed remotely only — no lock, see below) go in `~/.config/fleet-lock/windows-hosts` as `alias|jump`:

```
winbox|host1
```

---

## Use

From the menu bar:

- **Unlock / Lock fleet** — one click toggles the whole fleet (Touch ID to open).
- **Preferences → Idle timeout** — choose N (1 / 5 / 10 / 15 / 30 / 60 min).
- **Preferences → Language** — Italiano · English · Español · Français · Deutsch · 中文.
- The device list shows each member's state (unlocked / locked / manageable / unreachable).

Or from the CLI:

```bash
fleet-lock open      # Touch ID, opens the fleet
fleet-lock close
fleet-lock set 15
fleet-lock status
```

---

## Windows?

Windows has no `sudo`/sudoers, so there is **no lock** there. A Windows host reachable over SSH is shown as **"manageable"** (you administer it remotely from the controller, where elevation is already handled). Lowering Windows UAC to mimic the behavior is intentionally **not** done by this project.

---

## Uninstall

```bash
./uninstall.sh          # controller + app (user), then client (asks for sudo)
```

---

## License

[MIT](LICENSE) © Christian Franchi Viceré. Contributions welcome.

> Disclaimer: this software changes system security settings (`sudoers`, PAM). Review the code, understand the trade-offs in the Security section, and run it only where you accept the risk. No warranty.
