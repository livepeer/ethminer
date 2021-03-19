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
    nvidia-cuda-mps-control -d
}

start_ethminer() {
    echo "Starting ethminer in the background..."
    ethminer -U -P $POOL_ADDR --cuda-streams $CUDA_STREAMS \
        --cuda-block-size $CUDA_BLOCK_SIZE --cuda-grid-size $CUDA_GRID_SIZE \
        --cuda-devices $NVIDIA_DEVICES \
        --api-bind 127.0.0.1:3333 &
    ethminer_pid=$!
}

if [ -n "$ENABLE_CUDA_MPS" ]; then
    export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
    export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
    export CUDA_VISIBLE_DEVICES=$NVIDIA_DEVICES

    start_cuda_mps_daemon
    unset CUDA_VISIBLE_DEVICES
    sleep 2
fi

start_ethminer
sleep 2
# Make sure DAG generation completes before starting livepeer
echo "Waiting for DAG generation..."
dag_generated=0
while [ $dag_generated == 0 ]
do
    # Assumptions:
    # 1. If hashrate is greater than 0 then DAG generation is complete
    # 2. The DAG will be loaded on the GPUs in parallel (default ethminer behavior) 
    # Note: If the 2nd assumption is not true then it is possible for the overall hashrate to be greater than 0, but the DAG
    # not to be loaded on all GPUs yet
    hashrate=$(echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstatdetail"}' | netcat -w 1 127.0.0.1 3333 | jq .result.mining.hashrate)
    if [ $hashrate != "\"0x00000000\"" ]
    then
        dag_generated=1
    else
        sleep 2
    fi
done

echo "DAG generation complete!"

exec livepeer "$@"
