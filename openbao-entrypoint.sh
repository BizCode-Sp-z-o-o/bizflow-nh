#!/bin/sh
# Redirect server output separately so it doesn't interfere with status checks
bao server -config=/openbao/config/config.hcl &
BAO_PID=$!

# Wait for HTTP listener (any response code means server is up)
for i in $(seq 1 30); do
    wget -q --spider --timeout=2 http://127.0.0.1:8200/v1/sys/seal-status 2>/dev/null && break
    # wget returns 0 only on 2xx; for 4xx/5xx check if we got any HTTP response
    if wget -S --spider --timeout=2 http://127.0.0.1:8200/v1/sys/seal-status 2>&1 | grep -q "HTTP/"; then
        break
    fi
    sleep 1
done

# Auto-unseal if key is provided
if [ -n "${OPENBAO_UNSEAL_KEY:-}" ]; then
    # Use compact JSON (-format=json produces single line for simple values after pipe)
    SEALED=$(bao status -address=http://127.0.0.1:8200 -format=json 2>/dev/null | grep '"sealed"' | grep -c 'true' || echo "0")
    if [ "$SEALED" -gt 0 ]; then
        bao operator unseal -address=http://127.0.0.1:8200 "$OPENBAO_UNSEAL_KEY" >/dev/null 2>&1
        echo "OpenBao auto-unsealed."
    fi
fi

wait $BAO_PID
