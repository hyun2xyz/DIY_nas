# Contributing

## Development Checks

Run these before opening a pull request:

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

## Privacy Rules

This project is designed to be reusable. Do not add personal deployment values to tracked files.

Use sample values:

- `drive.example.com`
- `192.168.100.10`
- `LIVE-DISK-1`
- `BACKUP-DISK-1`

Do not use:

- real domains
- real IP addresses from your deployment
- real disk serial numbers
- real usernames
- real tokens
- real backup paths

## Script Rules

- Prefer dry-run behavior by default.
- Print target disks before destructive operations.
- Keep user-specific values configurable through parameters or environment variables.
- Add tests for parsing, planning, and safety behavior when possible.

## Documentation Rules

- Explain what the script changes.
- Include rollback or recovery notes when relevant.
- Keep public docs free of screenshots containing personal values.
