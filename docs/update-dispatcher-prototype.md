# Stable backend dispatcher prototype

Scope: the explicitly opted-in company workstation only. This branch is an isolated prototype, not a deployed update fix. The requested flow is **Codex UI update -> official installation -> official automatic relaunch -> matching new backend and proxy**, without another shortcut click.

## Evidence from the inspected desktop build

The installed desktop's update handler passes its argument list to Electron app.relaunch with the newly registered executable path, filtering only its update-attempt argument. Therefore explicit Chromium proxy arguments are preserved by this handler; it is wrong to assume all proxy arguments are discarded.

Its backend transport resolves CODEX_CLI_PATH and spawns the executable with piped stdin/stdout/stderr, inherited process environment plus logging/runtime variables, and the selected working directory. Its close path kills the spawned process. A shim that only spawns and waits would orphan the real backend when killed.

Neither inspected handler refreshes a version-addressed compatibility path. Environment and package identity across the real installed-version relaunch are an acceptance gate, not a proven promise. Electron main-branch source is reference material, not an exact-version proof of the packaged binary.

## Intended design

1. The selected profile eventually sets CODEX_CLI_PATH to a stable dispatcher executable outside version-addressed caches. No global environment or security settings are changed.
2. On every backend invocation the dispatcher reads its native current MSIX package identity. It must reject missing identity instead of silently selecting the highest installed version.
3. A resolver prepares the backend for that exact registered package. It reuses the signature/hash-checked immutable cache logic with an exact-package constraint. A missing package, signature failure or incomplete helper set fails closed.
4. The dispatcher runs the matching backend with unchanged raw arguments, working directory and standard handles, setting CODEX_APP_RUNTIME_CLI_PATH to the real backend path. No startup diagnostics may appear on stdout.
5. The dispatcher owns a kill-on-close job for its newly created descendants. The backend is created suspended, assigned to the job and only then resumed. Job-assignment failure must not fall back to an unowned live backend. Existing Codex processes are never attached to or killed by this job.
6. The outer MSIX job/identity must survive the nested job. Proxy command-line arguments remain the desktop's responsibility; backend proxy environment must be observed after relaunch.

## Verification gates

- Fixture only: empty/quoted/Unicode arguments; large binary streams; stderr separation; exit codes; parent termination cleanup; nested jobs.
- Package probe: dispatcher and fixture child have the intended MSIX identity inside the launcher's PreventBreakaway job.
- Resolver: exact package selection, unavailable version rejection, source/cache mismatch rejection, no desktop launch.
- Production wiring: opt-in profile validation, no-identity rejection, helper timeout/cleanup, no protocol output contamination.
- Real official UI update: capture before/after package identity, dispatcher and real backend paths/versions, command-line proxy settings and sanitized presence/expected values of necessary environment variables; verify model/tool/remote operation. Never expose credentials.
- No test may force-close active user work. A simulated relaunch is not an actual cross-version update acceptance.

## Rollback and limits

Do not deploy the prototype until the relevant gates pass and the user authorizes the restart window. Preserve the existing profile, launcher and verified package recovery snapshot. Reverting the selected CODEX_CLI_PATH to its previous versioned path removes the dispatcher without uninstalling or weakening any security component.

A stable dispatcher cannot repair an official relaunch that discards the override environment before backend resolution. It also cannot silently ensure gateway startup if that gateway has exited independently. Those are separate boundaries. Polling and killing a newly restarted desktop is not an acceptable substitute for this design.
