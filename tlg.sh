#!/bin/sh

die() {
    fmt="$1"
    [ -n "$2" ]; shift
    printf 'error: '"$fmt"'\n' "$@" 1>&2
    rm -rf "$RNT_DIR"
    exit 1
}

TIMELOG_FULLTIME=${TIMELOG_FULLTIME:-$((8*60))}

DATE_REGEX="^([0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])$"
TMPDIR="$(mktemp -d)"

NRMCOL='\033[0m'
BLDCOL='\033[0;1m'
LO2COL='\033[31;1m'
LO1COL='\033[33;1m'
MEDCOL='\033[32;1m'
HI1COL='\033[35;1m'
HI2COL='\033[34;1m'

log_cmd() {
    if [ -z "$1" ]; then
        if [ -n "$TIMELOG_DIR" ]; then
            logfile="$TIMELOG_DIR/$(date +"%Y-%m-%d")"
        else
            die "no directory or log specified"
        fi
    elif [ -d "$1" ]; then
        logfile="$1/$(date +"%Y-%m-%d")"
        shift
    elif basename "$1" | grep -qE "$DATE_REGEX"; then
        logfile="$1"
        shift
    else
        die "invalid dir or log -- %s" "$1"
    fi

    # create temporary file
    tmplog="$TMPDIR/log"
    cmp="$TMPDIR/cmp"
    if [ -r "$logfile" ]; then
        cp "$logfile" "$tmplog"
    fi
    EPOCH="1970-01-01T00:00:00"
    touch -d "$EPOCH" "$tmplog"
    touch -d "$EPOCH" "$cmp"

    # let user edit log
    $EDITOR "$tmplog"

    # write log to log dir
    if [ "$tmplog" -nt "$cmp" ]; then
        if [ -s "$tmplog" ]; then
            if cp "$tmplog" "$logfile"; then
                cd "$(dirname "$logfile")" || die "cd failed"
                if git status; then
                    git add "$logfile"
                    git commit "$logfile" -m "log time"
                fi
                cd - > /dev/null || "cd back failed"
                echo "log saved to $logfile"
            else
                echo "failed to save log"
                cat "$tmplog"
            fi
        else
            rm -f "$logfile"
            echo "log empty, removed existing (if any)"
        fi
    else
        echo "log not modified, no writing needed"
    fi
}

year() {
    date -d "$*" +"%Y"
}
month() {
    date -d "$*" +"%Y-%m"
}
week() {
    date -d "$*" +"%G-W%V"
}

duration() {
    start=$1; end=$2
    starth=$(echo "$start" | cut -c1-2 | sed 's/0*//')
    startm=$(echo "$start" | cut -c3-4 | sed 's/0*//')
    endh=$(echo "$end" | cut -c1-2 | sed 's/0*//')
    endm=$(echo "$end" | cut -c3-4 | sed 's/0*//')
    echo "$((endh*60 + endm - starth*60 - startm))"
}

duration_fmt() {
    dur=$1
    if [ "$dur" -lt 0 ]; then
        dur=$((-dur))
        printf "-"
    fi
    if [ "$dur" -gt 60 ];
    then hourstr="$((dur / 60))h"
    else hourstr=""
    fi
    if [ $((dur % 60)) -gt 0 ]
    then minstr="$((dur % 60))m"
    else minstr=""
    fi

    if [ -z "$minstr" ] && [ -z "$hourstr" ]; then
        printf "0m"
    elif [ -z "$minstr" ]; then
        printf "%s" "$hourstr"
    elif [ -z "$hourstr" ]; then
        printf "%s" "$minstr"
    else
        printf "%s %s" "$hourstr" "$minstr"
    fi
}

aggregate_fmt() {
    inputfile=$1
    header=$2

    dur_total=0
    dur_full=0
    current_day=""
    while read -r day start end _; do
        dur_total=$((dur_total+$(duration "$start" "$end")))
        if [ "$current_day" != "$day" ]; then
            dur_full=$((dur_full+fulltime))
            current_day="$day"
        fi
    done < "$inputfile"

    if [ -n "$fulltime" ]; then
        diff=$((dur_total-dur_full))
        ratio=$((100*diff/dur_full)); ratio=${ratio#-}
        col=$MEDCOL
        if [ "$diff" -gt 0 ]; then
            diffsign="+"
            if [ "$ratio" -ge 10 ]; then
                col=$LO2COL
            elif [ "$ratio" -ge 5 ]; then
                col=$LO1COL
            fi
        else
            diffsign=""
            if [ "$ratio" -ge 10 ]; then
                col=$HI2COL
            elif [ "$ratio" -ge 5 ]; then
                col=$HI1COL
            fi
        fi
        ftstr=" $diffsign$(duration_fmt "$diff")"
    else
        ftstr=""
    fi

    printf "$BLDCOL%s $NRMCOL%s$col%s$NRMCOL\n" \
           "$header" "$(duration_fmt "$dur_total")" "$ftstr"
}

review_cmd() {
    daily=""
    weekly=""
    monthly=""
    yearly=""
    fulltime=""
    OPTIND=1
    while getopts dwmyf flag; do
        case $flag in
        d) daily="true";;
        w) weekly="true";;
        m) monthly="true";;
        y) yearly="true";;
        f) fulltime="$TIMELOG_FULLTIME";;
        [?]) die "invalid flag -- %s" "$OPTARG"
        esac
    done
    shift $((OPTIND-1))

    if [ -z "$1" ];
    then day_files="$TIMELOG_DIR/*"
    elif [ -z "$2" ] && [ -d "$1" ]
    then day_files="$1/*"
    else day_files="$*"
    fi

    mkdir -p "$TMPDIR/d"
    mkdir -p "$TMPDIR/w"
    mkdir -p "$TMPDIR/m"
    mkdir -p "$TMPDIR/y"

    for dayfile in $day_files; do
        day="$(basename "$dayfile")"
        echo "$day" | grep -qE "^(.*/)?$DATE_REGEX$" \
            || die "invalid filename, must be of type YYYY-MM-DD -- %s" "$day"
        [ -r "$dayfile" ] || die "cannot open log file -- %s" "$dayfile"

        # rm comments, rm empty lines, prepend day
        sed 's:#.*$::g' "$dayfile" | awk 'NF' | sed "s/^/$day /" > "$TMPDIR/d/$day"

        # add to aggregated periods
        [ -n "$weekly"  ] && cat "$TMPDIR/d/$day" >> "$TMPDIR/w/$(week "$day")"
        [ -n "$monthly" ] && cat "$TMPDIR/d/$day" >> "$TMPDIR/m/$(month "$day")"
        [ -n "$yearly"  ] && cat "$TMPDIR/d/$day" >> "$TMPDIR/y/$(year "$day")"
    done

    current_year=""
    current_month=""
    current_week=""
    for dayfile in "$TMPDIR"/d/*; do
        day=$(basename "$dayfile")

        year=$(year "$day")
        if [ "$yearly" = "true" ] && [ "$current_year" != "$year" ]; then
            current_year="$year"
            aggregate_fmt "$TMPDIR/y/$year" "$year"
        fi

        month=$(month "$day")
        if [ "$monthly" = "true" ] && [ "$current_month" != "$month" ]; then
            current_month="$month"
            aggregate_fmt "$TMPDIR/m/$month" "$(date -d "$day" +"%b %Y")"
        fi

        week=$(week "$day")
        if [ "$weekly" = "true" ] && [ "$current_week" != "$week" ]; then
            current_week="$week"
            aggregate_fmt "$TMPDIR/w/$week" "$(date -d "$day" +"%G-W%V")"
        fi

        if [ "$daily" = "true" ]; then
            aggregate_fmt "$dayfile" "$(date -d "$day" +"%a %e %b")"
        fi
    done
}

command="$1"
[ -z "$command" ] && die "no command"
shift

case "$command" in
    l|log) log_cmd "$@";;
    r|review) review_cmd "$@";;
    *) die 'invalid command -- %s\n\n%s' "$command" "$USAGE";;
esac

rm -rf "$TMPDIR"
