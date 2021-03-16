#!/bin/bash

set -e

# Cleanup ethminer when the script exits
trap cleanup EXIT

export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log

cleanup() {
    if [ -n "$ethminer_pid" ] && ps -p $ethminer_pid > /dev/null; then
        # Signal ethminer to exit
        kill -s TERM $ethminer_pid
    fi
}

start_cuda_mps_daemon() {
    echo "Starting CUDA MPS in the background..."
    export CUDA_VISIBLE_DEVICES=$NVIDIA_DEVICES
    nvidia-cuda-mps-control -d &
}

start_ethminer() {
    echo "Starting ethminer in the background..."
    ethminer -U -P $POOL_ADDR --cuda-streams $LP_CUDA_STREAMS \
        --cuda-block-size $LP_CUDA_BLOCKSIZE --cuda-grid-size $LP_CUDA_GRIDSIZE \
        --cuda-devices $NVIDIA_DEVICES &
    ethminer_pid=$!
}

start_cuda_mps_daemon
sleep 1

start_ethminer
sleep 1

exec livepeer "$@"
