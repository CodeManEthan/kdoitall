#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: validate_params, launch_option_exists, is_shell_identifier

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --- validate_params ---------------------------------------------------------

assert_true  "params: plain text accepted"            validate_params "hello"
assert_true  "params: spaces accepted"                validate_params "/home/user/my project"
assert_true  "params: tab-separated values accepted"  validate_params $'/srv/app\t\tnpm run dev'
assert_true  "params: empty accepted"                 validate_params ""
assert_true  "params: shell syntax accepted as text"  validate_params "\"q\" \`b\` \$(x) 'y' ; & >"
assert_true  "params: non-ASCII accepted"             validate_params "Größe/проект"
assert_false "params: '|' rejected"                   validate_params "a|b"
assert_false "params: newline rejected"               validate_params $'a\nb'
assert_false "params: carriage return rejected"       validate_params $'a\rb'
assert_false "params: escape rejected"                validate_params $'a\x1b[31mb'
assert_false "params: DEL rejected"                   validate_params $'a\x7fb'
assert_false "params: bell rejected"                  validate_params $'a\x07b'

# --- launch_option_exists ------------------------------------------------------

opts=$'terminal_run_script|Run a script|[]\nterm_x|Other|[]'
assert_true  "launch option: exact name found"           launch_option_exists "$opts" "terminal_run_script"
assert_true  "launch option: second line found"          launch_option_exists "$opts" "term_x"
assert_false "launch option: regex alternation literal"  launch_option_exists "$opts" 'nope\|terminal_run_script'
assert_false "launch option: trailing \\| literal"        launch_option_exists "$opts" 'terminal_run_script\|'
assert_false "launch option: '.' is not a wildcard"      launch_option_exists "$opts" "term.x"
assert_false "launch option: prefix is not a match"      launch_option_exists "$opts" "terminal_run"
assert_false "launch option: empty listing"              launch_option_exists "" "term_x"

# --- is_shell_identifier ------------------------------------------------------

assert_true  "identifier: launch function"   is_shell_identifier "terminal_run_script"
assert_true  "identifier: position name"     is_shell_identifier "FULLSCREEN"
assert_false "identifier: command subst"     is_shell_identifier '$(touch x)'
assert_false "identifier: leading digit"     is_shell_identifier "1abc"
assert_false "identifier: hyphen"            is_shell_identifier "a-b"
assert_false "identifier: empty"             is_shell_identifier ""

finish
