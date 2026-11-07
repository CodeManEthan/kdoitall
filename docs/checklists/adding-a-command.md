# Adding a New CLI Command or Subcommand

This checklist covers adding a new top-level command or a subcommand to an existing command group (workspace, app, window, screen, quick).

## 1. Decide: Top-Level or Subcommand

- [ ] Top-level command: routed directly from `bin/kdoitall` main dispatch (line ~164-222)
- [ ] Subcommand: routed from a dispatcher in `lib/commands/<group>/dispatcher.sh`
- [ ] Decide command aliases (e.g., `list|ls`, `info|i`, `close|c`)

## 2. Create Command Handler File

- [ ] Create `lib/commands/<group>/<command>.sh` (or `lib/commands/<command>.sh` for top-level)
- [ ] Add source guard: `check_and_set_guard "_KDOITALL_<NAME>_COMMAND_LOADED" || return 0`
- [ ] Source required dependencies (colors.sh, relevant db files, etc.)
- [ ] Implement main command function with parameter validation
- [ ] Use `debug_function_enter`/`debug_function_exit` for tracing
- [ ] Output user-facing text to fd 3 (via print_* functions from colors.sh)

## 3. Update Dispatcher

- [ ] For subcommand: Edit `lib/commands/<group>/dispatcher.sh`
  - Add case pattern with aliases (e.g., `list|ls)`)
  - Late-source the handler file: `source "${LIB_DIR}/commands/<group>/<command>.sh"`
  - Call the command function with remaining args
- [ ] For top-level: Edit `bin/kdoitall`
  - Add case pattern in main dispatch block (after line ~164)
  - Source the handler file
  - Call the command function

## 4. Add Help Text

- [ ] For subcommand: Update `<group>_show_help()` in the dispatcher file
  - Add command name, aliases, and one-line description
  - Include usage examples if non-trivial
- [ ] For both: Update `show_help()` in `lib/commands/help.sh`
  - Add to the appropriate section of the help output, as `<group> <subcommand> (<alias>) <args>`
- [ ] Add the command to the README's command lists with the same name and alias
  - `tests/unit/test-readme-help.sh` fails if the README shows a command, alias or flag that `--help` doesn't

## 5. Handle Global Flags

- [ ] Check if the command is informational (read-only, display output)
  - If yes: add to the `is_informational_command` check in `bin/kdoitall` (prevents auto-detach to background)
- [ ] Ensure --verbose and --info flags are filtered in the dispatcher before reaching your handler
- [ ] If command takes flags: parse them from `$@` before processing positional args

## 6. Add Database Support (if needed)

- [ ] Create or update query functions in appropriate `lib/db/<module>.sh` file
- [ ] Use `db_query()` with parameterized queries (`:param value` pairs)
- [ ] Check DB_STATUS after queries; handle DB_ERROR
- [ ] Add any new tables/columns to `database/schema.sql`
  - See `docs/checklists/modifying-database-schema.md`

## 7. Test

- [ ] Test with `--verbose` flag to verify debug tracing
- [ ] Test with missing/invalid arguments
- [ ] Test aliases work correctly
- [ ] Test help text displays properly: `kdoitall <group> --help`
- [ ] Verify auto-detach behavior is correct (informational commands stay in foreground)

## 8. Update Documentation

- [ ] Update `docs/modules/` for any module the command touches
- [ ] If command adds a new workflow, consider adding a `docs/flows/` doc
- [ ] Update this checklist if the command pattern introduces new conventions
