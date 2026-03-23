#!/bin/sh
# Start OpenBao server in background
bao server -config=/openbao/config/config.hcl &
BAO_PID=$!

# Wait for server to be ready
for i in $(seq 1 30); do
    if bao status -address=http://127.0.0.1:8200 >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Auto-unseal if key is provided
if [ -n "${OPENBAO_UNSEAL_KEY:-}" ]; then
    SEALED=$(bao status -address=http://127.0.0.1:8200 -format=json 2>/dev/null | grep -o '"sealed":[a-z]*' | cut -d: -f2 || echo "unknown")
    if [ "$SEALED" = "true" ]; then
        bao operator unseal -address=http://127.0.0.1:8200 "$OPENBAO_UNSEAL_KEY" >/dev/null 2>&1
        echo "OpenBao auto-unsealed."
    fi
fi

# Wait for server process
wait $BAO_PID
