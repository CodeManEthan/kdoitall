# Modifying Database Schema (Tables or Columns)

This checklist covers adding new tables, adding columns to existing tables, or modifying column definitions in the SQLite database.

## 1. Schema Definition

- [ ] Edit `database/schema.sql` with the new table or column
- [ ] For new tables: define PRIMARY KEY, FOREIGN KEYs, NOT NULL constraints, DEFAULT values
- [ ] For new columns: decide on type (TEXT, INTEGER, REAL, BOOLEAN as TEXT), nullability, default value
- [ ] Add appropriate indexes for columns used in WHERE clauses or JOINs
- [ ] Consider FK cascade behavior (ON DELETE CASCADE for dependent data)
- [ ] Verify PRAGMA foreign_keys = ON is already set in schema

## 2. Migration Strategy

- [ ] SQLite has limited ALTER TABLE support -- only ADD COLUMN is straightforward
- [ ] For column additions: prepare ALTER TABLE statement
- [ ] For table restructuring: plan CREATE new -> copy data -> DROP old -> RENAME new approach
- [ ] Add migration to initialization flow (or document manual migration for existing users)

## 3. Database Query Functions

- [ ] Create or update query functions in the appropriate `lib/db/<module>.sh` file:
  - `lib/db/app.sh` for `applications` table
  - `lib/db/workspace.sh` for `workspace_definitions` table
  - `lib/db/window-tracking.sh` for `app_windows` table (writes)
  - `lib/db/window-info.sh` for `app_windows` table (reads)
  - `lib/db/window-definitions.sh` for `window_definitions` table
  - `lib/db/launch-options.sh` for `launch_options` / `launch_parameters` tables
  - `lib/db/screen.sh` for `screen_aliases` table
  - `lib/db/app-registry.sh` for `app_registry` table (separate DB)
- [ ] Use parameterized queries with `:param value` pairs (never interpolate user input)
- [ ] Follow existing function naming: `db_get_<thing>()`, `db_set_<thing>()`, `db_add_<thing>()`, `db_delete_<thing>()`
- [ ] Check DB_STATUS after queries; set appropriate error codes on failure
- [ ] Use `normalize_boolean()` for boolean fields

## 4. Update Callers

- [ ] Search for all functions that read from the modified table -- verify SELECT columns still valid
- [ ] Search for all functions that write to the modified table -- add new column to INSERT/UPDATE
- [ ] If column is non-nullable without default: update all INSERT statements to include the column
- [ ] If adding to pipe-delimited result parsing (DB_RESULT[]), update all consumers that split on "|"

## 5. Update Display Functions (if user-visible)

- [ ] Update `lib/utils/display.sh` if the new data appears in info/list/status output
- [ ] Update `lib/commands/workspace/export.sh` if it should appear in JSON export
- [ ] Update `lib/commands/workspace/import.sh` if it should be importable
- [ ] Update `lib/commands/app/info.sh` if it's application metadata

## 6. Update App Registry (if applications table)

- [ ] If adding to `applications` table: update `db_upsert_application_scan()` in `lib/db/app.sh`
- [ ] Update `db_add_application()` and `db_add_application_full()` signatures
- [ ] Consider whether `app scan` should populate the new field or if safe-mode should
- [ ] If pre-known values exist: update `database/app-registry.sql` seed data
- [ ] Update `app_registry_get_metadata()` in `lib/db/app-registry.sh` if field comes from registry

## 7. Update Safe Mode (if applications table metadata)

- [ ] If the new field is runtime-detected: add detection logic to `lib/app/safe-mode.sh`
- [ ] Update `db_set_safe_mode_results()` in `lib/db/app.sh` to include the new field
- [ ] Update `safe_mode_display_summary_and_confirm()` to show the value
- [ ] Update `db_clear_safe_mode_data()` to reset the new field
- [ ] Update SAFE_MODE_STRICTNESS logic in `db_get_apps_needing_safe_mode()` if field affects validation

## 8. Update Workspace Script Generation (if window_definitions table)

- [ ] Update `generate_workspace_script()` in `lib/workspace/generator.sh`
- [ ] Update WORKSPACE_APPS array format (pipe-delimited: app_id|window_name|launch_function|desktop|screen|position|parameters)
- [ ] Update `store_window_definitions()` to persist the new field
- [ ] Update workspace create/edit/import to collect the new field from user input

## 9. Update Core Engine (if affects launch pipeline)

- [ ] Update `execute_launch_window()` parameter list in `lib/core/core.sh` (currently 15 params)
- [ ] Update `launch_by_app_id()` if the field comes from `db_get_app_launch_properties()`
- [ ] Update `gather_post_launch_metadata()` if the field is auto-detected at launch

## 10. Python DB Server (if query format changes)

- [ ] The Python coproc in `db-server.py` handles query execution -- it is query-agnostic
- [ ] No changes needed unless you modify the communication protocol (pipe-delimited results)

## 11. Test

- [ ] Run `./scripts/show-database-schema.sh` to verify schema
- [ ] Run `kdoitall app scan` to verify scan still works
- [ ] Create and open a test workspace to verify launch pipeline
- [ ] Run `kdoitall --verbose workspace open <test>` to check for query errors
- [ ] Test export/import round-trip if applicable

## 12. Update Documentation

- [ ] Update `docs/modules/database.md` -- add new column/table to schema section
- [ ] Update the relevant module doc's Function Impact Map if new query functions added
- [ ] Update any flow docs affected by the schema change
