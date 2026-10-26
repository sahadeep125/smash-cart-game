#!/bin/bash
# Runs a host and a client in two headless Godot processes and compares results.
# Usage: tests/run_net_test.sh [lan|online]   (GODOT=/path/to/godot)
set -u
GODOT=${GODOT:-godot}
TRANSPORT=${1:-lan}
DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d)
EXTRA=""
MOCK_PID=""
if [ "$TRANSPORT" = "online" ]; then
  python3 "$DIR/tests/mock_realtime.py" 8787 > "$OUT/mock.log" 2>&1 &
  MOCK_PID=$!
  sleep 1
  EXTRA="--url=http://127.0.0.1:8787"
fi
"$GODOT" --headless --path "$DIR" res://tests/net_test.tscn -- --role=host --transport=$TRANSPORT $EXTRA > "$OUT/host.log" 2>&1 &
HOST_PID=$!
"$GODOT" --headless --path "$DIR" res://tests/net_test.tscn -- --role=client --transport=$TRANSPORT $EXTRA > "$OUT/client.log" 2>&1 &
CLIENT_PID=$!
wait $HOST_PID; HOST_RC=$?
wait $CLIENT_PID; CLIENT_RC=$?
[ -n "$MOCK_PID" ] && kill $MOCK_PID 2>/dev/null
grep -hE "\] (PASS|FAIL)|NET RESULT|SCRIPT ERROR" "$OUT/host.log" "$OUT/client.log"
H=$(grep "^RESULTS" "$OUT/host.log"); C=$(grep "^RESULTS" "$OUT/client.log")
echo "host   $H"; echo "client $C"
if [ -n "$H" ] && [ "$H" = "$C" ]; then echo "PASS results identical on host and client"; else echo "FAIL results differ"; HOST_RC=1; fi
[ -n "$MOCK_PID" ] && echo "mock server messages: $(grep -c . "$OUT/mock.log")"
echo "logs: $OUT"
[ $HOST_RC -eq 0 ] && [ $CLIENT_RC -eq 0 ]
