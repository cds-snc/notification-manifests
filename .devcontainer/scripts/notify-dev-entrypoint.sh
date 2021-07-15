#!/bin/bash
set -ex 

###################################################################
# This script will get executed *once* the Docker container has 
# been built. Commands that need to be executed with all available
# tools and the filesystem mount enabled should be located here. 
###################################################################

# Define aliases
echo -e "\n\n# User's Aliases" >> ~/.profile
echo -e "alias fd=fdfind" >> ~/.profile
echo -e "alias l='ls -al --color'" >> ~/.profile
echo -e "alias ls='exa'" >> ~/.profile
echo -e "alias l='exa -alh'" >> ~/.profile
echo -e "alias ll='exa -alh@ --git'" >> ~/.profile
echo -e "alias lt='exa -al -T -L 2'" >> ~/.profile

# Warm up git index 
git status
