#!/bin/bash
###################################################################################################
# This script is used to install helm and helmfile, and name your local kubernetes context into   #
# nice names.                                                                                     #    
# This is required to leverage the context feature of helmfile.                                   #
# The context names must be consistent between developers.                                        #
#                                                                                                 #
# This only needs to be run once                                                                  #
#                                                                                                 #
# ./setup.sh                                                                                      #
#                                                                                                 #
###################################################################################################

brew install helm
brew install helmfile

 kubectl config rename-context arn:aws:eks:ca-central-1:800095993820:cluster/notification-canada-ca-dev-eks-cluster dev
 kubectl config rename-context arn:aws:eks:ca-central-1:239043911459:cluster/notification-canada-ca-staging-eks-cluster staging
 kubectl config rename-context arn:aws:eks:ca-central-1:296255494825:cluster/notification-canada-ca-production-eks-cluster production
