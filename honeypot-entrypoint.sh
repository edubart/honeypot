#!/bin/sh

# Run the dapp repeatedly, restarting it if it exits unexpectedly.
while true; do
    /home/dapp/honeypot
    echo "[dapp] exited, reinitializing..."
done