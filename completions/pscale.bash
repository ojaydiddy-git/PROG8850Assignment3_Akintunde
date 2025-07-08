# bash completion for pscale                               -*- shell-script -*-

__pscale_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__pscale_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__pscale_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__pscale_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__pscale_handle_go_custom_completion()
{
    __pscale_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly pscale allows handling aliases
    args=("${words[@]:1}")
    # Disable ActiveHelp which is not supported for bash completion v1
    requestComp="PSCALE_ACTIVE_HELP=0 ${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __pscale_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __pscale_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __pscale_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __pscale_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __pscale_debug "${FUNCNAME[0]}: the completions are: ${out}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        # Error code.  No completion.
        __pscale_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __pscale_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __pscale_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local fullFilter filter filteringCmd
        # Do not use quotes around the $out variable or else newline
        # characters will be kept.
        for filter in ${out}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __pscale_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        # Use printf to strip any trailing newline
        subdir=$(printf "%s" "${out}")
        if [ -n "$subdir" ]; then
            __pscale_debug "Listing directories in $subdir"
            __pscale_handle_subdirs_in_dir_flag "$subdir"
        else
            __pscale_debug "Listing directories in ."
            _filedir -d
        fi
    else
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out}" -- "$cur")
    fi
}

__pscale_handle_reply()
{
    __pscale_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __pscale_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION:-}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi

            if [[ -z "${flag_parsing_disabled}" ]]; then
                # If flag parsing is enabled, we have completed the flags and can return.
                # If flag parsing is disabled, we may not know all (or any) of the flags, so we fallthrough
                # to possibly call handle_go_custom_completion.
                return 0;
            fi
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __pscale_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions+=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        __pscale_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        if declare -F __pscale_custom_func >/dev/null; then
            # try command name qualified custom func
            __pscale_custom_func
        else
            # otherwise fall back to unqualified for compatibility
            declare -F __custom_func >/dev/null && __custom_func
        fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__pscale_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__pscale_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__pscale_handle_flag()
{
    __pscale_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue=""
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __pscale_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __pscale_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __pscale_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __pscale_contains_word "${words[c]}" "${two_word_flags[@]}"; then
        __pscale_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__pscale_handle_noun()
{
    __pscale_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __pscale_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __pscale_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__pscale_handle_command()
{
    __pscale_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_pscale_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __pscale_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__pscale_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __pscale_handle_reply
        return
    fi
    __pscale_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __pscale_handle_flag
    elif __pscale_contains_word "${words[c]}" "${commands[@]}"; then
        __pscale_handle_command
    elif [[ $c -eq 0 ]]; then
        __pscale_handle_command
    elif __pscale_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __pscale_handle_command
        else
            __pscale_handle_noun
        fi
    else
        __pscale_handle_noun
    fi
    __pscale_handle_word
}

_pscale_api()
{
    last_command="pscale_api"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--branch=")
    two_word_flags+=("--branch")
    flags+=("--database=")
    two_word_flags+=("--database")
    flags+=("--field=")
    two_word_flags+=("--field")
    two_word_flags+=("-F")
    flags+=("--header=")
    two_word_flags+=("--header")
    two_word_flags+=("-H")
    flags+=("--input=")
    two_word_flags+=("--input")
    two_word_flags+=("-I")
    flags+=("--method=")
    two_word_flags+=("--method")
    two_word_flags+=("-X")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--query=")
    two_word_flags+=("--query")
    two_word_flags+=("-Q")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_audit-log_list()
{
    last_command="pscale_audit-log_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--action=")
    two_word_flags+=("--action")
    flags_with_completion+=("--action")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    flags+=("--starting-after=")
    two_word_flags+=("--starting-after")
    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_audit-log()
{
    last_command="pscale_audit-log"

    command_aliases=()

    commands=()
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_auth_check()
{
    last_command="pscale_auth_check"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--client-id=")
    two_word_flags+=("--client-id")
    flags+=("--client-secret=")
    two_word_flags+=("--client-secret")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_auth_login()
{
    last_command="pscale_auth_login"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--client-id=")
    two_word_flags+=("--client-id")
    flags+=("--client-secret=")
    two_word_flags+=("--client-secret")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_auth_logout()
{
    last_command="pscale_auth_logout"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--client-id=")
    two_word_flags+=("--client-id")
    flags+=("--client-secret=")
    two_word_flags+=("--client-secret")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_auth()
{
    last_command="pscale_auth"

    command_aliases=()

    commands=()
    commands+=("check")
    commands+=("login")
    commands+=("logout")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_backup_create()
{
    last_command="pscale_backup_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_backup_delete()
{
    last_command="pscale_backup_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_backup_list()
{
    last_command="pscale_backup_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_backup_restore()
{
    last_command="pscale_backup_restore"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster-size=")
    two_word_flags+=("--cluster-size")
    flags_with_completion+=("--cluster-size")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--cluster-size=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_backup_show()
{
    last_command="pscale_backup_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_backup()
{
    last_command="pscale_backup"

    command_aliases=()

    commands=()
    commands+=("create")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("b")
        aliashash["b"]="create"
    fi
    commands+=("delete")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("rm")
        aliashash["rm"]="delete"
    fi
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("restore")
    commands+=("show")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_create()
{
    last_command="pscale_branch_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster-size=")
    two_word_flags+=("--cluster-size")
    flags_with_completion+=("--cluster-size")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--from=")
    two_word_flags+=("--from")
    flags+=("--region=")
    two_word_flags+=("--region")
    flags_with_completion+=("--region")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--restore=")
    two_word_flags+=("--restore")
    flags+=("--seed-data")
    flags+=("--wait")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_branch_delete()
{
    last_command="pscale_branch_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_demote()
{
    last_command="pscale_branch_demote"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_diff()
{
    last_command="pscale_branch_diff"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_lint()
{
    last_command="pscale_branch_lint"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_list()
{
    last_command="pscale_branch_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_branch_promote()
{
    last_command="pscale_branch_promote"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_branch_refresh-schema()
{
    last_command="pscale_branch_refresh-schema"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_routing-rules_get()
{
    last_command="pscale_branch_routing-rules_get"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_routing-rules_update()
{
    last_command="pscale_branch_routing-rules_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--routing-rules=")
    two_word_flags+=("--routing-rules")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_routing-rules()
{
    last_command="pscale_branch_routing-rules"

    command_aliases=()

    commands=()
    commands+=("get")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_safe-migrations_disable()
{
    last_command="pscale_branch_safe-migrations_disable"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_safe-migrations_enable()
{
    last_command="pscale_branch_safe-migrations_enable"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_safe-migrations()
{
    last_command="pscale_branch_safe-migrations"

    command_aliases=()

    commands=()
    commands+=("disable")
    commands+=("enable")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_schema()
{
    last_command="pscale_branch_schema"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--keyspace=")
    two_word_flags+=("--keyspace")
    flags+=("--web")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_show()
{
    last_command="pscale_branch_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch_switch()
{
    last_command="pscale_branch_switch"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--create")
    flags+=("--database=")
    two_word_flags+=("--database")
    flags+=("--parent-branch=")
    two_word_flags+=("--parent-branch")
    flags+=("--wait")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--database=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_branch()
{
    last_command="pscale_branch"

    command_aliases=()

    commands=()
    commands+=("create")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("b")
        aliashash["b"]="create"
    fi
    commands+=("delete")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("rm")
        aliashash["rm"]="delete"
    fi
    commands+=("demote")
    commands+=("diff")
    commands+=("lint")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("promote")
    commands+=("refresh-schema")
    commands+=("routing-rules")
    commands+=("safe-migrations")
    commands+=("schema")
    commands+=("show")
    commands+=("switch")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_completion()
{
    last_command="pscale_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("bash")
    must_have_one_noun+=("fish")
    must_have_one_noun+=("powershell")
    must_have_one_noun+=("zsh")
    noun_aliases=()
}

_pscale_connect()
{
    last_command="pscale_connect"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--execute=")
    two_word_flags+=("--execute")
    flags+=("--execute-env-url=")
    two_word_flags+=("--execute-env-url")
    flags+=("--execute-protocol=")
    two_word_flags+=("--execute-protocol")
    flags+=("--host=")
    two_word_flags+=("--host")
    flags+=("--mysql-auth-method=")
    two_word_flags+=("--mysql-auth-method")
    flags+=("--no-random")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--port=")
    two_word_flags+=("--port")
    flags+=("--remote-addr=")
    two_word_flags+=("--remote-addr")
    flags+=("--replica")
    flags+=("--role=")
    two_word_flags+=("--role")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_cancel()
{
    last_command="pscale_data-imports_cancel"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--name=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_detach-external-database()
{
    last_command="pscale_data-imports_detach-external-database"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--name=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_get()
{
    last_command="pscale_data-imports_get"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--name=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_lint()
{
    last_command="pscale_data-imports_lint"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--database=")
    two_word_flags+=("--database")
    flags+=("--host=")
    two_word_flags+=("--host")
    flags+=("--password=")
    two_word_flags+=("--password")
    flags+=("--port=")
    two_word_flags+=("--port")
    flags+=("--ssl-certificate-authority=")
    two_word_flags+=("--ssl-certificate-authority")
    flags+=("--ssl-client-certificate=")
    two_word_flags+=("--ssl-client-certificate")
    flags+=("--ssl-client-key=")
    two_word_flags+=("--ssl-client-key")
    flags+=("--ssl-mode=")
    two_word_flags+=("--ssl-mode")
    flags+=("--ssl-server-name=")
    two_word_flags+=("--ssl-server-name")
    flags+=("--username=")
    two_word_flags+=("--username")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--database=")
    must_have_one_flag+=("--host=")
    must_have_one_flag+=("--password=")
    must_have_one_flag+=("--ssl-mode=")
    must_have_one_flag+=("--username=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_make-primary()
{
    last_command="pscale_data-imports_make-primary"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--name=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_make-replica()
{
    last_command="pscale_data-imports_make-replica"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--name=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports_start()
{
    last_command="pscale_data-imports_start"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--database=")
    two_word_flags+=("--database")
    flags+=("--dry-run")
    flags+=("--host=")
    two_word_flags+=("--host")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--password=")
    two_word_flags+=("--password")
    flags+=("--port=")
    two_word_flags+=("--port")
    flags+=("--region=")
    two_word_flags+=("--region")
    flags+=("--ssl-certificate-authority=")
    two_word_flags+=("--ssl-certificate-authority")
    flags+=("--ssl-client-certificate=")
    two_word_flags+=("--ssl-client-certificate")
    flags+=("--ssl-client-key=")
    two_word_flags+=("--ssl-client-key")
    flags+=("--ssl-mode=")
    two_word_flags+=("--ssl-mode")
    flags+=("--ssl-server-name=")
    two_word_flags+=("--ssl-server-name")
    flags+=("--username=")
    two_word_flags+=("--username")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--database=")
    must_have_one_flag+=("--host=")
    must_have_one_flag+=("--name=")
    must_have_one_flag+=("--password=")
    must_have_one_flag+=("--ssl-mode=")
    must_have_one_flag+=("--username=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_data-imports()
{
    last_command="pscale_data-imports"

    command_aliases=()

    commands=()
    commands+=("cancel")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("c")
        aliashash["c"]="cancel"
    fi
    commands+=("detach-external-database")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ded")
        aliashash["ded"]="detach-external-database"
    fi
    commands+=("get")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("g")
        aliashash["g"]="get"
    fi
    commands+=("lint")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("l")
        aliashash["l"]="lint"
    fi
    commands+=("make-primary")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("mp")
        aliashash["mp"]="make-primary"
    fi
    commands+=("make-replica")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("mr")
        aliashash["mr"]="make-replica"
    fi
    commands+=("start")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("s")
        aliashash["s"]="start"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_database_create()
{
    last_command="pscale_database_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster-size=")
    two_word_flags+=("--cluster-size")
    flags_with_completion+=("--cluster-size")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--region=")
    two_word_flags+=("--region")
    flags_with_completion+=("--region")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_database_delete()
{
    last_command="pscale_database_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_database_dump()
{
    last_command="pscale_database_dump"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--keyspace=")
    two_word_flags+=("--keyspace")
    flags+=("--local-addr=")
    two_word_flags+=("--local-addr")
    flags+=("--output=")
    two_word_flags+=("--output")
    flags+=("--rdonly")
    flags+=("--remote-addr=")
    two_word_flags+=("--remote-addr")
    flags+=("--replica")
    flags+=("--schema-only")
    flags+=("--shard=")
    two_word_flags+=("--shard")
    flags+=("--tables=")
    two_word_flags+=("--tables")
    flags+=("--threads=")
    two_word_flags+=("--threads")
    flags+=("--wheres=")
    two_word_flags+=("--wheres")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_database_list()
{
    last_command="pscale_database_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--page=")
    two_word_flags+=("--page")
    flags+=("--per-page=")
    two_word_flags+=("--per-page")
    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_database_restore-dump()
{
    last_command="pscale_database_restore-dump"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-different-destination")
    flags+=("--data-only")
    flags+=("--dir=")
    two_word_flags+=("--dir")
    flags+=("--ending-table=")
    two_word_flags+=("--ending-table")
    flags+=("--local-addr=")
    two_word_flags+=("--local-addr")
    flags+=("--max-query-size=")
    two_word_flags+=("--max-query-size")
    flags+=("--overwrite-tables")
    flags+=("--remote-addr=")
    two_word_flags+=("--remote-addr")
    flags+=("--schema-only")
    flags+=("--show-details")
    flags+=("--starting-table=")
    two_word_flags+=("--starting-table")
    flags+=("--threads=")
    two_word_flags+=("--threads")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_database_show()
{
    last_command="pscale_database_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_database()
{
    last_command="pscale_database"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("rm")
        aliashash["rm"]="delete"
    fi
    commands+=("dump")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("restore-dump")
    commands+=("show")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_apply()
{
    last_command="pscale_deploy-request_apply"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_cancel()
{
    last_command="pscale_deploy-request_cancel"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_close()
{
    last_command="pscale_deploy-request_close"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_create()
{
    last_command="pscale_deploy-request_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--auto-delete-branch")
    flags+=("--into=")
    two_word_flags+=("--into")
    flags+=("--notes=")
    two_word_flags+=("--notes")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_deploy()
{
    last_command="pscale_deploy-request_deploy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--instant")
    flags+=("--wait")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_diff()
{
    last_command="pscale_deploy-request_diff"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_edit()
{
    last_command="pscale_deploy-request_edit"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--auto-apply=")
    two_word_flags+=("--auto-apply")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_list()
{
    last_command="pscale_deploy-request_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_revert()
{
    last_command="pscale_deploy-request_revert"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_review()
{
    last_command="pscale_deploy-request_review"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--approve")
    flags+=("--comment=")
    two_word_flags+=("--comment")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_show()
{
    last_command="pscale_deploy-request_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request_skip-revert()
{
    last_command="pscale_deploy-request_skip-revert"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_deploy-request()
{
    last_command="pscale_deploy-request"

    command_aliases=()

    commands=()
    commands+=("apply")
    commands+=("cancel")
    commands+=("close")
    commands+=("create")
    commands+=("deploy")
    commands+=("diff")
    commands+=("edit")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("revert")
    commands+=("review")
    commands+=("show")
    commands+=("skip-revert")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_help()
{
    last_command="pscale_help"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_keyspace_create()
{
    last_command="pscale_keyspace_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--additional-replicas=")
    two_word_flags+=("--additional-replicas")
    flags+=("--cluster-size=")
    two_word_flags+=("--cluster-size")
    flags_with_completion+=("--cluster-size")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--shards=")
    two_word_flags+=("--shards")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--cluster-size=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_list()
{
    last_command="pscale_keyspace_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_resize_cancel()
{
    last_command="pscale_keyspace_resize_cancel"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_resize_status()
{
    last_command="pscale_keyspace_resize_status"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_resize()
{
    last_command="pscale_keyspace_resize"

    command_aliases=()

    commands=()
    commands+=("cancel")
    commands+=("status")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--additional-replicas=")
    two_word_flags+=("--additional-replicas")
    flags+=("--cluster-size=")
    two_word_flags+=("--cluster-size")
    flags_with_completion+=("--cluster-size")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_rollout-status()
{
    last_command="pscale_keyspace_rollout-status"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_settings()
{
    last_command="pscale_keyspace_settings"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_show()
{
    last_command="pscale_keyspace_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_update-settings()
{
    last_command="pscale_keyspace_update-settings"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--interactive")
    flags+=("-i")
    flags+=("--replication-durability-constraints-strategy=")
    two_word_flags+=("--replication-durability-constraints-strategy")
    flags+=("--vreplication-batch-replication-events")
    flags+=("--vreplication-enable-noblob-binlog-mode")
    flags+=("--vreplication-optimize-inserts")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_vschema_show()
{
    last_command="pscale_keyspace_vschema_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_vschema_update()
{
    last_command="pscale_keyspace_vschema_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--vschema=")
    two_word_flags+=("--vschema")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace_vschema()
{
    last_command="pscale_keyspace_vschema"

    command_aliases=()

    commands=()
    commands+=("show")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_keyspace()
{
    last_command="pscale_keyspace"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("list")
    commands+=("resize")
    commands+=("rollout-status")
    commands+=("settings")
    commands+=("show")
    commands+=("update-settings")
    commands+=("vschema")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_mcp_install()
{
    last_command="pscale_mcp_install"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--target=")
    two_word_flags+=("--target")
    flags_with_completion+=("--target")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--target=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_mcp_server()
{
    last_command="pscale_mcp_server"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_mcp()
{
    last_command="pscale_mcp"

    command_aliases=()

    commands=()
    commands+=("install")
    commands+=("server")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_org_list()
{
    last_command="pscale_org_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_org_show()
{
    last_command="pscale_org_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_org_switch()
{
    last_command="pscale_org_switch"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--save-config=")
    two_word_flags+=("--save-config")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_org()
{
    last_command="pscale_org"

    command_aliases=()

    commands=()
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("show")
    commands+=("switch")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_password_create()
{
    last_command="pscale_password_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--replica")
    flags+=("--role=")
    two_word_flags+=("--role")
    flags+=("--ttl=")
    two_word_flags+=("--ttl")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_password_delete()
{
    last_command="pscale_password_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_password_list()
{
    last_command="pscale_password_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--web")
    flags+=("-w")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_password_renew()
{
    last_command="pscale_password_renew"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_password()
{
    last_command="pscale_password"

    command_aliases=()

    commands=()
    commands+=("create")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("p")
        aliashash["p"]="create"
    fi
    commands+=("delete")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("rm")
        aliashash["rm"]="delete"
    fi
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("renew")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_ping()
{
    last_command="pscale_ping"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--concurrency=")
    two_word_flags+=("--concurrency")
    flags+=("--count=")
    two_word_flags+=("--count")
    two_word_flags+=("-n")
    flags+=("--provider=")
    two_word_flags+=("--provider")
    flags_with_completion+=("--provider")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-p")
    flags_with_completion+=("-p")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--timeout=")
    two_word_flags+=("--timeout")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_region_list()
{
    last_command="pscale_region_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_region()
{
    last_command="pscale_region"

    command_aliases=()

    commands=()
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token_add-access()
{
    last_command="pscale_service-token_add-access"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--database=")
    two_word_flags+=("--database")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token_create()
{
    last_command="pscale_service-token_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token_delete()
{
    last_command="pscale_service-token_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token_delete-access()
{
    last_command="pscale_service-token_delete-access"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--database=")
    two_word_flags+=("--database")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token_list()
{
    last_command="pscale_service-token_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token_show-access()
{
    last_command="pscale_service-token_show-access"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_service-token()
{
    last_command="pscale_service-token"

    command_aliases=()

    commands=()
    commands+=("add-access")
    commands+=("create")
    commands+=("delete")
    commands+=("delete-access")
    commands+=("list")
    commands+=("show-access")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_shell()
{
    last_command="pscale_shell"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--local-addr=")
    two_word_flags+=("--local-addr")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--remote-addr=")
    two_word_flags+=("--remote-addr")
    flags+=("--replica")
    flags+=("--role=")
    two_word_flags+=("--role")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_signup()
{
    last_command="pscale_signup"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_size_cluster_list()
{
    last_command="pscale_size_cluster_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--metal")
    flags+=("--region=")
    two_word_flags+=("--region")
    flags_with_completion+=("--region")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_size_cluster()
{
    last_command="pscale_size_cluster"

    command_aliases=()

    commands=()
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_size()
{
    last_command="pscale_size"

    command_aliases=()

    commands=()
    commands+=("cluster")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("clusters")
        aliashash["clusters"]="cluster"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_cancel()
{
    last_command="pscale_workflow_cancel"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_complete()
{
    last_command="pscale_workflow_complete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_create()
{
    last_command="pscale_workflow_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--defer-secondary-keys")
    flags+=("--global-keyspace=")
    two_word_flags+=("--global-keyspace")
    flags+=("--interactive")
    flags+=("-i")
    flags+=("--name=")
    two_word_flags+=("--name")
    flags+=("--on-ddl=")
    two_word_flags+=("--on-ddl")
    flags_with_completion+=("--on-ddl")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--source-keyspace=")
    two_word_flags+=("--source-keyspace")
    flags+=("--tables=")
    two_word_flags+=("--tables")
    flags+=("--target-keyspace=")
    two_word_flags+=("--target-keyspace")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_cutover()
{
    last_command="pscale_workflow_cutover"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_list()
{
    last_command="pscale_workflow_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_pscale_workflow_retry()
{
    last_command="pscale_workflow_retry"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_reverse-cutover()
{
    last_command="pscale_workflow_reverse-cutover"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_reverse-traffic()
{
    last_command="pscale_workflow_reverse-traffic"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_show()
{
    last_command="pscale_workflow_show"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_switch-traffic()
{
    last_command="pscale_workflow_switch-traffic"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("--replicas-only")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow_verify-data()
{
    last_command="pscale_workflow_verify-data"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_workflow()
{
    last_command="pscale_workflow"

    command_aliases=()

    commands=()
    commands+=("cancel")
    commands+=("complete")
    commands+=("create")
    commands+=("cutover")
    commands+=("list")
    commands+=("retry")
    commands+=("reverse-cutover")
    commands+=("reverse-traffic")
    commands+=("show")
    commands+=("switch-traffic")
    commands+=("verify-data")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--org=")
    two_word_flags+=("--org")
    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")

    must_have_one_flag=()
    must_have_one_flag+=("--org=")
    must_have_one_noun=()
    noun_aliases=()
}

_pscale_root_command()
{
    last_command="pscale"

    command_aliases=()

    commands=()
    commands+=("api")
    commands+=("audit-log")
    commands+=("auth")
    commands+=("backup")
    commands+=("branch")
    commands+=("completion")
    commands+=("connect")
    commands+=("data-imports")
    commands+=("database")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("db")
        aliashash["db"]="database"
    fi
    commands+=("deploy-request")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("dr")
        aliashash["dr"]="deploy-request"
    fi
    commands+=("help")
    commands+=("keyspace")
    commands+=("mcp")
    commands+=("org")
    commands+=("password")
    commands+=("ping")
    commands+=("region")
    commands+=("service-token")
    commands+=("shell")
    commands+=("signup")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("register")
        aliashash["register"]="signup"
        command_aliases+=("sign-up")
        aliashash["sign-up"]="signup"
    fi
    commands+=("size")
    commands+=("workflow")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--api-token=")
    two_word_flags+=("--api-token")
    flags+=("--api-url=")
    two_word_flags+=("--api-url")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--debug")
    flags+=("--format=")
    two_word_flags+=("--format")
    flags_with_completion+=("--format")
    flags_completion+=("__pscale_handle_go_custom_completion")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__pscale_handle_go_custom_completion")
    flags+=("--no-color")
    flags+=("--service-token=")
    two_word_flags+=("--service-token")
    flags+=("--service-token-id=")
    two_word_flags+=("--service-token-id")
    flags+=("--version")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_pscale()
{
    local cur prev words cword split
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __pscale_init_completion -n "=" || return
    fi

    local c=0
    local flag_parsing_disabled=
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("pscale")
    local command_aliases=()
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function=""
    local last_command=""
    local nouns=()
    local noun_aliases=()

    __pscale_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_pscale pscale
else
    complete -o default -o nospace -F __start_pscale pscale
fi

# ex: ts=4 sw=4 et filetype=sh
