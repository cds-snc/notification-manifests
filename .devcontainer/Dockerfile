FROM mcr.microsoft.com/vscode/devcontainers/base:0-debian@sha256:514d9a94b7f68d49bbf22f15dd82cb75cf0467763e96fc12682a07826bd13b04

ARG KUBENS_VERSION

RUN apt-get update \
    && apt-get -y install --no-install-recommends apt-utils 2>&1 \
    && apt-get -y install \
        build-essential \
        curl \
        fd-find \
        emacs \
        exa \
        git \
        iproute2 \
        less \
        libsodium-dev \
        lsb-release \
        man-db \
        manpages \
        openssh-client \
        postgresql-client \
        procps \
        net-tools \
        sudo \
        tldr \
        unzip \
        vim \
        zsh \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

COPY .devcontainer/scripts/notify-dev-entrypoint.sh /usr/local/bin/

# Install kubens
RUN git clone -b v${KUBENS_VERSION} --single-branch https://github.com/ahmetb/kubectx /opt/kubectx \
    && ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx \
    && ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Install AWS CLI v2 (non-interactive, install dir + symlink)
RUN curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip \
 && unzip /tmp/awscliv2.zip -d /tmp \
 && /tmp/aws/install -i /usr/local/aws-cli -b /usr/local/bin \
 && rm -rf /tmp/aws /tmp/awscliv2.zip

# Install Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Helmfile
RUN curl -LO https://github.com/helmfile/helmfile/releases/download/v0.151.0/helmfile_0.151.0_linux_amd64.tar.gz
RUN tar -zxvf helmfile_0.151.0_linux_amd64.tar.gz
RUN sudo chmod +x helmfile
RUN sudo mv helmfile /usr/local/bin/helmfile

# Install Helm plugins such as helm-diff, helm-secrets, helm-git
RUN helm plugin add https://github.com/databus23/helm-diff
RUN helm plugin install https://github.com/jkroepke/helm-secrets
RUN helm plugin install https://github.com/aslafy-z/helm-git
