#!/bin/zsh
#
# measure-efficiency.sh
#
# Profiles the cost of a macOS dictation app so several apps can be compared on
# the same machine with the same harness. Reports resident memory, idle CPU,
# and optionally energy and timer wakeups.
#
# Usage
#   ./measure-efficiency.sh [-i seconds] [-d] [-h] [<app|pid> ...]
#
#   -i seconds   idle sampling window. Default 30.
#   -d           deep mode. Adds energy impact, CPU ms/s and timer wakeups via
#                powermetrics. Needs sudo, so it will prompt.
#   -h           help
#
# With no target, measures the calling shell, which doubles as a self test.
#
# Examples
#   ./measure-efficiency.sh Utter
#   ./measure-efficiency.sh -i 60 Utter Handy FluidVoice VoiceInk
#   sudo ./measure-efficiency.sh -d Utter
#
# Method
#   Resident memory comes from footprint(1), which reports phys_footprint and
#   phys_footprint_peak. Idle CPU comes from the delta in cumulative CPU time
#   over the sampling window, which is exact rather than a decaying average.
#   Deep mode adds powermetrics(1), the only source for energy and wakeups.
#
# Read it like this
#   Launch each app, let it sit idle and unfocused, then measure. A dictation
#   app that just transcribed something holds a warm model in memory, and that
#   warm state is its steady state, so measure after one dictation rather than
#   straight after launch.
#
#   idle CPU near 0.0 and zero wakeups mean the app is genuinely asleep. A
#   timer that fires once a second will show up here and will cost battery all
#   day even though it looks free.
#
# Caveat
#   Run this in a normal Terminal. ps(1) and top(1) are blocked for other
#   processes inside a sandbox, so a sandboxed run reports memory only.

set -u
emulate -L zsh

WINDOW=30
DEEP=0
TARGETS=()

usage() {
  sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while (( $# )); do
  case "$1" in
    -i) WINDOW="${2:-30}"; shift 2 ;;
    -d) DEEP=1; shift ;;
    -h|--help) usage ;;
    -*) print -u2 "unknown option: $1"; exit 2 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

if (( ${#TARGETS[@]} == 0 )); then
  TARGETS=("$$")
fi

# Human readable bytes from a string like "177 MB" or "1952 KB".
to_mb() {
  local v="${1%% *}" u="${1##* }"
  case "$u" in
    GB) print -r -- "$v" | awk '{printf "%.1f", $1*1024}' ;;
    MB) print -r -- "$v" | awk '{printf "%.1f", $1}' ;;
    KB) print -r -- "$v" | awk '{printf "%.1f", $1/1024}' ;;
    B)  print -r -- "$v" | awk '{printf "%.1f", $1/1048576}' ;;
    *)  print -r -- "0" ;;
  esac
}

# Seconds from a ps cputime field such as "1:02.34" or "12:00.00".
ctime_to_secs() {
  print -r -- "$1" | awk -F: '
    { if (NF==3) printf "%.2f", $1*3600+$2*60+$3
      else if (NF==2) printf "%.2f", $1*60+$2
      else printf "%.2f", $1 }'
}

resolve_pid() {
  local t="$1"
  if [[ "$t" == <-> ]]; then
    print -r -- "$t"
    return 0
  fi
  local p
  p=$(pgrep -x "$t" 2>/dev/null | head -1)
  [[ -z "$p" ]] && p=$(pgrep -f "$t" 2>/dev/null | head -1)
  [[ -n "$p" ]] && print -r -- "$p"
}

mem_of() {
  local pid="$1" raw res peak
  raw=$(footprint --noCategories -p "$pid" 2>/dev/null)
  [[ -z "$raw" ]] && return 1
  res=$(print -r -- "$raw" | grep -m1 'Footprint:' | sed -E 's/.*Footprint: *([0-9.]+ [KMG]?B).*/\1/')
  peak=$(print -r -- "$raw" | grep -m1 'phys_footprint_peak:' | sed -E 's/.*phys_footprint_peak: *//')
  print -r -- "$res|$peak"
}

# Idle CPU percent, averaged over the window, from cumulative CPU time.
cpu_of() {
  local pid="$1" a b sa sb
  a=$(ps -o cputime= -p "$pid" 2>/dev/null | tr -d ' ')
  if [[ -z "$a" ]]; then
    print -r -- "n/a"
    return 0
  fi
  sleep "$WINDOW"
  b=$(ps -o cputime= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ -z "$b" ]] && { print -r -- "n/a"; return 0; }
  sa=$(ctime_to_secs "$a")
  sb=$(ctime_to_secs "$b")
  print -r -- "$sa $sb $WINDOW" | awk '{d=$2-$1; printf "%.2f", (d/$3)*100}'
}

# Deep mode. powermetrics is the only source for energy and wakeups.
deep_of() {
  local name="$1"
  print -u2 "  sampling powermetrics for ${WINDOW}s (sudo may prompt)..."
  sudo -n true 2>/dev/null || { print -u2 "  deep mode needs sudo. skipping."; return 1; }
  local n=$(( WINDOW / 2 ))
  (( n < 2 )) && n=2
  sudo powermetrics --samplers tasks,cpu_power,gpu_power,ane_power \
       -i 2000 -n "$n" 2>/dev/null \
    | grep -iE "$name|ANE Power|GPU Power|CPU Power|Combined Power|Energy Impact" \
    | tail -30
}

if (( DEEP )); then
  printf 'deep mode, window %ss, %d target(s)\n\n' "$WINDOW" "${#TARGETS[@]}"
else
  printf 'idle window %ss, %d target(s)\n\n' "$WINDOW" "${#TARGETS[@]}"
fi

printf '%-18s %11s %11s %11s\n' target "resident" "peak" "idle CPU"
printf '%s\n' "----------------------------------------------------------------"

for t in "${TARGETS[@]}"; do
  pid=$(resolve_pid "$t")
  if [[ -z "$pid" ]]; then
    printf '%-18s %10s %10s %10s\n' "$t" "-" "-" "not running"
    continue
  fi

  m=$(mem_of "$pid")
  if [[ -z "$m" ]]; then
    printf '%-18s %11s %11s %11s\n' "$t" "-" "-" "no access"
    continue
  fi
  res="${m%%|*}"
  peak="${m##*|}"
  [[ -z "$peak" ]] && peak="$res"
  cpu=$(cpu_of "$pid")

  printf '%-18s %8s MB %8s MB %10s %%\n' "$t" "$(to_mb "$res")" "$(to_mb "$peak")" "$cpu"

  if (( DEEP )); then
    deep_of "$t" | sed 's/^/    /'
    print
  fi
done

print
print "resident is phys_footprint now, peak is the high water mark since launch."
print "idle CPU is the exact average over the window, not a decaying average."
(( DEEP )) || print "run with -d under sudo for energy, CPU ms/s and timer wakeups."
