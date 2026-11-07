#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: every command the README shows is named in `kdoitall --help`,
# so the two can't drift apart without a failing test.
#
# What is read from README.md:
#   - the command lists: unindented lines in the plain ``` blocks of the
#     Usage section. The ### heading gives the command, e.g. "### Window
#     Commands (window | win)" makes "move (mv) <window-name>" mean
#     "window move". A heading without "(...)" (Status & Update) lists
#     top-level commands. Indented lines (per-flag detail) are skipped.
#   - every `kdoitall ...` invocation in a code block or inline code span.
#     The first word is the command; for a command that has subcommands,
#     the next plain word is the subcommand.
#   - the Global Options block, and the setting names in the Configuration
#     table.
#
# How each is matched against show_help:
#   - A command line is reduced to its literal words, e.g. "app name (n)
#     reset <app_id>" becomes "app name reset". Help must have a line with
#     the same literal words. Argument shapes (<name>, [screen]) are not
#     compared.
#   - An abbreviation the README gives in "(...)" after a subcommand must
#     appear on a help line for that subcommand. A command abbreviation in a
#     heading, "(window | win)", must appear in help as written.
#   - A --flag written on a README command line or in a `kdoitall`
#     invocation must appear on a help line for the same command. Indented
#     flag lists under an entry are left to the subcommand help.
#   - Global options must appear in help's OPTIONS section, and each setting
#     name must start a line in its CONFIGURATION section (indented 2 to 8
#     spaces, so a name in a wrapped description line does not count).

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# shellcheck source=../../lib/commands/help.sh
source "$LIB_DIR/commands/help.sh"

README_FILE="$PROJECT_ROOT/README.md"

LITERAL_RE='^[a-z][a-z0-9-]*$'
ALIAS_RE='^\(([a-z][a-z0-9-]*)\)$'
FLAG_RE='(--[a-z][a-z0-9-]*)'
HEADING_CMD_RE='\(([a-z][a-z0-9-]*)( \| ([a-z][a-z0-9-]*))?\)'
CODE_SPAN_RE='`([^`]*)`'
CONFIG_ROW_RE='^\| `([A-Z][A-Z0-9_]*)` \|'
GLOBAL_FLAG_RE='^--?[a-z]'
HELP_SECTION_RE='^([A-Z][A-Z ]*)( \(.*\))?:$'
CODE_INVOCATION_RE='^[[:space:]]*(\$ )?kdoitall (.*)$'

# split_syntax <line>
# The part of a command line before its description, which is separated
# from it by two or more spaces.
split_syntax() {
    local line="$1"
    line="${line#"${line%%[![:space:]]*}"}"
    printf '%s' "${line%%  *}"
}

# parse_syntax <syntax> <literals-ref> <alias-ref> <flags-ref>
# Literal words up to the first word that is none of: literal, (alias),
# <placeholder>, [optional], "quoted", -flag. Aliases are taken from the
# "(x)" tokens; flags from every --flag in the syntax.
parse_syntax() {
    local syntax="$1"
    local -n literals_out="$2"
    local -n alias_out="$3"
    local -n flags_out="$4"
    local token=""
    local rest=""
    local -a tokens=()

    literals_out=""
    alias_out=""
    flags_out=""

    read -ra tokens <<< "$syntax"
    for token in "${tokens[@]}"; do
        if [[ "$token" =~ $LITERAL_RE ]]; then
            literals_out+="${literals_out:+ }$token"
        elif [[ "$token" =~ $ALIAS_RE ]]; then
            alias_out+="${alias_out:+ }${BASH_REMATCH[1]}"
        elif [[ "$token" == [\<\[\"-]* ]]; then
            continue
        else
            break
        fi
    done

    rest="$syntax"
    while [[ "$rest" =~ $FLAG_RE ]]; do
        flags_out+="${flags_out:+ }${BASH_REMATCH[1]}"
        rest="${rest#*"${BASH_REMATCH[1]}"}"
    done
}

# ----------------------------------------------------------------------------
# What --help says
# ----------------------------------------------------------------------------

help_text="$(show_help)"

declare -A HELP_SIGS=()
declare -A HELP_ALIASES=()
declare -A HELP_FLAGS=()
HELP_GLOBAL_FLAGS=""
HELP_CONFIG=""

# Filled by parse_syntax through its name references
sig=""
sig_alias=""
sig_flags=""
words=""
words_alias=""
words_flags=""

help_section=""
while IFS= read -r line; do
    if [[ "$line" =~ $HELP_SECTION_RE ]]; then
        help_section="${BASH_REMATCH[1]}"
        continue
    fi
    [[ "$help_section" == "EXAMPLES" ]] && break

    if [[ "$help_section" == "CONFIGURATION" ]]; then
        HELP_CONFIG+="$line"$'\n'
        continue
    fi

    if [[ "$help_section" == "OPTIONS" && "$line" == "    -"* ]]; then
        HELP_GLOBAL_FLAGS+=" $(split_syntax "$line" | tr -d ',') "
        continue
    fi

    # Command lines are indented by exactly four spaces. Deeper indents are
    # continuation lines of the entry above.
    [[ "$line" =~ ^\ {4}[a-z] ]] || continue
    [[ "$line" == "    kdoitall "* ]] && continue

    parse_syntax "$(split_syntax "$line")" sig sig_alias sig_flags
    [[ -n "$sig" ]] || continue
    HELP_SIGS["$sig"]=1
    HELP_ALIASES["$sig"]+=" $sig_alias "
    HELP_FLAGS["$sig"]+=" $sig_flags "
done <<< "$help_text"

# ----------------------------------------------------------------------------
# What the README shows
# ----------------------------------------------------------------------------

declare -A README_SIGS=()        # signature -> README line number
declare -A README_ALIASES=()     # signature -> aliases given in the README
declare -A README_FLAGS=()       # signature -> flags given on its line
declare -A SUB_ALIAS_MAP=()      # "cmd alias" -> "cmd sub"
declare -A CMD_ALIAS_MAP=()      # command alias -> command
declare -A HAS_SUBCOMMANDS=()    # command -> 1
README_HEADING_ALIASES=()        # "(window | win)" as written
README_GLOBAL_FLAGS=()           # "flag:line"
README_CONFIG_KEYS=()            # "KEY:line"
INVOCATIONS=()                   # "text:line"

add_readme_sig() {
    local sig="$1"
    local line_no="$2"
    local aliases="$3"
    local flags="$4"
    [[ -n "${README_SIGS[$sig]:-}" ]] || README_SIGS["$sig"]="$line_no"
    README_ALIASES["$sig"]+=" $aliases "
    README_FLAGS["$sig"]+=" $flags "
}

line_no=0
in_fence=false
fence_lang=""
h2=""
h3=""
list_cmd=""
while IFS= read -r line; do
    line_no=$((line_no + 1))

    if [[ "$line" == '```'* ]]; then
        if [[ "$in_fence" == true ]]; then
            in_fence=false
        else
            in_fence=true
            fence_lang="${line#\`\`\`}"
        fi
        continue
    fi

    if [[ "$in_fence" == false ]]; then
        case "$line" in
            "## "*)
                h2="${line#\#\# }"
                h3=""
                list_cmd=""
                ;;
            "### "*)
                h3="${line#\#\#\# }"
                list_cmd=""
                if [[ "$h3" =~ $HEADING_CMD_RE ]]; then
                    list_cmd="${BASH_REMATCH[1]}"
                    if [[ -n "${BASH_REMATCH[3]}" ]]; then
                        CMD_ALIAS_MAP["${BASH_REMATCH[3]}"]="$list_cmd"
                    fi
                    README_HEADING_ALIASES+=("${BASH_REMATCH[0]}:$line_no")
                fi
                ;;
        esac

        if [[ "$h2" == "Configuration" && "$line" =~ $CONFIG_ROW_RE ]]; then
            README_CONFIG_KEYS+=("${BASH_REMATCH[1]}:$line_no")
        fi

        # Inline code spans that run kdoitall
        rest="$line"
        while [[ "$rest" =~ $CODE_SPAN_RE ]]; do
            span="${BASH_REMATCH[1]}"
            rest="${rest#*"${BASH_REMATCH[0]}"}"
            if [[ "$span" == "kdoitall "* ]]; then
                INVOCATIONS+=("$span:$line_no")
            fi
        done
        continue
    fi

    # Inside a code block: a line that runs kdoitall, with or without a
    # "$ " prompt in front
    if [[ "$line" =~ $CODE_INVOCATION_RE ]]; then
        INVOCATIONS+=("kdoitall ${BASH_REMATCH[2]}:$line_no")
        continue
    fi

    [[ "$h2" == "Usage" && -z "$fence_lang" ]] || continue

    if [[ "$h3" == "Global Options" ]]; then
        if [[ "$line" == -* ]]; then
            read -ra flag_words <<< "$(split_syntax "$line" | tr -d ',')"
            for flag in "${flag_words[@]}"; do
                README_GLOBAL_FLAGS+=("$flag:$line_no")
            done
        fi
        continue
    fi

    # A command-list entry: unindented, starts with a lowercase word
    [[ "$line" =~ ^[a-z] ]] || continue
    parse_syntax "$(split_syntax "$line")" words words_alias words_flags
    [[ -n "$words" ]] || continue

    if [[ -z "$list_cmd" || "${words%% *}" == "$list_cmd" ]]; then
        sig="$words"
    else
        sig="$list_cmd $words"
        HAS_SUBCOMMANDS["$list_cmd"]=1
        if [[ -n "$words_alias" ]]; then
            SUB_ALIAS_MAP["$list_cmd $words_alias"]="$list_cmd ${words%% *}"
        fi
    fi
    add_readme_sig "$sig" "$line_no" "$words_alias" "$words_flags"
done < "$README_FILE"

# Invocations: kdoitall [--global] <command> [<subcommand>] ...
for entry in "${INVOCATIONS[@]}"; do
    text="${entry%:*}"
    inv_line="${entry##*:}"
    cmd=""
    sub=""
    inv_flags=""
    read -ra inv_tokens <<< "${text#kdoitall }"
    for token in "${inv_tokens[@]}"; do
        if [[ -z "$cmd" ]]; then
            if [[ "$token" =~ $GLOBAL_FLAG_RE ]]; then
                README_GLOBAL_FLAGS+=("$token:$inv_line")
                continue
            fi
            [[ "$token" =~ $LITERAL_RE ]] || break
            cmd="${CMD_ALIAS_MAP[$token]:-$token}"
            continue
        fi
        if [[ "$token" =~ $FLAG_RE && "$token" == -* ]]; then
            inv_flags+="${inv_flags:+ }${BASH_REMATCH[1]}"
        elif [[ -z "$sub" && -n "${HAS_SUBCOMMANDS[$cmd]:-}" \
                && "$token" =~ $LITERAL_RE ]]; then
            sub="$token"
        fi
    done
    [[ -n "$cmd" ]] || continue
    sig="$cmd${sub:+ $sub}"
    if [[ -n "${SUB_ALIAS_MAP[$sig]:-}" ]]; then
        sig="${SUB_ALIAS_MAP[$sig]}"
    fi
    add_readme_sig "$sig" "$inv_line" "" "$inv_flags"
done

# ----------------------------------------------------------------------------
# The parser found what it should, so the checks below aren't vacuous
# ----------------------------------------------------------------------------

assert_true "README parse: found more than 25 commands (found ${#README_SIGS[@]})" \
    test "${#README_SIGS[@]}" -gt 25
for anchor in "status" "quick" "workspace open" "app scan" "screen alias remove" "window move"; do
    assert_true "README parse: found '$anchor'" test -n "${README_SIGS[$anchor]:-}"
done
assert_true "README parse: found global options" test "${#README_GLOBAL_FLAGS[@]}" -gt 3
assert_true "README parse: found config settings" test "${#README_CONFIG_KEYS[@]}" -gt 3
assert_true "help parse: found more than 25 commands (found ${#HELP_SIGS[@]})" \
    test "${#HELP_SIGS[@]}" -gt 25

# ----------------------------------------------------------------------------
# Every README command, abbreviation and flag is in --help
# ----------------------------------------------------------------------------

mapfile -t sorted_sigs < <(printf '%s\n' "${!README_SIGS[@]}" | sort)
for sig in "${sorted_sigs[@]}"; do
    where="README.md:${README_SIGS[$sig]}"
    if [[ -z "${HELP_SIGS[$sig]:-}" ]]; then
        fail "help names '$sig'" "$where shows it; --help has no such line"
        continue
    fi
    pass "help names '$sig'"

    read -ra sig_alias_words <<< "$(printf '%s\n' ${README_ALIASES[$sig]} | sort -u | tr '\n' ' ')"
    for alias in "${sig_alias_words[@]}"; do
        if [[ "${HELP_ALIASES[$sig]}" == *" $alias "* ]]; then
            pass "help gives '($alias)' for '$sig'"
        else
            fail "help gives '($alias)' for '$sig'" "$where gives it; --help doesn't"
        fi
    done

    read -ra sig_flag_words <<< "$(printf '%s\n' ${README_FLAGS[$sig]} | sort -u | tr '\n' ' ')"
    for flag in "${sig_flag_words[@]}"; do
        if [[ "${HELP_FLAGS[$sig]}" == *" $flag "* ]]; then
            pass "help shows '$flag' for '$sig'"
        else
            fail "help shows '$flag' for '$sig'" "README.md uses it; --help doesn't"
        fi
    done
done

for entry in "${README_HEADING_ALIASES[@]}"; do
    heading="${entry%:*}"
    if [[ "$help_text" == *"$heading"* ]]; then
        pass "help heading has '$heading'"
    else
        fail "help heading has '$heading'" "README.md:${entry##*:} has it; --help doesn't"
    fi
done

mapfile -t README_GLOBAL_FLAGS < <(printf '%s\n' "${README_GLOBAL_FLAGS[@]}" | sort -t: -k1,1 -u)
for entry in "${README_GLOBAL_FLAGS[@]}"; do
    flag="${entry%:*}"
    if [[ " $HELP_GLOBAL_FLAGS " == *" $flag "* ]]; then
        pass "help OPTIONS has '$flag'"
    else
        fail "help OPTIONS has '$flag'" "README.md:${entry##*:} has it; --help doesn't"
    fi
done

for entry in "${README_CONFIG_KEYS[@]}"; do
    key="${entry%:*}"
    if grep -qE -- "^ {2,8}${key}( |\$)" <<< "$HELP_CONFIG"; then
        pass "help CONFIGURATION has '$key'"
    else
        fail "help CONFIGURATION has '$key'" "README.md:${entry##*:} has it; --help doesn't"
    fi
done

finish
