#!/bin/bash
set -ex

###################################################################
# This script will get executed *once* the Docker container has
# been built. Commands that need to be executed with all available
# tools and the filesystem mount enabled should be located here.
###################################################################

# Define aliases
echo -e "\n\n# User's Aliases" >> ~/.zshrc
echo -e "alias fd=fdfind" >> ~/.zshrc
echo -e "alias l='ls -al --color'" >> ~/.zshrc
echo -e "alias ls='exa'" >> ~/.zshrc
echo -e "alias l='exa -alh'" >> ~/.zshrc
echo -e "alias ll='exa -alh@ --git'" >> ~/.zshrc
echo -e "alias lt='exa -al -T -L 2'" >> ~/.zshrc

# AWS cli autocomplete and aliases
echo -e "alias sso-staging='aws sso login --profile notify-staging'" >> ~/.zshrc
echo -e "alias sso-prod='aws sso login --profile notify-prod'" >> ~/.zshrc
echo -e "complete -C /usr/local/bin/aws_completer aws" >> ~/.zshrc

# Kubectl aliases and command autocomplete
echo -e "alias staging='export AWS_PROFILE=notify-staging && kubectl config use-context notify-staging'" >> ~/.zshrc
echo -e "alias prod='export AWS_PROFILE=notify-prod && kubectl config use-context notify-prod'" >> ~/.zshrc
echo -e "alias k='kubectl'" >> ~/.zshrc
echo -e "alias k-staging='aws eks --region ca-central-1 update-kubeconfig --name notification-canada-ca-staging-eks-cluster'" >> ~/.zshrc
echo -e "alias k-prod='aws eks --region ca-central-1 update-kubeconfig --name notification-canada-ca-production-eks-cluster'" >> ~/.zshrc
echo -e "source <(kubectl completion zsh)" >> ~/.zshrc
echo -e "complete -F __start_kubectl k" >> ~/.zshrc

cd /workspaces/notification-manifests

# kubent
 sh -c "$(curl -sSL https://git.io/install-kubent)"

# Warm up git index prior to display status in prompt
git status
