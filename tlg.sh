#!/bin/sh

die() {
    fmt="$1"
    [ -n "$2" ]; shift
    printf 'error: '"$fmt"'\n' "$@" 1>&2
    rm -rf "$RNT_DIR"
    exit 1
}

TIMEFMT="%H%M"
DATE_REGEX="^([0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])$"
TIME_REGEX="[0-2][0-9][0-5][0-9]"
TMPDIR="$(mktemp -d)"
SUBSEP="|"

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
                if [ "$TLG_GIT" != "false" ]; then
                    cd "$(dirname "$logfile")" || die "cd failed"
                    git add "$logfile"
                    git commit "$logfile" -m "log time"
                    cd - > /dev/null || "cd back failed"
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
    minutes=$1
    if [ "$minutes" -lt 0 ]; then
        minutes=$((-minutes))
        printf "-"
    fi
    hourstr="$((minutes / 60))h"
    if [ $((minutes % 60)) -gt 0 ]
    then minstr="$((minutes % 60))m"
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

    if [ -z "$1" ];
    then day_files="$TIMELOG_DIR/*"
    elif [ -z "$2" ] && [ -d "$1" ]
    then day_files="$1/*"
    else day_files="$*"
    fi

    mkdir -p "$TMPDIR/weeks"
    mkdir -p "$TMPDIR/activities"
    rm -rf "$TMPDIR"/weeks/*

    # format to entries per day per week, and per activity
    minutes_should=0
    for dayfile in $day_files; do
        minutes_should=$((minutes_should + 8*60))

        day="$(basename "$dayfile")"
        [ -r "$dayfile" ] || die "cannot open log file -- %s" "$dayfile"
        echo "$day" | grep -qE "$DATE_REGEX" \
            || die "invalid filename, must be of type YYYY-MM-DD -- %s" "$day"
        week="$(date -d"$day" +"%V")"
        mkdir -p "$TMPDIR/weeks/$week"

        AWK_PARSE='
        function duration(start, end) {
            starth=substr(start,1,2);
            startm=substr(start,3,2);
            endh=substr(end,1,2);
            endm=substr(end,3,2);
            return endh*60 + endm - starth*60 - startm
        }

        function flush() {
            if (start != "") {
                partstr=""
                for (p in participants) partstr=partstr SEP p
                partstr=substr(partstr,2)
                topstr=""
                for (t in topics) topstr=topstr SEP t
                topstr=substr(topstr,2)

                OFS="\t"
                FS=OFS
                print day,start,end,duration(start, end),activity,partstr,topstr
                OFS=" "
                FS=OFS

                start=""; end=""; activity="";
                split("", participants); split("", topics)
            }
        }

        $1 ~ REG && $2 ~ REG { flush(); start=$1; end=$2; activity=$3 }
        $1 == "+" { $1=""; participants[substr($0,2)]="" }
        $1 == "*" { $1=""; topics[substr($0,2)]="" }
        END { flush() }'
        awk -v"day=$day" -v"SEP=$SUBSEP" -v"REG=$TIME_REGEX" "$AWK_PARSE"\
            "$dayfile" > "$TMPDIR/weeks/$week/$day" || die "awk failed"
    done

    minutes_total=0
    for weekdir in "$TMPDIR"/weeks/*; do
        week=$(basename "$weekdir")
        minutes_week=0

        for dayfile in "$weekdir"/*; do
            minutes_day=0
            while read -r day start end duration activity partic topics; do
                minutes_day=$((minutes_day+duration))

                if [ "$activities" = "true" ]; then
                    actfile="$TMPDIR/activities/$activity"
                    if [ -e "$actfile" ]; then
                        current=$(cat "$actfile")
                        echo $((current+duration)) > "$actfile"
                    else
                        echo "$duration" > "$actfile"
                    fi
                fi

                if [ "$summary" = "true" ]; then
                    startstr=$(date -d"$start" +"%H:%M")
                    endstr=$(date -d"$end" +"%H:%M")
                    hours=$(echo "scale=2; $duration/60" | bc)
                    partstr=$(echo "$partic" | sed "s/$SUBSEP/, /g")
                    topstr=$(echo "$topics" | sed "s/$SUBSEP/, /g")

                    printf "%s\t%s\t%s\t%s\t%s: %s\t%s\n" "$day" "$startstr" \
                        "$endstr" "$hours" "$activity" "$topstr" "$partstr"
                fi
            done < "$dayfile"

            day=$(basename "$dayfile")
            if [ "$daily" = "true" ]; then
                printf "%s: %s\n" "$(date -d"$day" +"%Y-%m-%d %a")" \
                                  "$(duration_fmt "$minutes_day")"
            fi

            minutes_week=$((minutes_week+minutes_day))
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

    diff=$(duration_fmt $((minutes_total-minutes_should)) | sed 's/^[0-9]/+&/')
    printf "Total: %s (%s)\n" "$(duration_fmt "$minutes_total")" "$diff"

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
