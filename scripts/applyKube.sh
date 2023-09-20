retryCount=0
workDir=$1
kubeConfig=$2
pushd $workDir
until [ "$retryCount" -ge 5 ]
do
   kubectl apply -k . $kubeConfig  && break  # substitute your command here
   retryCount=$((retryCount+1)) 
   sleep 10
done
popd