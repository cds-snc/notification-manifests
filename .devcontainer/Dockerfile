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
RUN AWS_ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"; \
    curl -fsSL -o /tmp/awscliv2.zip "$AWS_ZIP_URL"; \
    if curl -fsSL -o /tmp/awscliv2.zip.sha256 "${AWS_ZIP_URL}.sha256"; then \
        expected=$(cut -d' ' -f1 /tmp/awscliv2.zip.sha256); \
        echo "${expected}  /tmp/awscliv2.zip" | sha256sum -c -; \
    else \
        echo "WARNING: checksum not found at ${AWS_ZIP_URL}.sha256; skipping verification" >&2; \
    fi; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install -i /usr/local/aws-cli -b /usr/local/bin; \
    rm -rf /tmp/aws /tmp/awscliv2.zip /tmp/awscliv2.zip.sha256

# Install Helm
RUN HELM_VERSION="v3.21.3"; \
    ARCH="linux-amd64"; \
    TARBALL="helm-${HELM_VERSION}-${ARCH}.tar.gz"; \
    URL="https://get.helm.sh/${TARBALL}"; \
    curl -fsSLO "$URL"; \
    curl -fsSLO "${URL}.sha256" || { echo "ERROR: checksum not found at ${URL}.sha256"; exit 1; }; \
    expected=$(cat "${TARBALL}.sha256"); \
    echo "${expected}  ${TARBALL}" | sha256sum -c -; \
    tar -zxvf "${TARBALL}"; \
    mv "${ARCH}"/helm /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    rm -rf "${TARBALL}" "${TARBALL}.sha256" "${ARCH}"

# Install Helmfile
RUN curl -LO https://github.com/helmfile/helmfile/releases/download/v0.151.0/helmfile_0.151.0_linux_amd64.tar.gz
RUN tar -zxvf helmfile_0.151.0_linux_amd64.tar.gz
RUN sudo chmod +x helmfile
RUN sudo mv helmfile /usr/local/bin/helmfile

# Install Helm plugins such as helm-diff, helm-secrets, helm-git
RUN helm plugin add https://github.com/databus23/helm-diff
RUN helm plugin install https://github.com/jkroepke/helm-secrets
RUN helm plugin install https://github.com/aslafy-z/helm-git
