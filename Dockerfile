FROM nvidia/cuda:10.1-devel-ubuntu18.04 as builder

WORKDIR /root

RUN apt-get update \
    && apt-get install -qy build-essential git cmake perl software-properties-common mesa-common-dev libidn11-dev python3-requests python3-git

COPY . .

RUN git submodule update --init --recursive \
    && mkdir build \
    && cd build \
    && cmake .. \
    && cmake --build . \
    && make install 

FROM nvidia/cuda:10.1-base

COPY --from=builder /root/build/ethminer/ethminer /usr/local/bin/ethminer

ENTRYPOINT ["ethminer"]