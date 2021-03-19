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

start_cuda_mps_daemon() {
    echo "Starting CUDA MPS in the background..."
    nvidia-cuda-mps-control -d &
}

start_ethminer() {
    echo "Starting ethminer in the background..."
    ethminer -U -P $POOL_ADDR --cuda-streams $CUDA_STREAMS \
        --cuda-block-size $CUDA_BLOCK_SIZE --cuda-grid-size $CUDA_GRID_SIZE \
        --cuda-devices $NVIDIA_DEVICES &
    ethminer_pid=$!
}

if [ -n "$ENABLE_CUDA_MPS" ]; then
    export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
    export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
    export CUDA_VISIBLE_DEVICES=$NVIDIA_DEVICES

    start_cuda_mps_daemon
    unset CUDA_VISIBLE_DEVICES
    sleep 10
fi

start_ethminer
sleep 10

exec livepeer "$@"
