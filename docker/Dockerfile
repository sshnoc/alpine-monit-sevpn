# https://github.com/SoftEtherVPN/SoftetherVPN-docker/blob/master/Dockerfile
# https://github.com/siomiz/SoftEtherVPN/tree/master

# BUILDER
# FROM --platform=$BUILDPLATFORM alpine-core as builder
FROM alpine:3.18 AS builder

RUN mkdir /usr/local/src && \
        apk update && apk add binutils --no-cache \
        build-base readline-dev openssl-dev ncurses-dev git \
        cmake zlib-dev libsodium-dev gnu-libiconv 

ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so
WORKDIR /usr/local/src
RUN git clone https://github.com/SoftEtherVPN/SoftEtherVPN.git
# RUN git clone -b ${GIT_TAG} https://github.com/SoftEtherVPN/SoftEtherVPN.git
# ENV USE_MUSL=YES
RUN cd SoftEtherVPN && \
	git submodule init && \
	git submodule update && \
    ./configure && \
	make -C build

# PRODUCTION
FROM alpine-monit
LABEL maintainer="sshnoc.com"

# Copy startup files
COPY ./*.sh /

RUN apk add --no-cache \
        readline openssl libsodium gnu-libiconv \
        rsync dnsmasq iproute2 curl && \
        mkdir /sevpn && \
        chmod +x /*.sh && \
        rm -rf /var/cache/apk/*

COPY ./etc/monit.d/*.conf /etc/monit.d/

ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so
ENV LD_LIBRARY_PATH /root
WORKDIR /sevpn
COPY --from=builder /usr/local/src/SoftEtherVPN/build/vpnserver /usr/local/src/SoftEtherVPN/build/vpncmd /usr/local/src/SoftEtherVPN/build/libcedar.so /usr/local/src/SoftEtherVPN/build/libmayaqua.so /usr/local/src/SoftEtherVPN/build/hamcore.se2 ./
COPY --from=builder /usr/local/src/SoftEtherVPN/build/libcedar.so /usr/local/src/SoftEtherVPN/build/libmayaqua.so ../lib/

EXPOSE 443/tcp 992/tcp 1194/tcp 1194/udp 5555/tcp 5555/udp 500/udp 4500/udp
