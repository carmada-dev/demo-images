FROM mcr.microsoft.com/devcontainers/base:dev-ubuntu

RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && apt-get install -y apt-transport-https curl gnupg lsb-release software-properties-common \
    && curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - && apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    && apt-get -y install packer jq dos2unix
