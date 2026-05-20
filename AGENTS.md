# AGENTS.md

This repository is a public template for a Windows + Hyper-V + Ubuntu + ZFS + Docker self-hosted NAS drive pipeline.

## Operating Rules

- Treat this repository as public. Do not add real domains, emails, passwords, tokens, disk serials, internal IPs, backup archives, databases, or logs.
- Prefer placeholders such as `example.com`, `user@example.com`, `<API_TOKEN>`, `<APP_PASSWORD>`, `<DISK_SERIAL>`, and `192.168.100.10`.
- Keep scripts conservative. Disk-destroying actions must require explicit flags and must print the target disks before doing anything.
- Do not expose `/`, `/var`, Docker root volumes, or a full user home directory through FileBrowser. Expose only a dedicated NAS mountpoint.
- Preserve the split between user-facing drive UI and integration/API layer.

## Architecture Boundary

- User-facing drive UI: FileBrowser Quantum.
- Integration/API layer: optional Node Gateway.
- Storage: ZFS live mirror for active data, separate backup target for recovery.
- Public HTTPS: Cloudflare Tunnel or another explicitly configured reverse proxy.

## Verification

Run these before claiming the repository is ready:

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

If a change touches shell scripts, inspect the destructive path manually.

## Documentation Standard

- Keep README short and installation-focused.
- Put explanations in `docs/`.
- Update `agent.md` when architecture or operational decisions change.
- Add recovery notes when changing storage, backup, or tunnel behavior.

## Release Standard

- Public release contents should be generated from git-tracked and non-ignored files only.
- Ignored local files are private by default.
- Do not commit generated runtime data.
