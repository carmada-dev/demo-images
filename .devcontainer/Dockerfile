FROM mcr.microsoft.com/devcontainers/base:dev-ubuntu

# register hashicorp repository
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - \
    && apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" 

# install required packages
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && apt-get -y install packer jq dos2unix


