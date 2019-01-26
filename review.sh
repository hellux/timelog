#!/bin/sh

TIME_REGEX="[0-2][0-9][0-5][0-9]"
RNT_DIR="$(mktemp -d)"

duration_fmt() {
    hourstr="$(($1 / 60))h"
    if [ $(($1 % 60)) -gt 0 ]
    then minstr="$(($1 % 60))m"
    else minstr=""
    fi
    printf "$hourstr $minstr"
}
duration() {
    start=$1; end=$2
    starth=$(echo "$start" | cut -c1-2 | sed 's/0*//')
    startm=$(echo "$start" | cut -c3-4 | sed 's/0*//')
    endh=$(echo "$end" | cut -c1-2 | sed 's/0*//')
    endm=$(echo "$end" | cut -c3-4 | sed 's/0*//')
    echo "$((endh*60 + endm - starth*60 - startm))"
}

daily="false"
weekly="false"
summary="false"
activities="false"
while getopts dwas flag; do
    case $flag in
    d) daily="true";;
    w) weekly="true";;
    s) summary="true";;
    a) activities="true";;
    esac
done
shift $(($OPTIND-1))

[ -z "$1" ] && exit 1

if [ -d "$1" ];
then day_files="$1/*"
else day_files="$@"
fi

mkdir -p "$RNT_DIR/weeks"
mkdir -p "$RNT_DIR/activities"
rm -rf "$RNT_DIR"/weeks/*

# format to entries per day per week, and per activity
for dayfile in $day_files; do
    day=$(basename $dayfile)
    week=$(date -d"$day" +"%V")
    mkdir -p "$RNT_DIR/weeks/$week"
    grep -e "^$TIME_REGEX $TIME_REGEX" "$dayfile" | sed 's/ /\t/;s/ /\t/' |\
    while read -r start end activity; do
        duration="$(duration $start $end)"

        actfile="$RNT_DIR/activities/$activity"
        if [ -e "$actfile" ]; then
            current="$(cat $actfile)"
            echo "$((current+duration))" > "$actfile"
        else
            echo "$duration" > "$actfile"
        fi

        printf "$day\t$start\t$end\t$duration\t$activity\n"
    done > "$RNT_DIR/weeks/$week/$day"
done

minutes_total=0
for weekdir in $RNT_DIR/weeks/*; do
    week=$(basename "$weekdir")
    minutes_week=0
    
    for dayfile in $weekdir/*; do
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
    for actfile in $RNT_DIR/activities/*; do
        activity="$(basename $actfile)"
        minutes_activity="$(cat $actfile)"
        duration=$(duration_fmt minutes_activity)
        percentage="$((100*minutes_activity/minutes_total))"
        printf "%s\t%3d%%\t%s\n" "$duration" "$percentage" "$activity" 
    done | sort -nr
fi

printf "Total: %s\n" "$(duration_fmt "$minutes_total")"

rm -rf "$RNT_DIR"
