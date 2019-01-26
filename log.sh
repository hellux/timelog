#!/bin/sh

TIMEFMT="%H%M"
TZ=$(date +"%Z")

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
log=$(mktemp)
cmp=$(mktemp)
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

rm -f "$log" "$cmp"
