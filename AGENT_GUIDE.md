# DIY_nas Agent Guide

Use this file when another coding agent needs to continue the DIY_nas project.

## Project Goal

DIY_nas is a public, sanitized template for building a NAS-style web drive on a Windows PC while keeping Windows as the main host OS. The reference architecture uses Hyper-V, Ubuntu Server, ZFS, Docker, FileBrowser Quantum, and optional API/tunnel components.

## Current Architecture

```text
Windows host
  -> Hyper-V Ubuntu Server VM
  -> physical HDD pass-through
  -> ZFS live mirror for active drive data
  -> FileBrowser Quantum for browser-based file management
  -> optional Node Gateway for integrations
  -> optional Cloudflare Tunnel for public HTTPS access
```

## Operating Assumptions

- Windows stays installed on the SSD.
- The Ubuntu VM is the Linux NAS runtime.
- Only the intended NAS data directory should be exposed to FileBrowser Quantum.
- FileBrowser Quantum is the primary human-facing drive UI.
- The Node Gateway is optional and exists for service/API integrations.
- Public HTTPS exposure should go through an explicit tunnel or reverse proxy configuration.

## Safety Rules

- Never run destructive disk operations without explicit user confirmation and disk identity checks.
- Never commit `.env`, app passwords, Cloudflare tunnel tokens, real domain names, real IP addresses, disk serials, logs, or backup archives.
- Never expose `/`, `/var`, Docker volumes, or full home directories through the web drive.
- Prefer placeholders such as `drive.example.com`, `REPLACE_WITH_TOKEN`, and `REPLACE_WITH_SHARE_HASH` in public files.
- Keep scripts dry-run by default when they touch disks or published network routes.

## Expected Verification

Run these before claiming the public template is ready:

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

If a change touches shell scripts, also review them manually for quoting, destructive flags, and hardcoded environment-specific values.

## Documentation Policy

- `README.md` is the default English GitHub landing page.
- `README.ko.md` is the Korean translation.
- Keep implementation details in `docs/`.
- Keep operator-specific deployment notes out of Git unless fully sanitized.
