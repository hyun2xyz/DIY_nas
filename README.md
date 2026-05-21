# DIY_nas

DIY_nas is a sanitized open-source template for building a self-hosted NAS-style web drive on a Windows PC without replacing Windows.

Korean documentation: [README.ko.md](README.ko.md)

## What This Project Builds

```text
Windows host
  - Keeps the existing Windows installation on SSD
  - Runs an Ubuntu Server VM through Hyper-V
  - Passes selected HDDs through to the VM

Ubuntu VM
  - Uses a ZFS mirror for live drive storage
  - Runs Docker Engine
  - Runs FileBrowser Quantum for the human web drive UI
  - Optionally runs a Node Gateway for service-to-service file APIs

Optional public access
  - Cloudflare Tunnel publishes selected local services over HTTPS
```

The project is intended for home labs, small internal teams, and learning-oriented NAS deployments. It is not a turnkey appliance. Disk selection, backup policy, network exposure, and authentication must be reviewed for each machine before use.

## Included

- Windows and Hyper-V oriented setup notes
- Ubuntu Server and Docker based NAS service layout
- ZFS mirror setup scripts with explicit destructive flags
- FileBrowser Quantum Docker configuration
- Optional Node Gateway API examples
- Optional Cloudflare Tunnel helper scripts
- Public-release audit tooling for secrets and private environment markers
- Agent handoff documentation in [AGENT_GUIDE.md](AGENT_GUIDE.md)

## Quick Start

```powershell
git clone https://github.com/hyun2xyz/DIY_nas.git
cd DIY_nas
npm install
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

Use `npm.cmd` on Windows PowerShell if the plain `npm` command is blocked by execution policy.

## Core Layout

```text
scripts/
  linux/       Ubuntu-side setup scripts
  vm/          Hyper-V helper scripts
  gateway/     Optional API gateway and WebDAV helper scripts
  cloudflare/  Optional tunnel helper scripts
  audit/       Public release checks

src/
  Minimal Node examples for the optional gateway/API layer

docs/
  Architecture, installation sources, safety notes, and release checklist
```

## Safety Rules

- Do not expose `/`, `/var`, Docker volumes, or a whole home directory through the web drive.
- Mount only the intended NAS data directory, for example `/srv/nas/live/drive`.
- Keep `.env`, app passwords, tunnel tokens, disk serials, real domains, real IP addresses, and backup archives out of Git.
- Run destructive storage scripts only after verifying disk identity and using the explicit confirmation flags.
- Use HTTPS, strong passwords, least-privilege accounts, and separate accounts for automation.

## Verification

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

`audit:public` scans the repository for common private markers before publishing.

## Third-Party Software

This repository does not redistribute third-party binaries. Operators install required software from its official distribution channels, such as Ubuntu apt repositories, Docker's official repository, FileBrowser Quantum container images, and Cloudflare's cloudflared release channel. Review each project's license and terms before production use.

## License

MIT License. See [LICENSE](LICENSE).
