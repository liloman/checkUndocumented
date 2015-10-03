#!/bin/bash 
#
# Parse command line commands options and search for undocumented
# options/commands in his manpage and bash autocompletion

#Version 0.1 Parse manpages and bash autocompletion options
#Version 0.2 Parse manpages and bash autocompletion verbs/commands

__version=0.2
MANPAGES=../man
BASH_AUTO=../shell-completion/bash

function generate_case_arg(){
local com
com=$1
for arg in $(get_options_type $com "arg")
do
    echo -n "
    $arg)
      comps=''
      ;;"
done
}

function get_options_type(){
local args com regex value
local regex
local -a arr

com=$1
type=$2

if [[ "$type" == "arg" ]];
then
    regex='([-[:alnum:]]*)(\[?)(=)'
else
    regex='([-[:alnum:]]*)'
fi

args=($(get_options $com))
[[ -z $args ]] && return

for num in $(seq 0 $((${#args[@]}-1))); 
do 
    value=${args[num]}
    # echo $value
    [[ $value =~ $regex ]] && arr=("${arr[@]}" "${BASH_REMATCH[1]}")
done
echo ${arr[@]}
}


function get_verbs_type(){
local args com regex value
local regex
local -a arr

com=$1
type=$2

if [[ "$type" == "standalone" ]];
then
    regex='([-[:alnum:]]*)(_NAME.*)$'
else
    regex='([-[:alnum:]]*)_[^NAME]'
fi

args=($(get_verbs $com "full"))
[[ -z $args ]] && return

for num in $(seq 0 $((${#args[@]}-1))); 
do 
    value=${args[num]}
    [[ $value =~ $regex ]] && arr=("${arr[@]}" "${BASH_REMATCH[1]}") 
    
done
echo ${arr[@]}
}

function generate_template(){
local com  output

com=$1
# mapfile output <<-EOF

cat <<-EOF
# $com(1) completion                                  -*- shell-script -*-
#
# This file is part of systemd.
#
# Copyright $(date +%Y) Carlos Morata Castillo <cmc809@inlumine.ual.es>
#
# systemd is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation; either version 2.1 of the License, or
# (at your option) any later version.
#
# systemd is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with systemd; If not, see <http://www.gnu.org/licenses/>.


_$com () {
local cur=\${COMP_WORDS[COMP_CWORD]} prev=\${COMP_WORDS[COMP_CWORD-1]}
local i verb comps

local -A OPTS=(
[STANDALONE]='$(get_options_type $com "standalone")'
[ARG]='$(get_options_type $com "arg")'
)

if __contains_word "\$prev" \${OPTS[ARG]}; then
    case \$prev in
        $(generate_case_arg $com)
    esac
COMPREPLY=( \$(compgen -W '\$comps' -- "\$cur") )
return 0
fi

if [[ "$cur" = -* ]]; then
    COMPREPLY=( $(compgen -W '${OPTS[*]}' -- "$cur") )
    return 0
fi

        local -A VERBS=(
           [STANDALONE]='$(get_verbs_type $com "standalone")'
           [FLAG]='$(get_verbs_type $com "flag")'
        )

        for ((i=0; i < COMP_CWORD; i++)); do
                if __contains_word "\${COMP_WORDS[i]}" \${VERBS[*]} &&
                 ! __contains_word "\${COMP_WORDS[i-1]}" \${OPTS[ARG]}; then
                        verb=\${COMP_WORDS[i]}
                        break
                fi
        done

        if   [[ -z \$verb ]]; then
                comps="\${VERBS[*]}"
        elif __contains_word "\$verb" \${VERBS[STANDALONE]}; then
                comps=''
        fi

        COMPREPLY=( \$(compgen -W '\$comps' -- "\$cur") )
        return 0
  }

complete -F _$com $com
EOF
}



function get_systemd_commands(){
local regex
regex='(root)?bin_PROGRAMS[[:space:]]?(\+?)=(.*)'

grep -E $regex ../Makefile.am -A 20 | while read a; do 
[[ $a =~ $regex ]] && echo ${BASH_REMATCH[3]}
done
}

function get_options(){
local com args arg value
com=$1
[[ ! $com ]] && return
hash $com 2>/dev/null || return 0

args=($($com -h))
for arg in $(seq 0 $((${#args[@]}-1))); 
do
    value=${args[arg]}
    if [[ $value == -* ]]; then
        echo $value
    fi
done
}

function get_verbs(){
local com regex_commands regex_verbs line arr found full 
com="$1 -h"
full=$2

regex_commands='^(.*)Commands:$'
regex_verbs='^([[:space:]]){1,2}([-[:alnum:]])(.*)'; 

while IFS= read -r line
do
    [[ "$line" =~ $regex_commands ]] && found=1 && continue
    if [[ $found ]]; 
    then
        if [[ "$line" =~ $regex_verbs ]]; 
        then
            arr=(${line//[[:space:]]/ })
            if [[ $full ]];
            then
                echo ${arr[0]}_${arr[1]}
            else
                echo ${arr[0]}
            fi
        fi
    fi
done < <($com)
}

function filter(){
local value ret
value=$1
ret="true"

#Shall it leave out -M and -H or not?
[[ "$value" = "-h" || "$value" = "--help" 
|| "$value" = "-M" || "$value" = "-H" 
|| "$value" = "--version" ]] &&
    ret="false"
echo "$ret"
}


function do_manpage_options(){
local value r clean regex1 regex2 lines com args
com=$1
lines=$2

#GET OPTIONS
args=($(get_options $com))
[[ -z $args ]] && echo Command not found or unknown options in: $com! && return

for num in $(seq 0 $((${#args[@]}-1))); 
do 
    value=${args[num]}
    r=$(filter $value)
    if [[ "$r" == "true" ]]; then
        [[ $value =~ (-+)([-[:alnum:]]*)(.*) ]] && clean=${BASH_REMATCH[2]}
        regex1='<xi:include href=".*-options.xml" xpointer="(-*)'$clean'(=?)" />'
        regex2='<term><option>(-*)'$clean'(.*)<.*</term>'
        if [[ ! $lines =~ $regex1 ]] && [[ ! $lines =~ $regex2 ]];
        then
            [[ $bool -eq 0 ]] && echo Updates needed in $MANPAGES/$com.xml && bool=1
            echo ...Need to document the option \"$value\" 
        fi
    fi
done
}

function do_manpage_verbs(){
local value r clean regex1 regex2 lines com args
com=$1
lines=$2

#What happened with journalctl commands?
[[ $com = "journalctl" ]] && return 

#COMMANDS/VERBS
args=($(get_verbs $com))
[[ -z $args ]] && return
for num in $(seq 0 $((${#args[@]}-1))); 
do 
    value=${args[num]}
    regex1='<term><command>'$value'(.*)</term>'
    regex2='<para><command>systemd-analyze '$value'(.*)'
    if [[ ! $lines =~ $regex1 ]] && [[ ! $lines =~ $regex2 ]];
    then
        [[ $bool -eq 0 ]] && echo Updates needed in $MANPAGES/$com.xml && bool=1
        echo ...Need to document the command \"$value\" 
    fi
done

}

function do_manpage(){
local value r clean regex1 regex2 lines com args
com=$1
bool=0
[[ ! -f $MANPAGES/$com.xml ]] && echo No manpage for $com! && return

mapfile -t lines <<< $(cat $MANPAGES/$com.xml)

do_manpage_options $com "$lines" 
do_manpage_verbs $com "$lines" 

}


function do_manpages(){
local com
local -a commands
cat <<EOF
################################################################################
#                             Uncompleted MANPAGES                             #
################################################################################
EOF

commands=($(get_systemd_commands))
for com in $(seq 0 $((${#commands[@]}-1))); do 
    do_manpage ${commands[com]} 
done
}


function do_bash_autocompletion_options(){
local value value_clear r found1 found2 args lines com
local regex regex1 regex2 regex3
com=$1
lines=$2

#OPTIONS
args=($(get_options $com))
[[ -z $args ]] && echo Command not found or unknown options: $com! && return

regex="(local -A OPTS=\([[:space:]]*)"
regex1=$regex"(\[STANDALONE\]\=)('?)([-[:alnum:][:space:]]*)('?)(.*)"
regex2=$regex"(.*)(\[ARG\]\=)('?)([-[:alnum:][:space:]]*)('?)(.*)"
regex3="(local OPTS=')([-[:alnum:][:space:]]*)('?)(.*)"

#Not "standar" way
[[ ! "$lines" =~ $regex ]]  && mapfile -t lines <<< $(cat $BASH_AUTO/$com)

[[ $lines =~ $regex1 ]] && found1=${BASH_REMATCH[4]} 
[[ $lines =~ $regex2 ]] && found2=${BASH_REMATCH[5]}
[[ $lines =~ $regex3 ]] && echo Not standar $com.Update please. && found1=${BASH_REMATCH[2]}

for num in $(seq 0 $((${#args[@]}-1))); 
do 
    value=${args[num]}
    r=$(filter $value)
    [[ $value =~ ([-[:alnum:]]*)(.*) ]] && value_clear=${BASH_REMATCH[1]}
    if [[ "$r" == "true" ]]; then
        if  [[ ! $found1 =~ (.*)$value_clear(.*) ]] && 
            [[ ! $found2 =~ (.*)$value_clear(.*) ]]; 
        then
            [[ $bool -eq 0 ]] && echo Updates needed in $BASH_AUTO/$com && bool=1
            echo ...Option not found: \"$value_clear\"
        fi
    fi
done
}

function do_bash_autocompletion_verbs(){
local file values com
local regex_verbs_start regex_verbs_end regex1
local -a arr
com=$1
file=$2
regex_verbs_start='local -A VERBS=\($'
regex_verbs_end='\)$'
regex1="(\[.*\]\=')([-[:alnum:][:space:]]*)('.*)"

#COMMANDS/VERBS
args=($(get_verbs $com))
[[ -z $args ]] && return

#Command grouping to scope arr outside while
cat $file | 
{
    while IFS= read -r line
    do
        [[ "$line" =~ $regex_verbs_start ]] && found=1 && continue
        [[ "$line" =~ $regex_verbs_end ]] && [[ $found -eq 1 ]] && break
        if [[ $found ]]; 
        then
            if [[ "$line" =~ $regex1 ]]; 
            then
                values=${BASH_REMATCH[2]}
                 arr=("${arr[@]}" ${values//[[:space:]]/ })
                #arr=("${arr[@]}" ($values))
            fi
        fi
    done
    for num in $(seq 0 $((${#args[@]}-1))); 
    do 
        if [[ ! "${arr[@]}" =~ (.*)${args[num]}(.*) ]];
        then
            [[ $bool -eq 0 ]] && echo Updates needed in $BASH_AUTO/$com && bool=1
            echo ...Verb not found: \"${args[num]}\"
        fi
    done
}  #end grouping
}


function do_bash_autocompletion(){
local com lines
com=$1
bool=0

[[ ! -f $BASH_AUTO/$com ]] && echo No bash autocompletion for $com! && return
mapfile -t lines <<< $(cat $BASH_AUTO/$com)

do_bash_autocompletion_options $com "$lines"
do_bash_autocompletion_verbs $com $BASH_AUTO/$com
}

function do_bash_autocompletions(){
local com
cat <<EOF
################################################################################
#                       Uncompleted BASH AUTOCOMPLETIONS                       #
################################################################################
EOF

declare -a commands=($(get_systemd_commands))

for com in $(seq 0 $((${#commands[@]}-1))); do 
    do_bash_autocompletion ${commands[com]} 
done
}

################################################################################
#                                     MAIN                                     #
################################################################################
function usage (){
cat <<- EOT
$0 [OPTIONS...]

Search for undocumented options and bash autocompletions

-h|help       Show this help
-v|version    Show version
-m|man        Search only for manpages
-b|bash       Search only for bash autocompletions
-t|template   Generate autocompletion template for program
-f|full       Search for everything
-p=PROGRAM    Search for undocumented program
EOT
} 

while getopts ":hvmbfp:t:" opt
do
    case $opt in
        h) 
            usage; exit 0 ;;
        v) 
            echo version: $__version; exit 0 ;;
        m)     
            do_manpages; exit 0 ;;
        b)     
            do_bash_autocompletions; exit 0 ;;
        f) 
            do_manpages 
            do_bash_autocompletions; exit 0 ;;
        p) 
            do_bash_autocompletion $OPTARG
            do_manpage $OPTARG; exit 0 ;;
        t) 
            generate_template $OPTARG; exit 0 ;;
        \?)
            echo -e "\n Incorrect option $OPTARG\n"; usage; exit 1
            ;;
        :)  
            echo "Option -$OPTARG needs an argument"; exit 1
            ;;
    esac   
done
shift $(($OPTIND-1))

[[ $# -eq 0 ]] && echo Need arguments

