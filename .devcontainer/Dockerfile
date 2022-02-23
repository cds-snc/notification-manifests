FROM mcr.microsoft.com/vscode/devcontainers/base:0-debian

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

# Install kubens
RUN git clone -b v0.9.4 --single-branch https://github.com/ahmetb/kubectx /opt/kubectx \
    && ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx \
    && ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Install AWS cli
RUN curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && aws/install \
    && rm -rf \
        awscliv2.zip \
        aws \
        /usr/local/aws-cli/v2/*/dist/awscli/examples
    
COPY .devcontainer/scripts/notify-dev-entrypoint.sh /usr/local/bin/
