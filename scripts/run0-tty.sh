#!/bin/sh
if command -v pkttyagent >/dev/null 2>&1 && [ -t 0 ]; then
    timeout --foreground 900 pkttyagent --process $$ &
    sleep 0.3
fi
exec run0 "$@"
