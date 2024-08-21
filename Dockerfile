# syntax=docker/dockerfile:1
#
# Copyright (C) 2022, Berachain Foundation. All rights reserved.
# See the file LICENSE for licensing terms.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#######################################################
###           Stage 0 - Build Arguments             ###
#######################################################

# Beacon-Kit Build args
ARG GO_VERSION=1.23.0
ARG RUNNER_IMAGE=alpine:3.20
ARG BUILD_TAGS="netgo,muslc,blst,bls12381,pebbledb"
ARG NAME=beacond
ARG APP_NAME=beacond
ARG DB_BACKEND=pebbledb
ARG CMD_PATH=./beacond/cmd
ARG BEACON_KIT_REPO_URL=https://github.com/berachain/beacon-kit.git
ARG BEACON_KIT_COMMIT_HASH=dd2155c66cdb5d92fbcd59636736a4a90db15c47

# Geth Build args
ARG GETH_REPO_URL=https://github.com/ethereum/go-ethereum.git
ARG GETH_COMMIT_HASH=a9523b6428238a762e1a1e55e46ead47630c3a23


#######################################################
###         Stage 1 - Build Beacon-Kit              ###
#######################################################

FROM golang:${GO_VERSION}-alpine3.20 AS beacon-kit-build

ARG BEACON_KIT_REPO_URL
ARG BEACON_KIT_COMMIT_HASH

# Install git and build dependencies
RUN apk add --no-cache git make ncurses gcc musl-dev linux-headers

# Set working directory
WORKDIR /app

# Clone the beacon-kit repository
RUN git clone ${BEACON_KIT_REPO_URL} \
    && cd beacon-kit \
    && git checkout ${BEACON_KIT_COMMIT_HASH} \
    && go mod download

# Build Beacon-Kit with specific tags
RUN cd beacon-kit \
    && make build

RUN mv /app/beacon-kit/build/bin/beacond /app/beacond \
    && mkdir /app/networks \
    && mv /app/beacon-kit/testing/networks/* /app/networks \
    && cd /app \
    && rm -rf beacon-kit

#######################################################
###         Stage 2 - Build Geth                    ###
#######################################################

# Build Geth in a stock Go builder container
FROM golang:${GO_VERSION}-alpine3.20 as geth-build

RUN apk add --no-cache gcc musl-dev linux-headers git

WORKDIR /app

ARG GETH_REPO_URL
ARG GETH_COMMIT_HASH

RUN git clone ${GETH_REPO_URL} \
    && cd go-ethereum \
    && git checkout ${GETH_COMMIT_HASH} \
    && go mod download

# Build Geth
RUN cd go-ethereum/ && go run build/ci.go install -static ./cmd/geth

RUN mv go-ethereum/build/bin/geth /app/geth \
    && cd /app \
    && rm -rf go-ethereum

#######################################################
###        Stage 3 - Prepare the Final Image        ###
#######################################################

FROM ${RUNNER_IMAGE}

RUN apk add --no-cache ca-certificates lz4 curl-dev

WORKDIR /app

# Copy over built executable into a fresh container
COPY --from=beacon-kit-build /app/beacond /app/beacond
COPY --from=geth-build /app/geth /app/geth
COPY --from=beacon-kit-build /app/networks /app/networks
COPY scripts/ /app/scripts

RUN mkdir -p /root/jwt /root/kzg && \
    apk add --no-cache bash sed curl

EXPOSE 30303
EXPOSE 8545
EXPOSE 8546

ENTRYPOINT [ "/app/scripts/entrypoint.sh" ]