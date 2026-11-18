# SPK-002: Docker Test B, does a build-cache prune give space back to the Mac?

| | |
| --- | --- |
| Status | done |
| Date | 2026-11-18 |
| Time box | 1 hour (agent run on the author's Mac; each prune confirmed by the author at that moment) |
| Serves | R10, R11, `SPEC.md` assumption A2 and kill criterion 1, ADR 0010 (proposed), `PLAN.md` SP1, risk 7 |
| Verdict | **confirmed**: 89.7 % of the announced space came back 10 minutes after `docker builder prune -a -f` (94.6 % after 1 minute) |

## Question

After a prune of Docker's build cache on this Mac (Docker Desktop, engine running), does at least half of the space the prune announces come back as free space on the Mac, with no volume touched and without Docker's reclaim container?

## Why it matters

- **Yes (at least half):** ADR 0010 becomes `accepted`, SL13 (the Docker tool) is opened, R10 and R11 stay.
- **No (less than half):** ADR 0010 becomes `deprecated`, R10 and R11 are dropped, SL13 is dropped (kill criterion 1 of the spec). The rest of the project continues.

## Criteria (written before running)

Measures: **announced** = the "Total reclaimed space" printed by the prune command; **returned** = free space of the Mac before minus after, read with `df -k ~` (the data volume); **disk image** = the really allocated size of `Docker.raw` (`ls -ks`), never its apparent size (about 995 GB, sparse); and `docker system df` before and after.

- **Success:** the free space of the Mac has grown by at least 50 % of the announced space, read **10 minutes after the prune** (the first reading right after the prune is also noted, because the virtual machine may give space back with a delay).
- **Failure:** less than 50 % of the announced space is back after 10 minutes.
- **Inconclusive:** the announced space is under 2 GB (too close to the noise of `df`); or the free space drifts by more than 1 GB over a 4-minute baseline taken before the prune with Docker idle, so that the result cannot be told from the drift; or the prune fails or is interrupted. The verdict then says what stays unknown and what to repeat.
- **Conditions:**
  - Docker Desktop 29.7.2 (client and server), started by the author; macOS 27 on Apple silicon; disk image `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`. OrbStack is not installed and cannot be tested (R15).
  - State read before any action (2026-11-18, read-only): `docker system df` says images 2.042 GB (580.7 MB reclaimable), containers 114.7 kB, **local volumes 915.2 MB (23 volumes, 8 active), never touched**, **build cache 22.46 GB, 21.19 GB reclaimable**; 2 containers running (`cocardo-manual-test-web-1` and `-db-1`, which the author uses) and 0 untagged ("dangling") images. `Docker.raw` allocated: 25 239 748 KB (about 24 GiB).
  - Allowed by ADR 0010, and nothing else: a build-cache prune and an untagged-image prune. **Never** `--volumes`, `docker system prune`, `docker rm`, `docker rmi`, `docker run` or Docker's reclaim container (`docker/desktop-reclaim-space`).
  - The untagged-image prune has nothing to remove (0 dangling images): it is **not run**, and the result says so. Unused tagged images (580.7 MB) are not touched either, since ADR 0010 does not pre-select them.
  - Each prune command is run **only after the author confirms it, with its exact text, at that moment**. The default `docker builder prune` removes only dangling build records; `-a` removes all unused build cache. Which of the two is run is the author's choice; the announced space of the command actually run is the denominator.
  - Soaro itself is not involved: the commands are typed by hand (the tool has no Docker code yet). This measures the space returned, not Soaro's behaviour.

## Experiment

A throwaway shell session, nothing committed. In order: (1) a 4-minute baseline of `df -k ~` every 30 s with Docker idle; (2) the full "before" state (`df`, `Docker.raw`, `docker system df`); (3) the prune, confirmed by the author; (4) the "after" state right away, at 5 minutes and at 10 minutes. Observed outputs are copied into "Result".

## Result

Run on 2026-11-18 between 08:42 and 08:59 on the author's Mac. The author confirmed the exact command `docker builder prune -a -f` before it ran (the choice offered was `-a` or the default, which removes only dangling records). Throwaway scripts in the session scratchpad, not committed. Sizes: Docker prints decimal GB; `df -k` values are converted to bytes (x 1024) and compared in decimal GB.

**Baseline** (Docker idle, 9 readings of `df -k ~` every 30 s, 08:42:05 to 08:46:06): free space between 158 993 872 and 159 091 672 KB, a spread of **98 MB**, far under the 1 GB limit; `Docker.raw` steady at 25 240 356 KB. The test is readable.

**Before** (08:47:20): free 159 066 468 KB; `Docker.raw` allocated 25 240 364 KB (24.07 GiB); `docker system df`: images 10 (2.042 GB), containers 11 (2 running), local volumes 23 (915.6 MB), build cache 299 records, 22.46 GB (21.19 GB reclaimable by Docker's own count, 0 active).

**The prune:** `docker builder prune -a -f` took about 43 s (08:47:24 to about 08:48:07) and printed `Total: 22.46GB`. That is the announced space.

| Reading | Free space gained | Share of the announced 22.46 GB | `Docker.raw` allocated |
| --- | --- | --- | --- |
| right after the prune (08:48:07) | 15 984 852 KB = 16.37 GB | **72.9 %** | 9 248 904 KB |
| 1 minute later (08:49:15) | 20 751 320 KB = 21.25 GB | 94.6 % | 4 478 824 KB |
| 5 to 6 minutes (08:52:15 to 08:55:15) | 18.6 to 18.7 GB | about 83 % | 4 478 836 KB |
| **10 minutes (08:58:15)** | **19 677 140 KB = 20.15 GB** | **89.7 %** | 4 478 836 KB |
| 11 minutes (08:59:15) | 19 683 428 KB = 20.16 GB | 89.7 % | 4 478 836 KB |

The disk image itself shrank by 21.26 GB (94.7 % of the announced space) and stayed at 4.27 GiB. The dip in free space at 08:52 and its partial recovery at 08:56 happened while `Docker.raw` did not move, so they come from other activity on the Mac, not from Docker; the 10-minute reading is the one the criteria ask for.

**After** (08:59:16): build cache 0 records, 0 B; images 10 (2.042 GB), containers 11 (2 running, `Up 18 minutes (healthy)`), **local volumes 23, unchanged** (915.6 MB); the two running containers kept running throughout. Nothing else was touched.

**Not run, as planned:** the untagged-image prune, because there were **0 untagged images** to remove; unused tagged images (580.7 MB) and volumes (681.8 MB reclaimable) were left alone; Docker's reclaim container was never started.

Surprises:

- The space came back **without** the reclaim container, and fast: 73 % at once, 95 % after one minute. The disk image shrinks on its own after the prune with this Docker Desktop (29.7.2).
- Docker's `docker system df` counted 21.19 GB reclaimable while the prune with `-a` announced and removed 22.46 GB (the whole cache, including records `system df` did not count as reclaimable).

## Verdict

**Confirmed.** On this Mac, with Docker Desktop 29.7.2, a build-cache prune (`docker builder prune -a -f`) gave back **89.7 %** of the announced space to the Mac 10 minutes later, well above the 50 % threshold, with no volume, container or image touched. The success criterion is met; the failure and inconclusive cases do not apply (announced 22.46 GB, baseline drift 98 MB, the prune succeeded).

What remains unknown:

- Only the **build cache** was measured. The untagged-image prune could not be measured (0 untagged images), so ADR 0010's "untagged images" part rests on the same mechanism but is not shown by this test; R11's honest measurement ("free space after minus before") will report it as it is.
- One Mac, one Docker Desktop version, one run. A different disk format, an older Docker Desktop or an engine under memory pressure may behave differently. OrbStack is untested (R15).
- The default `docker builder prune` (without `-a`) was not run; its announced space is probably much smaller. The choice between the two belongs to SL13.
- The cost to the author is the next build: the whole cache is gone (22.46 GB to rebuild); SL13's confirmation must say so, as for system images.
- The free space moves by about 1 to 2 GB for reasons unrelated to Docker while measuring: R11's "returned" figure should say it is a measurement, not a guarantee.

## Consequences

- ADR: ADR 0010 `proposed` becomes `accepted` (the rule of `PLAN.md` SP1: at least half comes back).
- Architecture: risk 7 closed and risk 2 updated in `ARCHITECTURE.md`; ADR 0010 index status `accepted`.
- Spec or kill criteria: kill criterion 1 (Docker returns less than half) is **not met**; A2 confirmed, R10 and R11 stay.
- Plan: SP1 done; SL13 (Docker) may start, to be detailed with its own decisions (`-a` or not, what the confirmation says); SL14 depends on it.
