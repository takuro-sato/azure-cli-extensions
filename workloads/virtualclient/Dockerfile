FROM mcr.microsoft.com/mirror/docker/library/ubuntu:22.04
RUN apt update -y && \
    apt install -y bash python3 python3-pip curl sudo software-properties-common lsb-release git wget gnupg iptables && \
    pip install azure-kusto-data
WORKDIR /build
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DEBIAN_FRONTEND=noninteractive
COPY container_build_script.sh ./
COPY run_profiles.sh /
COPY VirtualClient /opt/virtualclient
COPY custom-profile-*.json /opt/virtualclient/profiles
COPY systemctl.fake.sh /usr/bin/systemctl
RUN chmod +x ./container_build_script.sh && ./container_build_script.sh

COPY startup.sh /
CMD ["/bin/bash", "/startup.sh"]
