#!/bin/sh

die() {
    [ -n "$2" ]; shift
    printf 'error: '"$1"'\n' "$@" 1>&2
    rm -rf "$RNT_DIR"
    exit 1
}

TIMEFMT="%H%M"
DATE_REGEX="^([0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])$"
TIME_REGEX="[0-2][0-9][0-5][0-9]"
TMPDIR="$(mktemp -d)"

log_cmd() {
    [ -z "$1" ] && die "no directory or log specified"
    if [ -d "$1" ]; then
        logfile="$1/$(date +"%Y-%m-%d")"
    elif echo "$(basename $1)" | grep -qE "$DATE_REGEX"; then
        logfile="$1"
    else
        die "invalid dir or log -- %s" "$1"
    fi
    shift
    duration=${1:-120}

    # create temporary file
    tmplog="$TMPDIR/log"
    cmp="$TMPDIR/cmp"
    if [ -r "$logfile" ]; then
        cat "$logfile" > "$tmplog"
    else
        unix=$(date +"%s")
        halfhours=$(((unix+60*15) / (60*30)))
        start=$(date -d "@$(((halfhours*30-duration)*60))" +"$TIMEFMT")
        end=$(date -d "@$((halfhours*30*60))" +"$TIMEFMT")

        echo "$start $end" > "$tmplog"
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
                if [ "$TLG_GIT" = "true" ]; then
                    git add "$logfile"
                    git commit "$logfile" -m "log time"
                fi
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

duration_fmt() {
    hourstr="$(($1 / 60))h"
    if [ $(($1 % 60)) -gt 0 ]
    then minstr="$(($1 % 60))m"
    else minstr=""
    fi
    printf "%s %s" "$hourstr" "$minstr"
}

duration() {
    start=$1; end=$2
    starth=$(echo "$start" | cut -c1-2 | sed 's/0*//')
    startm=$(echo "$start" | cut -c3-4 | sed 's/0*//')
    endh=$(echo "$end" | cut -c1-2 | sed 's/0*//')
    endm=$(echo "$end" | cut -c3-4 | sed 's/0*//')
    echo "$((endh*60 + endm - starth*60 - startm))"
}

review_cmd() {
    daily="false"
    weekly="false"
    summary="false"
    activities="false"
    OPTIND=1
    while getopts dwas flag; do
        case $flag in
        d) daily="true";;
        w) weekly="true";;
        s) summary="true";;
        a) activities="true";;
        [?]) die "invalid flag -- %s" "$OPTARG"
        esac
    done
    shift $((OPTIND-1))

    [ -z "$1" ] && die "no directory or log files specified"

    if [ -z "$2" -a -d "$1" ];
    then day_files="$1/*"
    else day_files="$*"
    fi

    mkdir -p "$TMPDIR/weeks"
    mkdir -p "$TMPDIR/activities"
    rm -rf "$TMPDIR"/weeks/*

    # format to entries per day per week, and per activity
    for dayfile in $day_files; do
        day="$(basename "$dayfile")"
        [ -r "$dayfile" ] || die "cannot open log file -- %s" "$dayfile"
        echo $day | grep -qE "$DATE_REGEX" \
            || die "invalid filename, must be of type YYYY-MM-DD -- %s" "$day"
        week="$(date -d"$day" +"%V")"
        mkdir -p "$TMPDIR/weeks/$week"

        grep -e "^$TIME_REGEX $TIME_REGEX" "$dayfile" |\
            sed 's/ /\t/;s/ /\t/' |\
            while read -r start end activity; do
                duration="$(duration "$start" "$end")"

                actfile="$TMPDIR/activities/$activity"
                if [ -e "$actfile" ]; then
                    current="$(cat "$actfile")"
                    echo "$((current+duration))" > "$actfile"
                else
                    echo "$duration" > "$actfile"
                fi

                printf "%s\t%s\t%s\t%s\t%s\n" "$day" "$start" "$end" \
                                              "$duration" "$activity"
            done > "$TMPDIR/weeks/$week/$day"
    done

    minutes_total=0
    for weekdir in "$TMPDIR"/weeks/*; do
        week=$(basename "$weekdir")
        minutes_week=0
        
        for dayfile in "$weekdir"/*; do
            day=$(basename "$dayfile")
            minutes_day=0
            while read -r date start end duration activity; do
                minutes_day=$((minutes_day+duration))

                if [ "$summary" = "true" ];then
                    startstr=$(date -d"$start" +"%H:%M")
                    endstr=$(date -d"$end" +"%H:%M")
                    hours=$(echo "scale=2; $duration/60" | bc)
                    printf "%s\t%s\t%s\t%s\t%s\n" "$date" \
                           "$startstr" "$endstr" "$hours" "$activity"
                fi
            done < "$dayfile"
            minutes_week=$((minutes_week+minutes_day))

            if [ "$daily" = "true" ]; then
                printf "%s: %s\n" "$(date -d"$day" +"%Y-%m-%d %a")" \
                                  "$(duration_fmt "$minutes_day")"
            fi
        done
        minutes_total=$((minutes_total+minutes_week))

        if [ "$weekly" = "true" ]; then
            printf "W%s: %s\n" "$week" "$(duration_fmt "$minutes_week")"
        fi
    done

    if [ "$activities" = "true" ]; then
        for actfile in "$TMPDIR"/activities/*; do
            activity="$(basename "$actfile")"
            minutes_activity="$(cat "$actfile")"
            duration=$(duration_fmt minutes_activity)
            percentage="$((100*minutes_activity/minutes_total))"
            printf "%s\t%3d%%\t%s\n" "$duration" "$percentage" "$activity" 
        done | sort -nr
    fi

    printf "Total: %s\n" "$(duration_fmt "$minutes_total")"
}

command="$1"
[ -z "$command" ] && die "no command"
shift

case "$command" in
    l|log) log_cmd "$@";;
    r|review) review_cmd "$@";;
    *) die 'invalid command -- %s\n\n%s' "$command" "$USAGE";;
esac

#rm -rf "$TMPDIR"
