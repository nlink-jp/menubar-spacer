#!/bin/bash
# probe-remote.sh DIR — time the real settings file after a real write, with the
# user's spacing keys set aside, and put them back whatever happens.
set -u
DIR="$1"
K1=NSStatusItemSpacing
K2=NSStatusItemSelectionPadding
RESTORED=0
CLEARED=0
read_key()  { defaults -currentHost read -g "$1" 2>/dev/null || echo "<absent>"; }
read_type() { t=$(defaults -currentHost read-type -g "$1" 2>/dev/null) && echo "${t#Type is }" || echo "<absent>"; }
PRE1=$(read_key $K1); PRE2=$(read_key $K2); T1=$(read_type $K1); T2=$(read_type $K2)
echo "pre  $K1=$PRE1 ($T1)  $K2=$PRE2 ($T2)"
if [ "$T1" != integer ] || [ "$T2" != integer ]; then echo "pre-state is not two integers. Nothing touched."; exit 3; fi
restore() {
  [ "$RESTORED" = 1 ] && return
  [ "$CLEARED" = 1 ] || { RESTORED=1; return; }
  defaults -currentHost delete -g $K1 2>/dev/null
  defaults -currentHost write -g $K1 -int "$PRE1"
  defaults -currentHost write -g $K2 -int "$PRE2"
  RESTORED=1
  echo "[restore] wrote back $K1=$PRE1 $K2=$PRE2"
}
trap restore EXIT HUP INT TERM
echo "manual recovery if this dies: defaults -currentHost write -g $K1 -int $PRE1; defaults -currentHost write -g $K2 -int $PRE2"
cd "$DIR" || exit 2
swiftc -O probe3.swift -o probe3 > build.txt 2>&1 || { echo "BUILD FAILED"; tail -20 build.txt; exit 4; }
echo "== clear the keys"
CLEARED=1
defaults -currentHost delete -g $K1
defaults -currentHost delete -g $K2
sleep 1
./probe3 2>&1 | sed -E 's/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/<host uuid>/g'
restore
echo "post $K1=$(read_key $K1) ($(read_type $K1))  $K2=$(read_key $K2) ($(read_type $K2))"
