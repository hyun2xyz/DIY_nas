# Security Policy

## Scope

This project documents and automates a self-hosted NAS drive pipeline. It may touch disks, authentication tokens, storage credentials, and public tunnel configuration. Treat all local configuration as sensitive.

## Do Not Commit

Never commit:

- real domain names or production URLs
- email addresses or account names
- passwords, app passwords, or API tokens
- Cloudflare Tunnel install tokens
- Tailscale IPs or private network addresses from a real deployment
- physical disk serial numbers from a real machine
- database files, backup archives, logs, or generated data

Use `.env.local`, local JSON files, or OS-level secret storage for real values.

## Public Exposure

If you expose a drive UI or API through Cloudflare Tunnel, reverse proxy, or port forwarding:

- require strong passwords
- separate admin accounts from automation accounts
- require bearer tokens for upload APIs
- decide whether download URLs are public or private
- use HTTPS
- keep software updated
- test backup restore before relying on the system

## Destructive Operations

Disk formatting and pool creation scripts must default to plan/dry-run mode. Any destructive mode should require an explicit confirmation flag and should print the target disks before acting.

## Reporting Issues

For public repositories, use GitHub Security Advisories when available. Do not paste secrets into issues, pull requests, logs, or screenshots.
