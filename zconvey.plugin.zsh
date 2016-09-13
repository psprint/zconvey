#
# No plugin manager is needed to use this file. All that is needed is adding:
#   source {where-zconvey-is}/zconvey.plugin.zsh
#
# to ~/.zshrc.
#

0="${(%):-%N}" # this gives immunity to functionargzero being unset
ZCONVEY_REPO_DIR="${0%/*}"
ZCONVEY_CONFIG_DIR="$HOME/.config/zconvey"

#
# Update FPATH if:
# 1. Not loading with Zplugin
# 2. Not having fpath already updated (that would equal: using other plugin manager)
#

if [[ -z "$ZPLG_CUR_PLUGIN" && "${fpath[(r)$ZCONVEY_REPO_DIR]}" != $ZCONVEY_REPO_DIR ]]; then
    fpath+=( "$ZCONVEY_REPO_DIR" )
fi

#
# Global variables
#

typeset -gi ZCONVEY_ID
typeset -ghH ZCONVEY_FD
typeset -ghH ZCONVEY_IO_DIR="${ZCONVEY_CONFIG_DIR}/io"
typeset -ghH ZCONVEY_LOCKS_DIR="${ZCONVEY_CONFIG_DIR}/locks"
typeset -ghH ZCONVEY_NAMES_DIR="${ZCONVEY_CONFIG_DIR}/names"
typeset -ghH ZCONVEY_OTHER_DIR="${ZCONVEY_CONFIG_DIR}/other"
typeset -ghH ZCONVEY_RUN_SECONDS=$(( SECONDS + 4 ))
typeset -ghH ZCONVEY_SCHEDULE_ORIGIN
command mkdir -p "$ZCONVEY_IO_DIR" "$ZCONVEY_LOCKS_DIR" "$ZCONVEY_NAMES_DIR" "$ZCONVEY_OTHER_DIR"

#
# Helper functions
#

function pinfo() {
    print -- "\033[1;32m$*\033[0m";
}

function pinfo2() {
    print -- "\033[1;33m$*\033[0m";
}

function __convey_resolve_name_to_id() {
    local name="$1"

    REPLY=""
    local f
    for f in "$ZCONVEY_NAMES_DIR"/*.name(N); do
        if [[ ${(M)${(f)"$(<$f)"}:#:$name:} ]]; then
            REPLY="${${f:t}%.name}"
        fi
    done
}

function __convey_get_name_of_id() {
    local id="$1"

    REPLY=""
    local f="$ZCONVEY_NAMES_DIR/${id}.name"
    if [ -e "$f" ]; then
        REPLY=${(f)"$(<$f)"}
        REPLY="${REPLY#:}"
        REPLY="${REPLY%:}"
    fi
}

#
# User functions
#

function __convey_usage_zc-rename() {
    pinfo2 "Renames current Zsh session, or one given via ID or (old) NAME"
    pinfo "Usage: zc-rename [-i ID|-n NAME] [-q|--quiet] [-h|--help] NEW_NAME"
    print -- "-h/--help                - this message"
    print -- "-i ID / --id ID          - ID (number) of Zsh session"
    print -- "-n NAME / --name NAME    - NAME of Zsh session"
    print -- "-q/--quiet               - don't output status messages"
}

function zc-rename() {
    setopt localoptions extendedglob clobber

    local -A opthash
    zparseopts -E -D -A opthash h -help q -quiet i: -id: n: -name: || { __convey_usage_zc-rename; return 1; }

    integer have_id=0 have_name=0 quiet=0
    local id name new_name="$1"

    # Help
    (( ${+opthash[-h]} + ${+opthash[--help]} )) && { __convey_usage_zc-rename; return 0; }
    [ -z "$new_name" ] && { echo "No new name given"; __convey_usage_zc-rename; return 1; }

    # ID
    have_id=$(( ${+opthash[-i]} + ${+opthash[--id]} ))
    (( ${+opthash[-i]} )) && id="${opthash[-i]}"
    (( ${+opthash[--id]} )) && id="${opthash[--id]}"

    # NAME
    have_name=$(( ${+opthash[-n]} + ${+opthash[--name]} ))
    (( ${+opthash[-n]} )) && name="${opthash[-n]}"
    (( ${+opthash[--name]} )) && name="${opthash[--name]}"

    # QUIET
    (( quiet = ${+opthash[-q]} + ${+opthash[--quiet]} ))

    if [[ "$have_id" != "0" && "$have_name" != "0" ]]; then
        pinfo "Please supply only one of ID (-i) and NAME (-n)"
        return 1
    fi

    if [[ "$have_id" != "0" && ( "$id" != <-> || "$id" = "0" ) ]]; then
        pinfo "ID must be numeric, 1..100"
        return 1
    fi

    # Rename via NAME?
    if (( $have_name )); then
        __convey_resolve_name_to_id "$name"
        local resolved="$REPLY"
        if [ -z "$resolved" ]; then
            pinfo "Could not find session named: \`$name'"
            return 1
        fi

        # Store the resolved ID and continue normally,
        # with ID as the main specifier of session
        id="$resolved"
    elif (( $have_id == 0 )); then
        id="$ZCONVEY_ID"
    fi

    __convey_resolve_name_to_id "$new_name"
    if [ -n "$REPLY" ]; then
        pinfo "A session already has target name: \`$new_name' (its ID: $REPLY)"
        return 1
    fi

    if [[ "$id" != <-> || "$id" = "0" ]]; then
        pinfo "Bad ID ($id), aborting"
        return 1
    fi

    if [[ "$id" -gt "100" ]]; then
        pinfo "Maximum nr of sessions is 100, aborting"
        return 1
    fi

    print ":$new_name:" > "$ZCONVEY_NAMES_DIR"/"$id".name

    if (( ${quiet} == 0 )); then
        pinfo2 "Renamed session $id to: $new_name"
    fi

    local ls_after_rename
    zstyle -b ":plugin:zconvey" ls_after_rename ls_after_rename || ls_after_rename="no"
    [ "$ls_after_rename" = "yes" ] && print && zc-ls
}

function __convey_usage_zc-take() {
    pinfo2 "Takes a name for current Zsh session, i.e. takes it away from any other session if needed"
    pinfo2 "You can take a name for other session (not the current one) if -i or -n is provided"
    pinfo "Usage: zc-take [-i ID|-n NAME] [-q|--quiet] [-h|--help] NEW_NAME"
    print -- "-h/--help                - this message"
    print -- "-i ID / --id ID          - ID (number) of Zsh session"
    print -- "-n NAME / --name NAME    - NAME of Zsh session"
    print -- "-q/--quiet               - don't output status messages"
}

function zc-take() {
    setopt localoptions extendedglob clobber

    local -A opthash
    zparseopts -E -D -A opthash h -help q -quiet i: -id: n: -name: || { __convey_usage_zc-rename; return 1; }

    integer have_id=0 have_name=0 quiet=0
    local id name new_name="$1"

    # Help
    (( ${+opthash[-h]} + ${+opthash[--help]} )) && { __convey_usage_zc-take; return 0; }
    [ -z "$new_name" ] && { echo "No new name given"; __convey_usage_zc-take; return 1; }

    # ID
    have_id=$(( ${+opthash[-i]} + ${+opthash[--id]} ))
    (( ${+opthash[-i]} )) && id="${opthash[-i]}"
    (( ${+opthash[--id]} )) && id="${opthash[--id]}"

    # NAME
    have_name=$(( ${+opthash[-n]} + ${+opthash[--name]} ))
    (( ${+opthash[-n]} )) && name="${opthash[-n]}"
    (( ${+opthash[--name]} )) && name="${opthash[--name]}"

    # QUIET
    (( quiet = ${+opthash[-q]} + ${+opthash[--quiet]} ))

    if [[ "$have_id" != "0" && "$have_name" != "0" ]]; then
        pinfo "Please supply only one of ID (-i) and NAME (-n)"
        return 1
    fi

    if [[ "$have_id" != "0" && ( "$id" != <-> || "$id" = "0" ) ]]; then
        pinfo "ID must be numeric, 1..100"
        return 1
    fi

    # Rename via NAME?
    if (( $have_name )); then
        __convey_resolve_name_to_id "$name"
        local resolved="$REPLY"
        if [ -z "$resolved" ]; then
            echo "Could not find session named: \`$name'"
            return 1
        fi

        # Store the resolved ID and continue normally,
        # with ID as the main specifier of session
        id="$resolved"
    elif (( $have_id == 0 )); then
        id="$ZCONVEY_ID"
    fi

    if [[ "$id" != <-> || "$id" = "0" ]]; then
        pinfo "Bad ID ($id), aborting"
        return 1
    fi

    if [[ "$id" -gt "100" ]]; then
        pinfo "Maximum nr of sessions is 100, aborting"
        return 1
    fi

    __convey_resolve_name_to_id "$new_name"
    local other_id="$REPLY"
    if [ -n "$other_id" ]; then
        # The new name exist in system - find an
        # altered name that doesn't exist in system
        # and rename conflicting session, so that
        # $new_name is free
        integer counter=1
        local subst_name
        while (( 1 )); do
            counter+=1
            subst_name="${new_name}${counter}"
            __convey_resolve_name_to_id "$subst_name"
            if [ -z "$REPLY" ]; then
                # Found a name that doesn't exist in system, assign
                # it to the initial conflicting session $new_name
                print ":$subst_name:" > "$ZCONVEY_NAMES_DIR"/"$other_id".name

                (( ${quiet} == 0 )) && pinfo "Pre-rename: $new_name -> $subst_name"

                break
            fi
        done
    fi

    print ":$new_name:" > "$ZCONVEY_NAMES_DIR"/"$id".name

    if (( ${quiet} == 0 )); then
        pinfo2 "Renamed session $id to: $new_name"
    fi

    local ls_after_rename
    zstyle -b ":plugin:zconvey" ls_after_rename ls_after_rename || ls_after_rename="no"
    [ "$ls_after_rename" = "yes" ] && print && zc-ls
}

function __convey_usage_zc() {
    pinfo2 "Sends specified commands to given (via ID or NAME) Zsh session"
    pinfo "Usage: zc {-i ID}|{-n NAME} [-q|--quiet] [-v|--verbose] [-h|--help]"
    print -- "-h/--help                - this message"
    print -- "-i ID / --id ID          - ID (number) of Zsh session"
    print -- "-n NAME / --name NAME    - NAME of Zsh session"
    print -- "-q/--quiet               - don't output status messages"
    print -- "-v/--verbose             - output more status messages"
}

function zc() {
    setopt localoptions extendedglob clobber

    local -A opthash
    zparseopts -D -A opthash h -help q -quiet v -verbose i: -id: n: -name: zs -zshselect || { __convey_usage_zc; return 1; }

    integer have_id=0 have_name=0 verbose=0 quiet=0 zshselect=0
    local id name

    # Help
    (( ${+opthash[-h]} + ${+opthash[--help]} )) && { __convey_usage_zc; return 0; }

    # ID
    have_id=$(( ${+opthash[-i]} + ${+opthash[--id]} ))
    (( ${+opthash[-i]} )) && id="${opthash[-i]}"
    (( ${+opthash[--id]} )) && id="${opthash[--id]}"

    # NAME
    have_name=$(( ${+opthash[-n]} + ${+opthash[--name]} ))
    (( ${+opthash[-n]} )) && name="${opthash[-n]}"
    (( ${+opthash[--name]} )) && name="${opthash[--name]}"

    # ZSH-SELECT (for acquiring ID)
    (( zshselect = ${+opthash[-zs]} + ${+opthash[--zshselect]} ))

    # VERBOSE, QUIET
    (( verbose = ${+opthash[-v]} + ${+opthash[--verbose]} ))
    (( quiet = ${+opthash[-q]} + ${+opthash[--quiet]} ))

    if [[ "$have_id" != "0" && "$have_name" != "0" ]]; then
        pinfo "Please supply only one of ID (-i) and NAME (-n)"
        return 1
    fi

    if [[ "$have_id" != "0" && "$id" != <-> ]]; then
        pinfo "ID must be numeric, 1..100"
        return 1
    fi

    if [[ "$have_id" = 0 && "$have_name" = "0" && "$zshselect" = "0" ]]; then
        pinfo "Either supply target ID/NAME or request Zsh-Select (-zs/--zshselect)"
        return 1
    fi

    if (( $have_name )); then
        __convey_resolve_name_to_id "$name"
        local resolved="$REPLY"
        if [ -z "$resolved" ]; then
            echo "Could not find session named: \`$name'"
            return 1
        fi

        # Store the resolved ID and continue normally,
        # with ID as the main specifier of session
        id="$resolved"
    elif (( $zshselect )); then
        if ! type zsh-select 2>/dev/null 1>&2; then
            pinfo "Zsh-Select not installed, please install it first, aborting"
            return 1
        else
            export ZSELECT_START_IN_SEARCH_MODE=0
            id=`zc-ls | zsh-select`
            if [ -z "$id" ]; then
                pinfo "No selection, exiting"
                return 0
            else
                id="${id//(#b)*ID: ([[:digit:]]#)[^[:digit:]]#*(#e)/$match[1]}"
            fi
        fi
    fi

    local fd datafile="${ZCONVEY_IO_DIR}/${id}.io"
    local lockfile="${datafile}.lock"
    echo "PID $$ ID $ZCONVEY_ID is sending command" > "$lockfile"

    # 1. Zsh lock with timeout (2 seconds)
    if (( ${ZCONVEY_CONFIG[use_zsystem_flock]} > 0 )); then
        (( ${verbose} )) && print "Will use zsystem flock..."
        if ! zsystem flock -t 2 -f fd "$lockfile"; then
            pinfo2 "Communication channel of session $id is busy, could not send"
            return 1
        fi
    # 2. Provided flock binary (two calls)
    else
        (( ${verbose} )) && print "Will use provided flock..."
        exec {fd}>"$lockfile"
        "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$fd"
        if [ "$?" = "101" ]; then
            (( ${verbose} )) && print "First attempt failed, will retry..."
            LANG=C sleep 1
            "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$fd"
            if [ "$?" = "101" ]; then
                pinfo2 "Communication channel of session $id is busy, could not send"
                return 1
            fi
        fi
    fi

    # >> - multiple commands can be accumulated
    print -r -- "$*" >> "$datafile"

    # Release the lock by closing the lock file
    exec {fd}>&-

    if (( ${quiet} == 0 )); then
        pinfo2 "Zconvey successfully sent command to session $id"
    fi

}

function zc-ls() {
    setopt localoptions extendedglob clobber
    integer idx is_locked
    local idfile tmpfd name busyfile busywith

    for (( idx = 1; idx <= 100; idx ++ )); do
        idfile=""
        tmpfd=""
        name=""
        busywith=""
        is_locked=0

        if [ -e "$ZCONVEY_LOCKS_DIR/zsh_nr${idx}" ]; then
            idfile="$ZCONVEY_LOCKS_DIR/zsh_nr${idx}"
        fi

        if [ -n "$idfile" ]; then
            # Use zsystem only if non-blocking call is available (Zsh >= 5.3)
            if [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "1" ]; then
                zsystem flock -t 0 -f tmpfd "$idfile"
                res="$?"
            else
                exec {tmpfd}>"$idfile"
                "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$tmpfd"
                res="$?"
            fi

            is_locked=0
            if [[ "$res" = "101" || "$res" = "1" || "$res" = "2" ]]; then
                is_locked=1
            fi

            # Close the lock immediately
            [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "1" ] && zsystem flock -u "$tmpfd" || exec {tmpfd}>&-
            tmpfd=""
        fi

        __convey_get_name_of_id "$idx"
        name="$REPLY"

        busyfile="$ZCONVEY_OTHER_DIR/${idx}.busy"
        [[ -e "$busyfile" && "$idx" != "$ZCONVEY_ID" ]] && busywith=" \033[1;33m(BUSY: $(<$busyfile))\033[0m"

        if [[ "$is_locked" = "0" && -n "$name" ]]; then
            print "\033[1;31m(ABSENT)\033[0m  ID: $idx, NAME: $name"
        elif [[ "$is_locked" = "0" && -z "$name" ]]; then
            # Don't inform about absent, nameless sessions
            :
        elif [[ "$is_locked" = "1" && -z "$name" ]]; then
            if [ "$idx" = "$ZCONVEY_ID" ]; then
                print "\033[1;32m\033[4m(CURRENT) ID: $idx\033[0m$busywith"
            else
                print "\033[1;33m(ON-LINE)\033[0m ID: $idx$busywith"
            fi
        elif [[ "$is_locked" = "1" && -n "$name" ]]; then
            if [ "$idx" = "$ZCONVEY_ID" ]; then
                print "\033[1;32m\033[4m(CURRENT) ID: $idx, NAME: $name\033[0m$busywith"
            else
                print "\033[1;33m(ON-LINE)\033[0m ID: $idx, NAME: $name$busywith"
            fi
        fi
    done
}

function zc-id() {
    __convey_get_name_of_id "$ZCONVEY_ID"
    if [ -z "$REPLY" ]; then
        print "This Zshell's ID: \033[1;33m<${ZCONVEY_ID}>\033[0m (no name assigned)";
    else
        print "This Zshell's ID: \033[1;33m<${ZCONVEY_ID}>\033[0m, name: \033[1;33m${REPLY}\033[0m";
    fi
}

# Prints a graphical "logo" with ID and NAME
function zc-id-logo() {
    setopt localoptions extendedglob

    integer halfl=$(( LINES / 2 )) halfc=$(( COLUMNS / 2 ))
    integer hlen tlen
    local text headerline=" Zconvey" headerline2=""

    __convey_get_name_of_id "$ZCONVEY_ID"
    if [ -z "$REPLY" ]; then
        text="ID: <$ZCONVEY_ID> NAME: (no name assigned)"
    else
        text="ID: <$ZCONVEY_ID> NAME: $REPLY"
    fi
    tlen="${#text}"
    hlen=tlen+4
    headerline="${(r:hlen:: :)headerline}"
    headerline="${headerline/Zconvey/\033[1;34mZconvey\033[0m\033[1;44m}"
    headerline2="${(r:hlen:: :)headerline2}"
    text="${text/(#b)(<[[:digit:]]#>)/\033[1;32m${match[1]}\033[1;33m}"
    text="${text/(#b)NAME: (?#)/NAME: \033[1;32m${match[1]}\033[0m}"

    [ "$1" != "echo" ] && {
        echotc sc
        echotc cm $(( halfl - 3 )) $(( halfc - hlen/2 ))
        print -n "\033[1;44m$headerline\033[0m"
        echotc cm $(( halfl - 2 )) $(( halfc - hlen/2 ))
        print -n "\033[1;44m \033[0m \033[1;33m$text\033[0m \033[1;44m \033[0m"
        echotc cm $(( halfl - 1 )) $(( halfc - hlen/2 ))
        print -n "\033[1;44m$headerline2\033[0m"
        echotc rc
    } || {
        print "\033[1;44m$headerline\033[0m\n\033[1;44m \033[0m \033[1;33m$text\033[0m \033[1;44m \033[0m\n\033[1;44m$headerline2\033[0m"
    }
}

#
# Load configuration
#

() {
    setopt localoptions extendedglob
    typeset -gA ZCONVEY_CONFIG

    local check_interval
    zstyle -s ":plugin:zconvey" check_interval check_interval || check_interval="2"
    [[ "$check_interval" != <-> ]] && check_interval="2"
    ZCONVEY_CONFIG[check_interval]="$check_interval"

    local use_zsystem_flock
    zstyle -b ":plugin:zconvey" use_zsystem_flock use_zsystem_flock || use_zsystem_flock="yes"
    [ "$use_zsystem_flock" = "yes" ] && use_zsystem_flock="1" || use_zsystem_flock="0"
    ZCONVEY_CONFIG[use_zsystem_flock]="$use_zsystem_flock"

    local greeting
    zstyle -s ":plugin:zconvey" greeting greeting || greeting="logo"
    [[ "$greeting" != "none" && "$greeting" != "text" && "$greeting" != "logo" ]] && greeting="logo"
    ZCONVEY_CONFIG[greeting]="$greeting"
}

#
# Compile myflock
#

# Binary flock command that supports 0 second timeout (zsystem's
# flock in Zsh ver. < 5.3 doesn't) - util-linux/flock stripped
# of some things, compiles hopefully everywhere (tested on OS X,
# Linux).
if [ ! -e "${ZCONVEY_REPO_DIR}/myflock/flock" ]; then
    echo "\033[1;35m""psprint\033[0m/\033[1;33m""zconvey\033[0m is building small locking command for you..."
    make -C "${ZCONVEY_REPO_DIR}/myflock"
fi

# A command that feeds data to command line, via TIOCSTI ioctl
if [ ! -e "${ZCONVEY_REPO_DIR}/feeder/feeder" ]; then
    echo "\033[1;35m""psprint\033[0m/\033[1;33m""zconvey\033[0m is building small command line feeder for you..."
    make -C "${ZCONVEY_REPO_DIR}/feeder"
fi

#
# Acquire ID
#

if [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "1" ]; then
    autoload is-at-least
    if ! is-at-least 5.3; then
        # Use, but not for acquire
        ZCONVEY_CONFIG[use_zsystem_flock]="2"
    fi

    if ! zmodload zsh/system 2>/dev/null; then
        echo "Zconvey plugin: \033[1;31mzsh/system module not found, will use own flock implementation\033[0m"
        echo "Zconvey plugin: \033[1;31mDisable this warning via: zstyle \":plugin:zconvey\" use_zsystem_flock \"0\"\033[0m"
        ZCONVEY_CONFIG[use_zsystem_flock]="0"
    elif ! zsystem supports flock; then
        echo "Zconvey plugin: \033[1;31mzsh/system module doesn't provide flock, will use own implementation\033[0m"
        echo "Zconvey plugin: \033[1;31mDisable this warning via: zstyle \":plugin:zconvey\" use_zsystem_flock \"0\"\033[0m"
        ZCONVEY_CONFIG[use_zsystem_flock]="0"
    fi
fi

() {
    setopt localoptions extendedglob clobber

    integer idx try_id res
    local fd lockfile

    # Already assigned ID (inherited)?
    idx=0
    if [[ "$ZCONVEY_FD" = <-> && "$ZCONVEY_FD" != "0" && "$ZCONVEY_ID" = <-> && "$ZCONVEY_ID" != "0" ]]; then
        # Inherited FD and ID, no need to perform work
        if print -u "$ZCONVEY_FD" -n 2>/dev/null; then
            idx=101
        fi
    fi

    # Supported are 100 shells - acquire takes ~400ms max (zsystem's flock)
    for (( ; idx <= 100; idx ++ )); do
        # First (at first loop) try with $ZCONVEY_ID (the case of inherited ID)
        [[ "$idx" = "0" && "$ZCONVEY_ID" = <-> ]] && try_id="$ZCONVEY_ID" || try_id="$idx"
        [[ "$try_id" = "0" ]] && continue

        lockfile="${ZCONVEY_LOCKS_DIR}/zsh_nr${try_id}"
        echo "Lock done by Zsh (PID $$)" > "$lockfile"

        # Use zsystem only if non-blocking call is available (Zsh >= 5.3)
        # -e: preserve file descriptor on exec
        if [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "1" ]; then
            zsystem flock -t 0 -f ZCONVEY_FD -e "$lockfile"
            res="$?"
        else
            exec {ZCONVEY_FD}>"$lockfile"
            "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$ZCONVEY_FD"
            res="$?"
        fi

        if [[ "$res" = "101" || "$res" = "1" || "$res" = "2" ]]; then
            [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" != "1" ] && exec {ZCONVEY_FD}>&-

            # Is this the special case, i.e. inherition of ZCONVEY_ID?
            # In this case being unable to lock means: we already have
            # that lock, we're at our ZCONVEY_ID, we should use it
            # (process cannot lock files locked by itself, too)
            if [[ "$idx" = "0" ]]; then
                # Export again just to be sure
                export ZCONVEY_ID
                # We will not be able and want to close FD on zshexit
                export ZCONVEY_FD=0
                break
            fi
        else
            # Successful locking in the special case (try_id = ZCONVEY_ID,
            # i.e. idx == 0) means: we don't want to have that lock because
            # it's not inherited (i.e. not already locked by ourselves)
            if [[ "$idx" = "0" ]]; then
                # Release the out of order lock
                exec {ZCONVEY_FD}>&-
                # We will not be able to quick-close FD on zshexit
                ZCONVEY_FD=0
            else
                ZCONVEY_ID=try_id
                # ID and FD will be inherited by subshells and exec zsh calls
                export ZCONVEY_ID
                export ZCONVEY_FD
                break
            fi
        fi
    done

    # Show what is resolved (ID and possibly a NAME)
    [ "$ZCONVEY_CONFIG[greeting]" = "logo" ] && zc-id-logo echo
    [ "$ZCONVEY_CONFIG[greeting]" = "text" ] && zc-id
}

#
# Function to check for input commands
#

function __convey_on_period_passed() {
    # Reschedule as quickly as possible - user might
    # press Ctrl-C when function is executing
    #
    # Reschedule only if this scheduling sequence
    # comes from approved single origin
    [[ "$ZCONVEY_SCHEDULE_ORIGIN" = "$1" ]] && sched +"${ZCONVEY_CONFIG[check_interval]}" __convey_on_period_passed "$ZCONVEY_SCHEDULE_ORIGIN"

    # Remember when the command was run to detect a possible
    # fail in schedule (because of unlucky Ctrl-C press)
    ZCONVEY_RUN_SECONDS="$SECONDS"

    # ..and block Ctrl-C, this function will not
    # stall, no reason for someone to use Ctrl-C
    setopt localtraps; trap '' INT
    setopt localoptions extendedglob clobber

    local fd datafile="${ZCONVEY_IO_DIR}/${ZCONVEY_ID}.io"
    local lockfile="${datafile}.lock"

    # Quick return when no data
    [ ! -e "$datafile" ] && return 1

    # Prepare the lock file, follows locking it
    echo "PID $$ ID $ZCONVEY_ID is reading commands" > "$lockfile"

    # 1. Zsh 5.3 flock that supports timeout 0 (i.e. can be non-blocking)
    if [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "1" ]; then
        if ! zsystem flock -t 0 -f fd "$lockfile"; then
            LANG=C sleep 0.11
            if ! zsystem flock -t 0 -f fd "$lockfile"; then
                # Examine the situation by waiting long
                LANG=C sleep 0.11
                if ! zsystem flock -t 0 -f fd "$lockfile"; then
                    # Waited too long, lock must be broken, remove it
                    command rm -f "$lockfile"
                    # Will handle this input at next call
                    return 1
                fi
            fi
        fi
    # 2. Zsh < 5.3 flock that isn't non-blocking
    elif [ "${ZCONVEY_CONFIG[use_zsystem_flock]}" = "2" ]; then
        if ! zsystem flock -t 1 -f fd "$lockfile"; then
            # Waited too long, lock must be broken, remove it
            command rm -f "$lockfile"
            # Will handle this input at next call
            return 1
        fi
    # 3. Provided flock binary
    else
        exec {fd}>"$lockfile"
        "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$fd"
        if [ "$?" = "101" ]; then
            LANG=C sleep 0.11
            "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$fd"
            if [ "$?" = "101" ]; then
                # Examine the situation by waiting long
                sleep 1
                "${ZCONVEY_REPO_DIR}/myflock/flock" -nx "$fd"
                if [ "$?" = "101" ]; then
                    # Waited too long, lock must be broken, remove it
                    command rm -f "$lockfile"
                    # Will handle this input at next call
                    return 1
                fi
            fi
        fi
    fi

    local -a commands
    commands=( "${(@f)"$(<$datafile)"}" )
    command rm -f "$datafile"
    exec {fd}>&-

    local concat_command="${(j:; :)commands[@]}"
    if [[ -o interactive_comments ]]; then
        concat_command+=" ##"
    fi
    "${ZCONVEY_REPO_DIR}/feeder/feeder" "$concat_command"

    # Tried: zle .kill-word, .backward-kill-line, .backward-kill-word,
    # .kill-line, .vi-kill-line, .kill-buffer, .kill-whole-line

    return 0
}

#
# Preexec hooks
#

# A hook:
# - detecting failure in re-scheduling
# - marking the shell as busy
__convey_preexec_hook() {
    # No periodic run for a long time -> schedule
    if (( SECONDS - ZCONVEY_RUN_SECONDS >= 4 )); then
        # Simulate that __convey_on_period_passed was just
        # ran and did re-schedule
        ZCONVEY_RUN_SECONDS="$SECONDS"

        # Schedule with new schedule origin - any duplicate
        # scheduling sequence will be quickly eradicated
        ZCONVEY_SCHEDULE_ORIGIN="$SECONDS"
        sched +"${ZCONVEY_CONFIG[check_interval]}" __convey_on_period_passed "$ZCONVEY_SCHEDULE_ORIGIN"

        pinfo "Failure in reschedule detected"
    fi

    # Mark that the shell is busy
    print -r -- "${1[(w)1]}" >! "$ZCONVEY_OTHER_DIR/${ZCONVEY_ID}.busy"
}

# A hook marking the shell as not busy
__convey_precmd_hook() {
    command rm -f "$ZCONVEY_OTHER_DIR/${ZCONVEY_ID}.busy"
}

#
# Schedule, other
#

# Not called ideally at say SIGTERM, but
# at least when "exit" is enterred
function __convey_zshexit() {
    [[ "$ZCONVEY_FD" != "0" && "$SHLVL" = "1" ]] && exec {ZCONVEY_FD}>&-
}

if ! type sched 2>/dev/null 1>&2; then
    if ! zmodload zsh/sched 2>/dev/null; then
        echo "Zconvey plugin: \033[1;31mzsh/sched module not found, Zconvey cannot work with this Zsh build, aborting\033[0m"
        return 1
    fi
fi

ZCONVEY_SCHEDULE_ORIGIN="$SECONDS"
sched +"${ZCONVEY_CONFIG[check_interval]}" __convey_on_period_passed "$ZCONVEY_SCHEDULE_ORIGIN"
autoload -Uz add-zsh-hook
add-zsh-hook zshexit __convey_zshexit
add-zsh-hook preexec __convey_preexec_hook
add-zsh-hook precmd __convey_precmd_hook

zle -N zc-id-logo
bindkey '^O^I' zc-id-logo
