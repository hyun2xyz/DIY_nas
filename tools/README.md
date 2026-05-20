# NAS Cloud Tools

These tools are intentionally non-destructive. They do not create pools,
partition disks, format disks, or mount storage.

## Disk Inventory Report

Edit a copy of `samples/disk-inventory.sample.json`, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-NasCloudInventory.ps1 -InputJson .\samples\disk-inventory.sample.json
```

The report includes:

- RAIDZ2 capacity estimate
- per-disk OK/Review/Reject assessment
- Markdown rows that can be copied into `docs/disk-inventory.md`

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\tests\NasCloudTools.Tests.ps1
```

## Host Readiness Report

Use a sample JSON file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-NasCloudHostReadiness.ps1 -InputJson .\samples\host-readiness.sample.json
```

Run a quick local Windows check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-NasCloudHostReadiness.ps1
```

The local check is non-destructive. It reads basic OS and memory information,
then uses conservative defaults for fields that need human confirmation.

## Nextcloud AIO Plan

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-NasCloudNextcloudPlan.ps1 -InputJson .\samples\nextcloud-aio-plan.sample.json
```

The report validates the planned domain, data directory, backup directory,
ports, VPN/public-exposure posture, and optional heavy services. It prints a
Docker command template for review, but does not run Docker or create any
containers.

## SSD Pilot Plan

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-NasCloudSsdPilotPlan.ps1 -InputJson .\samples\ssd-pilot-plan.sample.json
```

This validates a disposable SSD-based pilot plan. It is designed for running an
Ubuntu VM in a window on Windows, learning Nextcloud AIO, and later rebuilding
or restoring onto the real RAIDZ2 server.
