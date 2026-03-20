## Shell Coding Standards

- All scripts use `set -euo pipefail`
- Use source guards: `check_and_set_guard "_KDOITALL_MODULE_LOADED" || return 0`
- Pass all function parameters explicitly (no globals except constants)
- Use `local -n` for reference parameters
- Quote all variable expansions
- Use `debug_function_enter`/`debug_function_exit` for tracing
- Parameter validation with `ERR_MISSING_PARAMETER` error codes
