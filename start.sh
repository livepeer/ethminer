#!/bin/bash

set -e

# Cleanup ethminer when the script exits
trap cleanup EXIT

livepeer_args=$@

start_livepeer() {
    echo "Starting livepeer in the background..."
    livepeer $livepeer_args &
    livepeer_pid=$!
}

stop_livepeer() {
    echo "Stopping livepeer..."
    if [ -n "$livepeer_pid" ] && ps -p $livepeer_pid > /dev/null; then
        # Signal livepeer to exit
        kill -s TERM $livepeer_pid
    fi
}

start_cuda_mps_daemon() {
    echo "Starting CUDA MPS in the background..."
    nvidia-cuda-mps-control -d
}

start_ethminer() {
    echo "Starting ethminer in the background..."
    # --cuda-devices accepts a space delimited string, but NVIDIA_DEVICES is a comma delimited string
    ethminer -U -P $POOL_ADDR --cuda-streams $CUDA_STREAMS \
        --cuda-block-size $CUDA_BLOCK_SIZE --cuda-grid-size $CUDA_GRID_SIZE \
        --api-bind 127.0.0.1:3333 \
        --cuda-devices $(echo $NVIDIA_DEVICES | tr , " ") &
    ethminer_pid=$!
}

stop_ethminer() {
    echo "Stopping ethminer..."
    if [ -n "$ethminer_pid" ] && ps -p $ethminer_pid > /dev/null; then
        # Signal ethminer to exit
        kill -s TERM $ethminer_pid
    fi
}

cleanup() {
    stop_ethminer
    stop_livepeer
}

dag_generation_check() {
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
}

if [ $ENABLE_CUDA_MPS == "true" ]; then
    export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
    export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
    export CUDA_VISIBLE_DEVICES=$NVIDIA_DEVICES

    start_cuda_mps_daemon
    unset CUDA_VISIBLE_DEVICES
    sleep 2
fi

start_ethminer
sleep 2

sleep $DAG_GENERATION_TIME
dag_generation_check

start_livepeer

## Make sure we stop and start livepeer during any future DAG generation, which happens at an epoch_change
epoch_changes_old=$(echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstatdetail"}' | netcat -w 1 127.0.0.1 3333 | jq .result.mining.epoch_changes)
while true
do
    epoch_changes_new=$(echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstatdetail"}' | netcat -w 1 127.0.0.1 3333 | jq .result.mining.epoch_changes)
    if [[ $epoch_changes_new -gt $epoch_changes_old ]]
    then
        echo "New epoch detected"

        # Stop ethminer and let livepeer continue to run between 0 and $MAX_EPOCH_CHANGE_DELAY seconds
        # before restarting ethminer to generate the DAG for the new epoch
        stop_ethminer
        sleep $(( RANDOM % $MAX_EPOCH_CHANGE_DELAY ))s

        # Stop livepeer to make sure no transcoding occurs during DAG generation
        stop_livepeer
        sleep 2

        # Start ethminer which will generate the DAG for the new epoch
        start_ethminer
        sleep 2

        # Track epoch_changes after ethminer restarts
        epoch_changes_old=$(echo '{"id":0,"jsonrpc":"2.0","method":"miner_getstatdetail"}' | netcat -w 1 127.0.0.1 3333 | jq .result.mining.epoch_changes)

        # Start livepeer after ethminer finishes DAG generation
        sleep $DAG_GENERATION_TIME
        dag_generation_check

        start_livepeer
    else
        sleep 1
    fi
done
