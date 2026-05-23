<p align="center">
  <img src="public/diynas.jpg" alt="DIY_nas line art: a laptop connected to a home server" width="780">
</p>

DIY(Do it your self)_nas is a sanitized open-source template for building a self-hosted NAS web drive on a Windows PC without replacing Windows.

Korean documentation: [README.ko.md](README.ko.md)

## Work Note

Hello, I’m Hyun.

I study editorial design in Korea, and I research different pipelines using AI and share them with others. I love the sharing philosophy of the World Wide Web, HTML, humor, and writing. Beyond HTML, CSS, and JavaScript, it has only been about a month since I started studying development in earnest.

I’d like to introduce my first open-source project, 〈DIY_nas〉.

Since last year, I’ve been consistently running generative AI tutorial workshops for designers and creators. Recently, as I began to feel the importance of “recording” things more strongly, I started building 〈iyo_wiki〉, a wiki engine-based project that could be accessed by more people.

In this space, I wanted to share my work process and thoughts, translate AI-related interviews, host small gatherings and open calls for projects among wiki users, and create a place where each person could build their own wiki page and practice sharing knowledge. I also wanted to build a VOD system for friends who live far away and cannot come to my workshop space in person.

But once these ideas started to move toward actual implementation on the web, there were more limitations than I had expected. Running hosting, cloud services, and databases all on paid plans made the scale grow bigger and bigger, and building a high-spec NAS system from scratch was not exactly cheap either.

As I studied a little about NAS, I learned that I would need hardware capable of running a Linux-based NAS OS. For stable operation, I would need at least a 4-bay system for RAID, and I would also have to buy NAS-grade HDDs separately.

Then one day, I casually thought “Couldn’t I just build this with the powerful desktop that’s been sitting unused in my studio?”
That’s how it lightly began. Inspired by Andrej Karpathy’s idea of vibe coding, I carried out this project without writing a single line of code myself, using only natural language.

I did set one rule for myself: whenever I encountered a word I didn’t know during the process, I wouldn’t just skip over it. I took the time to study and organize the concept and principle behind it. Because I needed to understand what I was actually doing.

Since I had a few other projects running in parallel, the total working time was around ten days. If I had focused on it alone, I think it could have been done even faster.
It is still in beta testing, but I’ve started by using it for wiki hosting, and I’m sharing the pipeline I built on GitHub in a way that is easy to understand.

Feedback and suggestions for the project are always welcome.
Thank you for reading. Please be very, very happy.


## Prerequisites

Use this section as the pre-install checklist. Detailed operating rules for future agents are kept in [AGENT_GUIDE.md](AGENT_GUIDE.md), so this README only lists the baseline requirements.

```text
Required accounts
- GitHub account, if you want to publish or fork this template
- Optional Cloudflare account and domain, if you want a public HTTPS URL
- Optional Tailscale account, if you want private access between your own devices

Required Windows host
- Windows 10/11 Pro, Enterprise, or Education is recommended because Hyper-V is required
- Administrator access to PowerShell and Hyper-V Manager
- Virtualization enabled in BIOS/UEFI
- Wired Ethernet is recommended for stable NAS access

Recommended host specs
- CPU: 4 cores minimum, 8+ cores recommended
- Memory: 16 GB minimum for a pilot, 32 GB+ recommended for heavier use
- SSD free space: 128 GB+ recommended for the Ubuntu VM virtual disk, logs, and tools
- Keep Windows installed on the SSD; do not install the NAS OS directly over Windows

Required storage
- SSD for the Windows host OS and the Ubuntu VM virtual disk
- At least 2 HDDs for a mirrored live NAS pool
- 4 HDDs recommended for live mirror + backup mirror
- NAS-grade HDDs are recommended for live data
- USB/SATA docking station, HBA, or enclosure that exposes each disk individually
- A UPS is strongly recommended if the machine will serve real data

Required software
- Git for Windows
- Node.js LTS and npm
- Ubuntu Server LTS ISO
- Hyper-V
- Docker Engine and Docker Compose plugin inside Ubuntu
- ZFS utilities inside Ubuntu
- FileBrowser Quantum Docker image
- Optional cloudflared for Cloudflare Tunnel
```

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
