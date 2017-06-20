#! /bin/bash

normal="\e[0m"
bold="\e[1m"
italic="\e[3m"
underline="\e[4m"
black="\e[30m"
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
blue="\e[34m"
magenta="\e[35m"
cyan="\e[36m"
white="\e[37m"

# >&2 echo -e "${black}black, ${red}red, ${green}green, ${yellow}yellow, ${blue}blue, ${magenta}magenta, ${cyan}cyan, ${white}white${normal}"
# >&2 echo -e "${bold}${black}black, ${red}red, ${green}green, ${yellow}yellow, ${blue}blue, ${magenta}magenta, ${cyan}cyan, ${white}white${normal}"

if [[ ! -t 0 ]]; then
    normal=""
    bold=""
    italic=""
    underline=""
    black=""
    red=""
    green=""
    yellow=""
    blue=""
    magenta=""
    cyan=""
    white=""
fi

# ---------------------------------------------
function errEcho()
{
    >&2 echo -e $*
}

function die()
{
    local _retCode; _retCode=$?
    errEcho "${bold}${red}[ERROR] Failure in:${normal} $@" 1>&2
    if [[ $_retCode == 0 ]] ; then
        _retCode=1
    fi
    exit $_retCode
}

# ---------------------------------------------
function dbgList
{
    local _listName; _listName="${1:-List}"
    if [[ $# > 0 ]]; then
        shift
    fi
    local _msgtxt; _msgtxt="${@:- EMPTY}"
    errEcho "${blue}[DBG ]: $_listName = [${black}${bold}"
    errEcho "$_msgtxt"
    errEcho "${normal}${blue}]${normal}"
}

function dbgEcho
{
    local _msgtxt; _msgtxt="${@:-}"
    errEcho "${blue}[DBG ]:${black}${bold} $_msgtxt${normal}"
}

function dbgVar()
{
    local _line; _line=""
    local _entry; _entry=""
    while [[ $# -ge 1 ]]; do
        if [[ -n $1 ]]; then
            eval _val=\$$1
            _entry="$(printf "$1 = [${_val:-NOT SET}]")"
            if [[ $# -gt 1 ]]; then
                _entry="${_entry}, "
            fi
        fi
        _line="${_line}${_entry}"
        shift
    done
    dbgEcho "${_line}${normal}"
}

function traceEcho
{
    local _msgtxt;_msgtxt="${@:-}"
    errEcho "${magenta}[TRC ]:${normal} $_msgtxt${normal}"
}

function infoEcho
{
    local _msgtxt;_msgtxt="${@:-}"
    errEcho "${yellow}[INFO]:${normal} $_msgtxt${normal}"
}

function warnEcho
{
    local _msgtxt;_msgtxt="${@:-}"
    errEcho "${red}[WARN]:${normal} $_msgtxt${normal}"
}

function errorEcho
{
    local _msgtxt;_msgtxt="${@:-}"
    errEcho "${bold}${red}[ERR ]:${normal} $_msgtxt${normal}"
}

# ---------------------------------------------
function preserveFile()
{
    local _fname; _fname="$1"
    if [[ -n $_fname && -f $_fname ]]; then
        # Get the last accessed time - trim off the fractional seconds?
        local _accessTime; _accessTime="$(find $(dirname "$_fname") -name "$_fname" -printf "%AY%Am%Ad.%AH%AM%AS")"
        if [[ -z $_accessTime ]]; then
            _accessTime="UNKNOWN"
        fi
        infoEcho "Moving existing ${bold}[$_fname]${normal}"
        mv -fv "$_fname" "${_fname}.${_accessTime}.old" || die "Cannot move existing file"
    fi
}

function loadModule()
{
    local _modulename; _modulename="$1"
    if [[ -n $_modulename ]]; then
        if [[ $(grep -c "$_modulename" <(2>&1 module list )) -ge 1 ]]; then
            dbgEcho "Module [$_modulename] is already loaded"
            return 0
        else
            dbgEcho "Module [$_modulename] is not loaded - attempt to load it"
            # try and load it
            module load "$_modulename" || return 1
            # in theory it is loaded, check again
            if [[ $(grep -c "$_modulename" <(2>&1 module list )) -ge 1 ]]; then
                return 0
            else
                return 1
            fi
        fi
    fi
}

function amazonDetails()
{
    # really hacky
    if [[ -f /sys/hypervisor/uuid && $(head -c 3 /sys/hypervisor/uuid) == ec2 ]]; then
        local _instanceid; _instanceid="$(wget -q -O - http://instance-data/latest/meta-data/instance-id || die "Cannot wget instance-id")"
        local _availabilityzone; _availabilityzone="$(wget -q -O - http://instance-data/latest/meta-data/placement/availability-zone || die "Cannot wget availability zone")"
        local _region; _region="$(sed -r "s:([0-9][0-9]*)[a-z]*$:\1:" <<< "$_availabilityzone")"
        echo $_instanceid $_availabilityzone $_region
    else
        echo
    fi
}

# ---------------------------------------------
set -u -o pipefail

function usage()
{
    errEcho "${bold}Usage:${normal} $(basename "${BASH_SOURCE[0]}") [trainingDB export path] [--test-only]"
}

localDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

if [[ $# -lt 1 || ($# -ge 1 && $1 =~ "^--h") ]]; then
    usage
    exit 1
fi

# always log - uncomment if needed
if [[ -z ${ROAMES_NO_SCRIPT_LOGGING:-} ]]; then
    logfileprefix="$(basename "${BASH_SOURCE[0]}" | sed -r "s:\..*$::").$(date "+%Y%m%d%H%M")"
    dbgVar logfileprefix
    if [[ -f ${logfileprefix}.err.log || -f ${logfileprefix}.out.log ]]; then
        logfileprefix="${logfileprefix}.$$"
        dbgEcho "Rebuilt logfileprefix [$logfileprefix]"
    fi
    infoEcho "Logging to ${logfileprefix}.err.log and ${logfileprefix}.out.log"
    exec 2> >(tee -a ${logfileprefix}.err.log 1>&2)
    exec > >(tee -a ${logfileprefix}.out.log)
else
    dbgEcho "Not logging - ROAMES_NO_SCRIPT_LOGGING is set"
fi

#set -x
# ---------------------------------------------

traceEcho "Process args"

trainingDBPath="$(sed -r "s%/$%%" <<< "$1")"
dbgVar trainingDBPath

traceEcho "Validate args"

if [[ ! -d $trainingDBPath || ! -r $trainingDBPath ]]; then
    die "Cannot read input directory [$trainingDBPath]"
fi

traceEcho "Process"

git status || die "COuld not run [git status]"

find "$trainingDBPath" -type f | while read infile; do
    inmd5="$(md5sum <(sed -r "s@\r\n@\n@g; s@\r@\n@g; s%[ \t]+$%%g" "$infile") | cut -d ' ' -f 1 || die "Cannot calculte md5sum for file[$infile]")"
    dbgVar infile inmd5
    outfile="$(sed -r "s@^${trainingDBPath}/@./@" <<< $infile)"

    if [[ -f $outfile ]]; then
        outmd5="$(md5sum "$outfile" | cut -d ' ' -f 1)"
        dbgVar outfile outmd5
        # outfile exists, check md5's
        if [[ $inmd5 == $outmd5 ]]; then
            # md5 sums are the same, report it and carry on
            infoEcho "input file [$infile] is identical to existing output file - skipping"
            continue
        else
            sed -r "s@\r\n@\n@g; s@\r@\n@g; s%[ \t]+$%%g" "$infile" > "$outfile" && infoEcho "Copied modified [$infile]" || die "Failed to copy modified file [$infile]"
            git add "$outfile" || die "Could not add updated file [$outfile] to git"
        fi
    else
        dbgVar outfile
        # outfile does not exist, copy it
        outpath="$(dirname "$outfile")"
        if [[ ! -d $outpath ]]; then
            mkdir -pv "$outpath" || die "Could not make output path [$outpath]"
        fi
        sed -r "s@\r\n@\n@g; s@\r@\n@g; s%[ \t]+$%%g" "$infile" > "$outfile" && infoEcho "Copied new file [$infile]" || die "Failed copying new file [$infile]"
        git add "$outfile" || die "Could not add new file [$outfile] to git"
    fi
done

find . -type f -name "*.txt" | while read fl; do
    srcname="$(sed -r "s@^\./@${trainingDBPath}/@g" <<< "$fl")"
    dbgVar fl srcname
    if [[ ! -f $srcname ]]; then
        #echo "git rm \"$fl\" || die \"Failed to remove deleted file [$fl] from git\""
        git rm "$fl" || die "Failed to remove deleted file [$fl] from git"
    fi
done

echo
git status || die "Could not get git status"
echo

traceEcho "${bold}${green}DONE.${normal}"

exit 0

