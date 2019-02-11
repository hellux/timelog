#!/bin/sh

die() {
    [ -n "$2" ]; shift
    printf 'error: '"$1"'\n' "$@" 1>&2
    rm -rf "$RNT_DIR"
    exit 1
}

TIMEFMT="%H%M"
TZ=$(date +"%Z")
TIME_REGEX="[0-2][0-9][0-5][0-9]"
TMPDIR="$(mktemp -d)"

log_cmd() {
    dir="$1"
    [ -z "$dir" ] && exit 1
    shift

    # determing start and end times
    duration=${1:-120}
    file="$dir"/"$(date +"%F")"
    unix=$(date +"%s")
    halfhours=$(((unix+60*15) / (60*30)))
    start=$(date -d "@$(((halfhours*30-duration)*60))" +"$TIMEFMT")
    end=$(date -d "@$((halfhours*30*60))" +"$TIMEFMT")

    # create temporary file
    log="$TMPDIR/log"
    cmp="$TMPDIR/cmp"
    if [ -r "$file" ]; then
        cat "$file" > "$log"
        echo >> "$log"
    fi
    echo "$start $end" >> "$log"
    touch "$log" -d "1970-01-01T00:00:00"
    touch "$cmp" -d "1970-01-01T00:00:00"

    # edit log
    $EDITOR "$log"

    # write log to log dir
    if [ "$log" -nt "$cmp" ]; then
        if [ -s "$log" ]; then
            cp "$log" "$file"
            echo "log saved to $file"
        else
            rm -f "$file"
            echo "log empty, removed existing (if any)"
        fi
    else
        echo "log not written, aborting"
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

    [ -z "$1" ] && exit 1

    if [ -d "$1" ];
    then day_files="$1/*"
    else day_files="$*"
    fi

    mkdir -p "$TMPDIR/weeks"
    mkdir -p "$TMPDIR/activities"
    rm -rf "$TMPDIR"/weeks/*

    # format to entries per day per week, and per activity
    for dayfile in $day_files; do
        day="$(basename "$dayfile")"
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
                    printf "%s\t%s\t%s-%s\t%s\n" "$date" \
                           "$duration" "$start" "$end" "$activity"
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

rm -rf "$TMPDIR"
