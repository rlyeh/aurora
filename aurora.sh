#!/bin/bash
#
# Aurora: "A utility:  remote operations,  remote access"
#          Really though, I named it after my dog Aurora 
#          (who we call "Ro" for short).
#
#          Author: rlyeh@reillyhayes.com
#
#          Please see the README FILE
#
# Add the following line to the top of your bashrc:
#
# [[ -z "$_RO_ENV" ]] || source aurora.sh ;  ro_init 
#

ro_env() {
  # called by ro_init 
  local \
      srcpath

  # We export everything important.  Only run once
  if [[ -n "$_RO_ENV" ]] ; then 
    return 0
  else
    typeset -x -r _RO_ENV=YES
  fi

  split_to_vars - - srcpath "$(caller)"
  
  : ${EMACS_SERVER_LOCAL_NAME:=server}
    # Extract components from EMACS_SERVER_FILE if available
  if [[ -n "$EMACS_SERVER_FILE" ]] ; then 
    export EMACS_SERVER_NAME=$(basename "$EMACS_SERVER_FILE")
    if [[ "${EMACS_SERVER_FILE}" == "${EMACS_SERVER_NAME}" ]] ; then
      echo "Warning: EMACS_SERVER_FILE has no directory component."
    else
      if [[ -z "${EMACS_SERVER_AUTH_DIR}" ]] ; then
        export EMACS_SERVER_AUTH_DIR=$(dirname "$EMACS_SERVER_FILE")
      else
        if [[ ! "${EMACS_SERVER_AUTH_DIR}" -ef \
            $(dirname "$EMACS_SERVER_FILE") ]] ; then 
          echo "Warning:"
          echo "  EMACS_SERVER_AUTH_DIR and EMACS_SERVER_FILE are inconsistent:"
          echo "  EMACS_SERVER_FILE=${EMACS_SERVER_FILE}"
          echo "  EMACS_SERVER_AUTH_DIR=${EMACS_SERVER_AUTH_DIR}"
        fi
      fi
    fi
  fi
    
    # A reasonable default
  : ${EMACS_SERVER_AUTH_DIR:=~/.emacs.d/server}
  : ${EMACS_SERVER_NAME:=${EMACS_SERVER_LOCAL_NAME}}
  : ${EMACSCLIENT:=$(which emacsclient)}
  : ${RO_TMPDIR:=/tmp}
  export RO_TMPDIR
  export EMACS_SERVER_AUTH_DIR EMACS_SERVER_FILE EMACS_SERVER_NAME 
  export EMACS_SERVER_LOCAL_NAME EMACSCLIENT
}
export -f ro_env

ro_init() {
  # ro_init must be called once per bash invocation
  ro_env

  [[ -z "$EMACS_SERVER_FILE" ]] && ro_use 

  if [[ -n "$STY" ]] && [[ -n "$PS1" ]]; then 
    echo $$ >>${RO_TMPDIR}/${STY}-bashpids
    trap _ro_reset_server_display INFO
  fi
}
export -f ro_init

_ro_reset_server_display() {
  local \
    server \
    display \
    dataline 
  # If we get this trap, make sure it's for us.
  if [[ -n "$STY" ]] && [[ -r "${RO_TMPDIR}/${STY}-emacsserver" ]] ; then 
    dataline=$(tail -n 1 "${RO_TMPDIR}/${STY}-emacsserver")
    server="${dataline#}"
    if [[ -n "$server" ]]; then
      export EMACS_SERVER_FILE="$server"
    else
      unset EMACS_SERVER_FILE EMACS_SERVER_NAME
    fi
  fi

  if [[ -n "$STY" ]] && [[ -r "${RO_TMPDIR}/${STY}-display" ]] ; then 
    dataline=$(tail -n 1 "${RO_TMPDIR}/${STY}-display")
    display="${dataline}"
    if [[ -n "$display" ]]; then
      export DISPLAY="$display"
    else
      unset DISPLAY
    fi
  fi
}
export -f _ro_reset_server_display

split_to_vars() {
  # Split the string provided as the final argument into tokens/words per IFS.
  # Assign these tokens to to variables named in argument list according to
  # the variable's position in the argument list (first arg names the variable
  # that will have the first token assigned to it as a value).
  # Skip the token if the corresponding argument is a dash (-).  
  # An argument of underscore (_) indicates that the remaining variables
  # should align with the end of the token list (if there are 3 variables
  # named after _, they will be assigned the last-2, last-1, and last tokens).
  # Finally, a __ indicate that all of the remaining tokens should be assigned
  # to the next named variable.  The tokens will be separated by the first char
  # of IFS or delimiter that optionally follows the variable name. 
  #
  # split a b c "one two three four"
  # Assigns "one" to $a, "two" to $b, "three" to $c
  # 
  # split a - - b "one two three four"
  # Assigns "one" to $a, "four" to $b
  #
  # split a - - b "one two three"
  # Assigns "one" to $a, $b is unset 
  #
  # split _ a b "one two three four"
  # Assigns "three" to $a, "four" to $b
  #
  # split _ a b c "one two" 
  # $a is unset, assigns "one" to $b, "two" to $c 
  #
  # split a __ b "one two three four"
  # Assigns "one" to $a, "two three four" to $b
  #
  # split a __ b \: "one two three four"
  # Assigns "one" to $a, "two:three:four" to $b
  #


  
  local \
      evalstr \
      delim="${IFS:0:1}"
  local -i  \
      ind=0 \
      itemcount 
  local -a \
      parray

  # We need last arg parsed into array prior to shifting thru arg list
  # Annoyingly, there's no parameter indirection on numeric params ($1)
  eval "parray=(\$${#})"
  # We need the number of items for counting back from end of list 
  itemcount=${#parray[@]}

  while [[ $# -gt  1 ]] ; do
    if [[ "$1" == "__" ]] ; then 
      # __ remaining values packed into next named variable, if there is one.
      shift 
      # break if the only arg left is the string to parse.  No-op, not error
      [[ $# -lt 2 ]] && break 

      # start the assignment expression
      evalstr+="$1=\"" ; shift 
      
      # look for the optional delimiter (by arg count)
      [[ $# -gt 1 ]] && delim="$1" && shift 

      # loop through values from current index to end of array
      for (( ; $ind<$itemcount ; ind++)) ; do 
        # Add item to this assignment
        evalstr+="\${parray[$ind]}"
        # if there's a next one, add a delimiter
        [[ $(($itemcount-$ind)) -gt 1 ]] && evalstr+="$delim"
      done
      # Close the assignment
      evalstr+="\" "
    elif [[ "$1" == "_" ]] ; then 
      # adjust ind so remaining vars assign to ..., last-2, last-1, last 
      ind=$itemcount+1-$#
    elif [[ "$1" != "-" ]] ; then
      # Unset var in case we don't set it (string may not have enough tokens)
      unset $1
      # Be sure the assignment is to an actual value
      [[ $ind -ge 0 ]] && [[ $ind -lt $itemcount ]] && evalstr+="$1=\"\${parray[$ind]}\" "
    fi
    shift ; ind+=1
  done

  # execute the assignments
  eval $evalstr
}
export -f split_to_vars

_ro_send_server_data() {
    # When we re-attach to a screen session, we may need to update the DISPLAY
    # and EMACS_SERVER_FILE variables (we may be ssh'd in from a different
    # node). We add them to the end of files named after the screen session
    # name and then send a trap to our bash shells.
    local \
        post_file=${RO_TMPDIR}/$$-sty \
        target_sty

    # It's remarkably hard to get these to resolve in all the right places
    # without additional helper scripts, etc.  I'm still not happy with this
    # I can get rid of the POST_FILE by writing the emacserver and display
    # files in a temporary screen.  Not sure this is best.
    screen "$@" -X eval \
        "setenv DISPLAY $DISPLAY" \
        "setenv EMACS_SERVER_FILE $EMACS_SERVER_FILE" \
        "setenv POST_FILE $post_file" \
        "screen bash -c 'echo \$STY >\${POST_FILE}'"
    
    # let's check for a race condition, just in case
    until [[ -r "${post_file}" ]] ; do
        sleep 1
    done
        
    target_sty=$(cat "${post_file}")

    echo $DISPLAY >>${RO_TMPDIR}/${target_sty}-display
    echo $EMACS_SERVER_FILE >>${RO_TMPDIR}/${target_sty}-emacsserver

    # interactive shells that see the STY variable register themselves
    for shell_pid in $(cat ${RO_TMPDIR}/${target_sty}-bashpids) ; do
        # Tell them to read the files
        kill -INFO $shell_pid 2>/dev/null
    done
    echo $target_sty
}
export -f _ro_send_server_data

ro_screen() {
    # Are we gonna have to parse screen command input?
    # doesn't seem so.
    send-server-data "$@"
    screen "$@"
}
export -f ro_screen
  
ro_ssh() {
  local host=$1
  shift
  ssh -t $host screen -a -q "$@"
}
export -f ro_ssh

_ro_discover_controlling_display () {
  # Try to discover information about the controlling display without relying
  # on DISPLAY or EMACS_SERVER_FILE.  Primarily uses "who -m", which is fairly
  # useless on Darwin (OS X)
    local \
        whostring \
        scratch \
        controlling \
        screen_num \
        display \
        host \
        tty \

    whostring="$(who -m)" 
    scratch="${whostring#*\(}"
    controlling="${scratch%\)*}"
    split_to_vars user tty "$whostring" 
    
    if [[ $(uname -s) == "Linux" ]]; then 
        scratch=${controlling##*\:S\.}
        if [[ "${scratch}" != "{$controlling}" ]] ; then 
            controlling=${controlling%\:S\.*}
            screen_num="$scratch"
        else
            screen_num=""
        fi
        
        scratch=${controlling##*\:}
        if [[ "${scratch}" != "{$controlling}" ]] ; then 
            display=${controlling}
            controlling=${controlling%\:*}
        else
            display=""
        fi
        if [[ -n "$controlling}" ]]; then
            host="${controlling}"
        else
            host=$(uname -n)
        fi
        _ro_names_for_ip $host 
    fi
    echo "$host,$tty,$display,$screen_num"
}
export -f _ro_discover_controlling_display

_ro_server_file_name() {
    # return a full path to server file given a partial (name only) or 
    # pull path name
    if [[ $(basename "$1") == "$1" ]] ; then 
        echo "${EMACS_SERVER_AUTH_DIR}/${1}"
    else
        echo "$1"
    fi
}
export -f _ro_server_file_name

_ro_check_for_active_server() {
    local \
        server_file=$(_ro_server_file_name "$1") \
        ipv4regex='[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+' \
        host \
        port
        
    if [[ ! -r "$server_file" ]] ; then
        # No such file 
        return 1
    else
        IFS=": " split_to_vars host port "$(head -1 $server_file)" 
        if [[ "$host" =~ ${ipv4regex} ]] ; then
            ip="${host}"
        else
            ip=$(dig +search +short $host | tail -1)
        fi
        
        if netstat -l -t -n | fgrep -q $ip:$port ; then 
            return 0
        else
        # Nobody is listening.  OR the emacs server is actually remote and
        # not tunneled.  I don't want to support this case.
            return 3 # No active tunnel 
        fi
    fi
}
export -f _ro_check_for_active_server

ro_cleanup_tunnels() {
    for file in ${EMACS_SERVER_AUTH_DIR}/*; do
        if ! _ro_check_for_active_server $file; then 
            echo rm $file
            rm "$file"
            if [[ -f "${EMACS_SERVER_AUTH_DIR}/ipmap/${file%%*/}" ]] ;then
              echo rm "${EMACS_SERVER_AUTH_DIR}/ipmap/${file%%*/}"
              rm "${EMACS_SERVER_AUTH_DIR}/ipmap/${file%%*/}"
            fi
        fi
    done
}
export -f ro_cleanup_tunnels

_ro_ipv4_p () {
    local \
        ipv4regex='^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$'
    [[ "$1" =~ $ipv4regex ]]
}
export -f _ro_ipv4_p

_ro_bonjour_p () {
    local \
        mdnsregex='^([[:alnum:]\_\-]+)\.local[.]?$'
    [[ "$1" =~ $mdnsregex ]]
}
export -f _ro_bonjour_p

_ro_dns_p () {
    local \
        dnsregex='^([[:alnum:]\_\-]+\.)+[[:alnum:]\_\-]+[.]?$'
    [[ "$1" =~ $dnsregex ]] && ! _ro_bonjour_p "$1" && ! _ro_ipv4_p "$1"
}
export -f _ro_dns_p

_ro_host_p () {
    local \
        hostregex='^[[:alnum:]\_\-]+$'
    [[ "$1" =~ $hostregex ]]
}
export -f _ro_host_p

# Darwin: scutil -r name | fgrep -q -e "Local Address"
# will return true if the name is this machine

_ro_node_self_p() {
    local host=$1
    
    if _ro_host_p "$host" ; then
        :
    fi
    if _ro_ipv4_p $host; then
        if [[ "$host" == "127.0.0.1" ]] ; then
            return 0
        elif ifconfig -a | fgrep -q -e "$1" ; then 
            return 0
        elif [[ "$(dig +short -x $host)" == "$(uname -n)." ]] ; then
            return 0
            # too dependent on external services
        else
            return 1
        fi
    fi
}
export -f _ro_node_self_p


_ro_server_names_for_host () {
    local \
        host="$1"

    # Check for a bunch of variations on THIS HOST
        
    if [[ "$servername" == "127.0.0.1" ]] || 
       [[ "$servername" == "$SHORTHOST" ]] ||
       [[ "$servername" == "$HOSTNAME" ]] ; then 
        
      echo ${EMACS_SERVER_LOCAL_NAME}
      return 0
    fi
    if [[ -d "$EMACS_SERVER_AUTH_DIR/ipmap" ]] ; then
        for file in $EMACS_SERVER_AUTH_DIR/ipmap/* ; do
            if fgrep -q $1 $file ; then
                servername=${file%%*/}
                if _ro_check_for_active_server $servername; then 
                    aresult+=($servername)
                fi
            fi
        done
    fi
    echo ${aresult[@]}
}
export -f _ro_server_names_for_host

ro_describe_emacs() {
  local \
      esf=$1 \
      disp=$2 \
      host=$3 \
      disp_regex='([[:alnum:]\-\_])+([\/\.])?'
  if [[ "${esf##*/esf}" == "$EMACS_SERVER_LOCAL_NAME" ]]; then
    desc="Local:$host" 
    if [[ -n "$disp" ]] && [[ "$disp" =~ $dispregex ]] ; then 
      disphost="${%\:*}"
      dispscr="${##*\:}"
      if [[ ${dispscr%\.*} -gt 0 ]] ; then 
        :
        # X is forwarded 
      else
        :
      fi
    fi
  fi
}
        
ro_use() {
    local \
        controlling_ip \
        remote_hosts
    declare -a remote_hosts 
    if [[ -n "$1" ]]; then
        remote_hosts=($1)
    elif [[ -n "$STY" ]] || [[ -n "$STY" ]] ; then
        remote_hosts=($_ro_controlling_host)
    elif [[ -n "$SHH_CONNECTION" ]] ; then 
        remote_hosts=($_ro_names_for_ip ${SSH_CONNECTION%% *})
    else
        export EMACS_SERVER_FILE=$EMACS_SERVER_AUTH_DIR/$EMACS_SERVER_LOCAL_NAME
        echo Using local Emacs server
        return 0
    fi

    if (( ${#remote_hosts[@]} == 1)) ; then
        echo Using Emacs server at ${remote_hosts[1]}
        export EMACS_SERVER_FILE=$EMACS_SERVER_AUTH_DIR/${remote_hosts[1]}
    elif (( ${#remote_hosts[@]} > 1)) ; then
        echo Multiple possible Emacs servers.
        echo ${remote_hosts[@]}
        return 1
    fi
}
export -f ro_use

_ro_rewrite_filename() {
    # We'll want to give this the option of not using tramp for files
    # on a share.  Lots of corner cases in that, however.
    case "$1" in
	\/*\:*) 
            # A filename already in TRAMP format.  Pass it on through
            echo "$1"
	    ;;
	\/*) 
            # An absolute filename.  Rewrite the filename to add the tramp
	    # host address formula /foo.corp.google.com:...
            echo "/${HOSTNAME}:$1"
            ;;
	*) 
            # A relative filename.  Rewrite the filename to add the current 
	    # working directory and add the tramp host address
            echo "/${HOSTNAME}:$PWD/$1"
	    ;;
    esac
}
export -f _ro_rewrite_filename

ro_emacs() {
  # Process the arguments and create an alternate version of the argument list
  # for emacs server connections tunneled through SSH.  File names need to be
  # rewritten to use tramp.  We rewrite the args up front because command line
  # switches will impact our decision as to which emacs server to use. It was
  # stupid to call this emacsclient.

  local \
      args4tunnel \
      takenext \
      varnext \
      evalstr \
      arg \
      dflag \
      emacs_server_file="$EMACS_SERVER_FILE" # we may override 
  
  declare -a args4tunnel
  declare -a args4local

  for arg in "$@" ; do

    if [[ -n "$varnext" ]] ; then
      unset evalstr 
      for var in $varnext ; do
        evalstr+="$var=\"$arg\" "
      done
      eval $evalstr
    fi

    [[ -n "$takenext" ]] && args4tunnel+=("$arg") args4local+=("$arg")

    [[ -n "${varnext}${takenext}" ]] && unset varnext takenext && break
    
    case "$arg" in
      -c|--create-frame) 
                # This switch creates a new frame by giving the remote emacs the
                # local DISPLAY variable.  If DISPLAY is not set, Linux emacsclient
                # decides terminal mode would be best (big lose, see below). But
                # The good news is that Darwin Emacs ignores what is sent to it.
                # so we add a DISPLAY arg of ":0.0" if DISPLAY is unset.
        if [[ -z "$DISPLAY" ]] ; then 
          args4tunnel+=("-d" ":0.0")
        fi
        args4tunnel+=("$arg")
	;;
      -t|--tty|-nw)
	        # Terminal mode.  Not compatible with remote emacsclient
        args4local+=("$arg")
	;;
      -e|--eval) 
                # Eval lisp code
        args4tunnel+=("$arg")
        takenext=yes ;;
      -d)
	        # Specify DISPLAY (in 2 word)
        args4tunnel+=("$arg")
        takenext=yes 
	;;
      --display=*)
        args4tunnel+=("$arg")
	        # Specify DISPLAY (in 1 word)
	;;
      -a) 
	        # Specify an alterative editor (in 2 words)
        args4tunnel+=("$arg")
        takenext=yes
	;;
      --alternate-editor=*)
	        # Specify an alterative editor (in 1 word)
        args4tunnel+=("$arg")
	;;
                # The next several switches redefine which server we're using.  
                # Tramp should be the safest (unless we're on a laptop that 
	        # doesn't support ssh in)
      -f)
	    # specify the server file (in 2 words)
        args4tunnel+=("$arg")
        takenext=yes
        varnext=emacs_server_file
	;;
      --server-file=*)
	    # specify the server file (in 1 word)
        emacs_server_file=${arg#--server-file=}
        args4tunnel+=("$arg")
	;;
      -s)
	    # specify the socket (named pipe) to use to talk to the 
	    # emacs server (in 2 words)
        args4tunnel+=("$arg")
        takenext=yes
	;;
      --socket*)
	    # specify the socket (named pipe) to use to talk to the 
	    # emacs server (in 1 word)
        args4tunnel+=("$arg")
	;;
      -*) 
            # Unknown or unexpected switch.  Pass it on and assume it takes no 
            # arguments
        args4tunnel+=("$arg") 
	;;
      \/*\:*) 
            # A filename already in TRAMP format.  Pass it on through
        args4tunnel+=("$arg") 
	;;
      \/*) 
            # An absolute filename.  Rewrite the filename to add the tramp
	    # host address formula /foo.corp.google.com:...
        args4tunnel+=("/${HOSTNAME}:$arg") 
	;;
      *) 
            # A relative filename.  Rewrite the filename to add the current 
	    # working directory and add the tramp host address
        args4tunnel+=("/${HOSTNAME}:$PWD/$arg") 
	;;
    esac
  done

  if  [[ $(basename "$emacs_server_file") != \
      "$EMACS_SERVER_LOCAL_NAME" ]]; then 
        # Access to EMACS_SERVER is tunneled through SSH.
        # We need to edit the command line to make this work
    
    echo Using tunnel: $EMACSCLIENT "${args4tunnel[@]}"
    $EMACSCLIENT "${args4tunnel[@]}"
  else 
    if [[ "$OSNAME" == "Linux" ]] && [[ -z "$DISPLAY" ]] ;  then
            # No display, so use terminal mode.
      dflag="-nw"
    else
            # Use the X display and make a new frame
      dflag="-c"
    fi
    echo "$EMACSCLIENT" $dflag "$@"
    "$EMACSCLIENT" $dflag "$@"
  fi
}
export -f ro_emacs

