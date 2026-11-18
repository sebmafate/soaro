# 0010. Docker: a targeted prune through the docker command, measured by the space returned to the Mac

| | |
| --- | --- |
| Status | accepted on 2026-11-18 (Test B passed: [SPK-002](../spikes/SPK-002-docker-test-b.md), 89.7 % of the announced space came back after `docker builder prune -a -f`) |
| Date | 2026-11-15 |
| Supersedes | none. Applies the contract of [0009](0009-cleanup-actions-by-supported-route-under-one-contract.md) to Docker |
| Drives from | R10, R11, R9; kill criterion 1; drivers: safety of deletion, privacy, honesty about fragile data |

## Context

On the author's Mac (read-only inspection, 2026-11-15):

- Docker Desktop stores everything in one sparse file, `Docker.raw`: apparent size 995 GB, 24 GB really allocated. Soaro must only ever use the allocated size.
- The engine was stopped (no socket in `~/.docker/run`). Soaro never starts or stops an engine (non-goal of the spec).
- `~/Library/Group Containers/group.com.docker` is protected by macOS ("Operation not permitted"), and reading another app's `Containers` folder would likely trigger a permission prompt. Soaro should not read Docker's own files.
- The `docker` command is at `/usr/local/bin/docker`, a link to `/Applications/Docker.app/Contents/Resources/bin/docker`. OrbStack is not installed, so it cannot be tested (R15).
- Docker's documented way to give space back to the host is a privileged container, `docker/desktop-reclaim-space`, which pulls an image from Docker Hub when it is not present. Started by Soaro, that would be a network call and a privileged action, against R9 and ADR 0007.
- Pruning inside the virtual machine frees space in the VM first. Whether the host gets it back depends on the disk format and the Docker Desktop version (see the sources in `SPEC.md`, "Prior art" and the Docker Desktop FAQ). Not yet measured on this Mac.

## Options considered

### Option A: no Docker support

- For: no risk, no work; matches kill criterion 1 if the test fails.
- Against: Docker is 24 GB on the author's Mac.

### Option B: report only

- For: nothing is deleted; shows what is big.
- Against: the author already has the commands (`docker system df`). It adds little over doing it by hand.

### Option C: targeted prune, measured by the space returned (proposed)

- For: real value if space comes back; stays inside the ADR 0009 contract; no network call by Soaro.
- Against: the benefit is unproven until the test; images pulled once may need downloading again; OrbStack is not verifiable here.

## Decision

**Option C**, with these rules (accepted on 2026-11-18 after Test B passed):

1. **Through the `docker` command only**, found from a list of candidate paths (Docker Desktop's, Homebrew's, OrbStack's), under the ADR 0009 contract (runner with time limit, confirmation, rescan). No reading of Docker's own folders.
2. **Engine stopped or unreachable:** the section says so, or hides itself. Soaro never starts or stops it.
3. **What is cleaned:** the build cache and untagged ("dangling") images, pre-selected. Other unused images are listed but not pre-selected, because deleting them means downloading them again later.
4. **Never:** volumes, containers, anything a running container uses, the reclaim container, or Docker's disk image file.
5. **Honest result (R11):** after the prune, the app reports the space really returned to the Mac (free space before and after), and says so plainly when the disk image did not shrink.

## Consequences

- Good: a safe, small Docker feature that never needs the network.
- Bad: if the host space does not come back, the feature is dropped (kill criterion 1) and part of this work is wasted.
- Risks and how we will notice them: a Docker Desktop update changes how space is returned; the measured result in R11 shows it to the user.

## Revisit when

- Test B returns less than half of the announced space: set the status to `deprecated` and drop R10 and R11.
- Someone provides an OrbStack Mac to test (R15).

## Open points

- **Test B done on 2026-11-18** ([SPK-002](../spikes/SPK-002-docker-test-b.md): 22.46 GB announced, 89.7 % back on the Mac after 10 minutes, no volume touched; the untagged-image part could not be measured, there were none). It was to run with Docker Desktop started by the author, measure `df`, the allocated size of `Docker.raw` and `docker system df` before and after `docker builder prune` and an untagged-image prune, with no volumes and no reclaim container. Criterion: at least half comes back. Soaro runs nothing destructive on the author's Docker without his confirmation at that moment.
- The exact commands and flags to list and prune are chosen at implementation, after the test.
