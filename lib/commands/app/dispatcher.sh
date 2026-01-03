#!/bin/bash

# ============================================================================
# App Command Dispatcher
# ============================================================================
# Main entry point for app subcommands
# Routes to appropriate app-*.sh command files

check_and_set_guard "_KDOITALL_APP_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# app_command()
# Dispatch app subcommands to appropriate handlers
# Parameters:
#   $1 - subcommand (scan, list, info, validate, options)
#   $@ - additional arguments passed to subcommand
# ----------------------------------------------------------------------------
app_command() {
    local subcommand="$1"
    shift
    
    # Validate subcommand provided
    if [[ -z "$subcommand" ]]; then
        echo "Error: App subcommand required"
        app_show_help
        return 1
    fi
    
    # Source app-registry module before dispatching
    # shellcheck source=../../app/registry.sh
    source "${LIB_DIR}/app/registry.sh"
    
    # Dispatch to appropriate handler
    case "$subcommand" in
        scan)
            # shellcheck source=scan.sh
            source "${LIB_DIR}/commands/app/scan.sh"
            app_scan "$@"
            ;;
        list)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/app/list.sh"
            app_list "$@"
            ;;
        info)
            # shellcheck source=info.sh
            source "${LIB_DIR}/commands/app/info.sh"
            app_info "$@"
            ;;
        validate)
            # shellcheck source=validate.sh
            source "${LIB_DIR}/commands/app/validate.sh"
            app_validate "$@"
            ;;
        options)
            # shellcheck source=options.sh
            source "${LIB_DIR}/commands/app/options.sh"
            app_options "$@"
            ;;
        safe-mode)
            # shellcheck source=safe-mode.sh
            source "${LIB_DIR}/commands/app/safe-mode.sh"
            safe_mode "$@"
            ;;
        *)
            echo "Error: Unknown app subcommand: $subcommand"
            app_show_help
            return 1
            ;;
    esac
}

# ----------------------------------------------------------------------------
# app_show_help()
# Display usage information for app commands
# ----------------------------------------------------------------------------
app_show_help() {
    cat << 'EOF'
Usage: kdoitall app <subcommand> [options]

App Subcommands:
  scan              Scan system for available applications and populate registry
  list [filter]     List applications from registry
                    Filters: all (default), terminal, desktop, both
  info <app_id>     Show detailed information about a specific application
  validate          Validate all application definition files
  options <app_id>  Show launch options for an application

Examples:
  kdoitall app scan
  kdoitall app list
  kdoitall app list terminal
  kdoitall app info firefox
  kdoitall app validate
  kdoitall app options konsole

For more information, see the application registry documentation.
EOF
}
