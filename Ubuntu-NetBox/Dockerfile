FROM ubuntu:20.04

LABEL maintainer="tstanley933@gmail.com"
LABEL version="0.2"
LABEL description="This is a custom Docker image for troubleshooting network connectivity inside of kubernetes."

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update

RUN apt install -y \
    iputils-ping \
    tcpdump \
    dnsutils \
    git \
    net-tools \
    iproute2 \
    curl \
    jq \
    wget