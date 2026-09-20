#!/bin/bash
# hardware-test-guarded.sh [LOGDIR] — run the hardware tests on THIS Mac when its
# spacing keys are already set: the tests refuse to run unless both are absent,
# so the two values are set aside first and put back whatever happens. The
# restore is verified (values, types, and the app's own backup.json untouched).
#
# It writes this Mac's real preferences for a few seconds. Run it on a Mac where
# that is acceptable. Globals only: a trap handler sees nothing else.
set -u
DIR="${1:-$(mktemp -d)}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$DIR"
echo "logs: $DIR"
K1=NSStatusItemSpacing
K2=NSStatusItemSelectionPadding
BK="$HOME/Library/Application Support/jp.nlink.menubar-spacer/backup.json"
RESTORED=0
CLEARED=0

read_key()  { defaults -currentHost read -g "$1" 2>/dev/null || echo "<absent>"; }
read_type() { t=$(defaults -currentHost read-type -g "$1" 2>/dev/null) && echo "${t#Type is }" || echo "<absent>"; }
bk_hash()   { [ -f "$BK" ] && shasum -a 256 "$BK" | awk '{print $1}' || echo "<no file>"; }

PRE1=$(read_key $K1); PRE2=$(read_key $K2); T1=$(read_type $K1); T2=$(read_type $K2); H_PRE=$(bk_hash)
{ echo "pre  $K1=$PRE1 ($T1)"; echo "pre  $K2=$PRE2 ($T2)"; echo "pre  backup.json sha256=$H_PRE"; } | tee "$DIR/pre-state.txt"

if [ "$T1" != integer ] || [ "$T2" != integer ]; then
  echo "pre-state is not two integers — this script only knows how to put integers back. Nothing touched."
  exit 3
fi

restore() {
  [ "$RESTORED" = 1 ] && return
  [ "$CLEARED" = 1 ] || { RESTORED=1; return; }     # nothing was cleared, nothing to write
  defaults -currentHost write -g $K1 -int "$PRE1"
  defaults -currentHost write -g $K2 -int "$PRE2"
  RESTORED=1
  echo "[restore] wrote back $K1=$PRE1 $K2=$PRE2"
}
trap restore EXIT HUP INT TERM

echo "manual recovery if this dies: defaults -currentHost write -g $K1 -int $PRE1; defaults -currentHost write -g $K2 -int $PRE2"

cd "$REPO" || exit 2
echo "== build the tests first, with the keys still in place"
swift build --build-tests > "$DIR/build.txt" 2>&1 || { echo "BUILD FAILED"; tail -25 "$DIR/build.txt"; exit 4; }
echo "   built"

echo "== clear the keys"
CLEARED=1
defaults -currentHost delete -g $K1
defaults -currentHost delete -g $K2
echo "   now $K1=$(read_key $K1) $K2=$(read_key $K2)"
START=$(date +%s)

echo "== hardware E2E"
MENUBAR_SPACER_HARDWARE_TEST=1 swift test --filter HardwareEndToEndTests > "$DIR/e2e.txt" 2>&1
RC=$?
echo "   swift test exit=$RC"

restore
echo "   keys were cleared for $(( $(date +%s) - START )) s"

echo "== verify"
POST1=$(read_key $K1); POST2=$(read_key $K2); PT1=$(read_type $K1); PT2=$(read_type $K2); H_POST=$(bk_hash)
echo "post $K1=$POST1 ($PT1)"; echo "post $K2=$POST2 ($PT2)"; echo "post backup.json sha256=$H_POST"
if [ "$PRE1/$T1/$PRE2/$T2/$H_PRE" = "$POST1/$PT1/$POST2/$PT2/$H_POST" ]; then echo "RESTORED EXACTLY"; else echo "RESTORE MISMATCH"; fi
exit $RC
