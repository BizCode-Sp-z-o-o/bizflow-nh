#!/bin/sh
# Start OpenBao server in background
bao server -config=/openbao/config/config.hcl &
BAO_PID=$!

# Wait for server to accept connections
# bao status returns exit code 2 when sealed — check JSON output, not exit code
for i in $(seq 1 30); do
    if bao status -address=http://127.0.0.1:8200 -format=json 2>&1 | grep -q '"storage_type"'; then
        break
    fi
    sleep 1
done

# Auto-unseal if key is provided
if [ -n "${OPENBAO_UNSEAL_KEY:-}" ]; then
    SEALED=$(bao status -address=http://127.0.0.1:8200 -format=json 2>&1 | grep -o '"sealed":[a-z]*' | cut -d: -f2 || echo "unknown")
    if [ "$SEALED" = "true" ]; then
        bao operator unseal -address=http://127.0.0.1:8200 "$OPENBAO_UNSEAL_KEY" >/dev/null 2>&1
        echo "OpenBao auto-unsealed."
    fi
fi

# Wait for server process
wait $BAO_PID
