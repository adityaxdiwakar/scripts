#!/bin/bash

# Function to calculate percentage complete
calculate_bytes() {
  local pos=$1
  local start=$2
  echo $(($pos - $start))
}

calculate_speed() {
  local prev_percentage=$1
  local current_percentage=$2
  local interval=$3
  local size=$4
  local perc_speed=$(awk -v prev="$prev_percentage" -v current="$current_percentage" -v interval="$interval" 'BEGIN{printf "%.7f", (current - prev) / (100 * interval)}')
  local byte_speed=$(awk -v perc_speed="$perc_speed" -v size="$size" 'BEGIN{printf "%.0f", (perc_speed * size)/1048576}')
  echo $byte_speed
}

# Parse the file transfer information
parse_file_transfer() {
  local file="$1"
  local size
  declare -A positions
  declare -A limits

  while IFS='=' read -r key value; do
    case "$key" in
      size) size="$value" ;;
      *.pos) positions["${key%.*}"]="$value" ;;
      *.limit) limits["${key%.*}"]="$value" ;;
    esac
  done < "$file"

  completed_bytes=0
  local_start=0
  indices=( ${!positions[@]} )
  for ((pos=0; pos < ${#indices[@]}; pos++)) ; do
    current_pos="${positions[$pos]}"
    bytes=$(calculate_bytes "$current_pos" "$local_start")
    completed_bytes=$(($completed_bytes + $bytes))
    local_start=${limits[$pos]}
  done

  local percentage=$(awk -v completed_bytes="$completed_bytes" -v size="$size" 'BEGIN{printf "%.3f", 100 * completed_bytes / size}')
  echo "$percentage,$size"
}

# Usage: ./script.sh <file>
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <file>"
  exit 1
fi

display_progress_bar() {
  local percentage=$1
  local term_width=$(tput cols)
  local max_len=$((term_width - 30))
  local filled_length=$(awk -v percentage="$percentage" -v max_len="$max_len" 'BEGIN{printf "%.2f", (percentage * max_len) / 100}')
  local bar=$(printf "%${filled_length}s" | tr ' ' '=')
  printf "\r[%-${max_len}s] %s%%" "$bar" "$percentage"
}

file="$1"
echo "Reading from $file"

if [[ ! -e $file ]]; then
  echo "File not found."
  exit 1
fi

res=$(parse_file_transfer "$file")
IFS=',' read -r last_perc size <<< "$res"
prev_mtime=$(stat -c %Y "$file")

while true; do
  curr_mtime=$(stat -c %Y "$file")

  if [[ ! -e $file ]]; then
    echo "Complete."
    break
  fi

  if [ "$curr_mtime" -gt "$prev_mtime" ]; then
    time_diff=$((curr_mtime - prev_mtime))

    res=$(parse_file_transfer "$file")
    IFS=',' read -r cur_perc _ <<< "$res"
    speed=$(calculate_speed "$last_perc" "$cur_perc" "$time_diff" "$size")
    display_progress_bar "$cur_perc"
    printf " - Speed: %s MB/s" "$speed"

    last_perc=$cur_perc
    prev_mtime=$curr_mtime
  fi

  sleep 0.5
done
