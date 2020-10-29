#!/bin/bash

set -e

# Cleanup ethminer when the script exits
trap cleanup EXIT

cleanup() {
    if [ -n "$ethminer_pid" ] && ps -p $ethminer_pid > /dev/null; then
        # Signal ethminer to exit
        kill -s TERM $ethminer_pid
    fi
}

start_ethminer() {
    echo "Starting ethminer in the background..."
    ethminer -U -P $POOL_ADDR & 
    ethminer_pid=$!
}

start_ethminer

sleep 1

exec livepeer "$@"