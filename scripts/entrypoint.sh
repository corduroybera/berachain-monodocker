#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2024 Berachain Foundation
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

set -euxo pipefail

# function to resolve absolute path from relative
resolve_path() {
	if [[ "$1" =~ : ]]; then
        # treat as an address or url, return as is
        echo "$1"
	fi
    cd "$(dirname "$1")"
    local abs_path
    abs_path="$(pwd -P)/$(basename "$1")"
    echo "$abs_path"
}

CHAINID="bartio-beacon-80084"
MONIKER="docker-single-node"
LOGLEVEL="info"
CONSENSUS_KEY_ALGO="bls12_381"
HOMEDIR="./.tmp/beacond"
BEACOND_PATH="/app"
GETH_PATH="/app"

# Path variables
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json
ETH_GENESIS=$(resolve_path "./testing/files/eth-genesis.json")

# used to exit on first error (any non-zero exit code)
set -e


$BEACOND_PATH/beacond init $MONIKER \
    --chain-id $CHAINID \
    --home $HOMEDIR \
    --consensus-key-algo $CONSENSUS_KEY_ALGO

cp -f $BEACOND_PATH/networks/80084/*.toml $BEACOND_PATH/networks/80084/genesis.json ${HOMEDIR}/config
cp -f $BEACOND_PATH/networks/80084/kzg-trusted-setup.json ${HOMEDIR}/config

$BEACOND_PATH/beacond jwt generate --home $HOMEDIR

CL_SEEDS=$(sed -e '1d; :a;N;$!ba;s/\n/,/g' $BEACOND_PATH/networks/80084/cl-seeds.txt)

# Start the node (remove the --pruning=nothing flag if historical queries are not needed)
BEACON_START_CMD="$BEACOND_PATH/beacond start --pruning=nothing \
--beacon-kit.logger.log-level $LOGLEVEL --api.enabled-unsafe-cors \
--api.enable --api.swagger --minimum-gas-prices=0.0001abgt \
--home $HOMEDIR --beacon-kit.engine.jwt-secret-path $HOMEDIR/config/jwt.hex \
--beacon-kit.kzg.trusted-setup-path=$HOMEDIR/config/kzg-trusted-setup.json \
--beacon-kit.block-store-service.enabled --beacon-kit.block-store-service.pruner-enabled \
--beacon-kit.node-api.enabled --beacon-kit.node-api.logging \
--p2p.seeds=$CL_SEEDS"

eval $BEACON_START_CMD &

# execution flags
NETWORK_ID="${NETWORK_ID:-80084}"
TESTNET_ARGS="${TESTNET_ARGS:-}"
ENABLE_DB_SNAPSHOT="${ENABLE_DB_SNAPSHOT:-true}"
SYNC_MODE="${SYNC_MODE:-snap}" # snap, full
GC_MODE="${GC_MODE:-full}" # full, archive
VERBOSITY="${VERBOSITY:-3}"
GETH_PEERS="${GETH_PEERS:-50}"
CACHE_SIZE="${CACHE_SIZE:-4096}"
GETH_CACHE_SIZE="${GETH_CACHE_SIZE:-$CACHE_SIZE}"
MORE_ARGS="${MORE_ARGS:-}"
EXECUTION_HTTP_PORT="${EXECUTION_HTTP_PORT:-8545}"
PEERING_PORT="${PEERING_PORT:-30303}"
WEBSOCKET_PORT="${WEBSOCKET_PORT:-8546}"
JWT_TOKEN_FILE_PATH="${JWT_TOKEN_FILE_PATH:-$HOMEDIR/config/jwt.hex}"
EXECUTION_DATA_DIR="${EXECUTION_DATA_DIR:-/app/execution-data}"

EL_BOOT_NODES=$(sed -e '/^#/d; /^$/d; /^=/d' /app/networks/80084/el-bootnodes.txt | sed -e ':a;N;$!ba;s/\n/,/g')

mkdir -p /app/execution-data

/app/geth init --datadir /app/execution-data /app/networks/80084/eth-genesis.json

exec /app/geth --networkid "${NETWORK_ID}" \
    --syncmode="${SYNC_MODE}" \
    --gcmode="${GC_MODE}" \
    --snapshot="${ENABLE_DB_SNAPSHOT}" \
    --rpc.txfeecap=0 \
    --rpc.gascap=0 \
    --rpc.evmtimeout=15s \
    --rpc.batch-request-limit 100000 \
    --rpc.batch-response-max-size 500000000 \
    --http \
    --http.addr 0.0.0.0 \
    --http.vhosts=* \
    --http.api="engine,eth,web3,net,debug,txpool" \
    --http.port "${EXECUTION_HTTP_PORT}" \
    --port "${PEERING_PORT}" \
    --datadir "${EXECUTION_DATA_DIR}" \
    --ws \
    --ws.addr 0.0.0.0 \
    --ws.port "${WEBSOCKET_PORT}" \
    --ws.api="engine,eth,web3,net,debug,txpool" \
    --metrics \
    --metrics.addr 0.0.0.0 \
    --metrics.port 6060 \
    --pprof \
    --pprof.addr 0.0.0.0 \
    --pprof.port 6061 \
    --http.corsdomain=* \
    --authrpc.jwtsecret="${JWT_TOKEN_FILE_PATH}" \
    --authrpc.addr 0.0.0.0 \
    --authrpc.port 8551 \
    --authrpc.vhosts=* \
    --cache "${CACHE_SIZE}" \
    --bootnodes "${EL_BOOT_NODES}" \
    ${MORE_ARGS} ${TESTNET_ARGS}