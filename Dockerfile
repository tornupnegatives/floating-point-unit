ARG base_tag=jammy
ARG base_img=mcr.microsoft.com/vscode/devcontainers/base:dev-${base_tag}

FROM --platform=linux/amd64 ${base_img} AS builder-install

RUN apt-get update --fix-missing && apt-get -y upgrade
RUN apt-get install -y \
    python3-pip \
    iverilog \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install cocotb
