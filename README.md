# forth6800

Forth for the SWTPC 6800.

## Included kernel

This repository includes `f83_6800.asm`, a compact direct-threaded Forth-83 style interpreter kernel in Motorola 6800 assembly.

It provides:

- an outer interpreter loop (`INTERPRET`) with tokenization and dictionary lookup,
- an inner interpreter (`NEXT`) and threaded execution model,
- colon definitions via `:` and `;`,
- literal compilation (`LIT`) while compiling,
- core words (`DUP DROP SWAP OVER + - AND OR XOR = 0= EMIT KEY CR .`),
- dictionary header/link management,
- line input + number parsing.

## GitHub Codespaces setup (SIMH SWTPC 6800)

This repo now includes a preconfigured Codespaces environment that downloads and compiles the SWTPC 6800 simulator from the SIMH project.

### What happens automatically

- `.devcontainer/devcontainer.json` installs build prerequisites (including `libpcre3-dev`, `libedit-dev`, `libpng-dev` for non-interactive SIMH builds).
- `scripts/setup-swtpc-sim.sh` clones SIMH into `.tools/simh` (if not present).
- The script builds the SIMH SWTPC target (defaults to `swtp6800mp-a`, configurable via `SIMH_TARGET`) and exposes the resulting binary at `.tools/bin/swtp6800`.
- PATH in the container is updated so `swtp6800` is directly runnable.

### Run manually (inside Codespaces)

```bash
bash scripts/setup-swtpc-sim.sh
swtp6800 -V
```


## CI build for simulator

A GitHub Actions workflow at `.github/workflows/build-swtpc6800.yml` now downloads and compiles the SIMH SWTPC simulator on every push and pull request, then uploads the built binary as a workflow artifact.

## Target

- SWTPC 6800 with SWTBUG monitor defaults.
- Intended to be loaded for use under SIMH SWTPC emulation.

## Notes

- ROM I/O entry points are currently set to `MON_INCH = $E1AC` and `MON_OUTCH = $E1D1` (common SWTBUG defaults).
- Memory map constants near the top of `f83_6800.asm` should be adjusted for your specific machine/SIMH configuration.
- This is a bootstrap-grade F83-like kernel rather than a complete, production F83 environment.

## CORES assembler smoke test in CI

A second CI workflow (`.github/workflows/cores-assemble-test.yml`) now:

1. builds the SIMH SWTPC 6800 simulator,
2. uses the checked-in SWTPC CORES S19 (`third_party/cores/swtpc_cores_1_01.s19`),
3. runs `simh/cores.ini` to load CORES and set `PC` for execution, and
4. verifies the simulator returns to `sim>` after running the script in CI.

### Manual CORES load in Codespaces

```bash
swtp6800 simh/cores.ini
# at sim>
go
```
