# SPK-002: Docker Test B, does a build-cache prune give space back to the Mac?

| | |
| --- | --- |
| Status | running |
| Date | 2026-11-18 |
| Time box | 1 hour (agent run on the author's Mac; each prune confirmed by the author at that moment) |
| Serves | R10, R11, `SPEC.md` assumption A2 and kill criterion 1, ADR 0010 (proposed), `PLAN.md` SP1, risk 7 |
| Verdict | (to fill when done) |

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

(to fill)

## Verdict

(to fill)

## Consequences

- ADR: (to fill)
- Architecture: risk 7 and risk 2 in `ARCHITECTURE.md` (to fill)
- Spec or kill criteria: (to fill)
- Plan: SP1, SL13, SL14 (to fill)
