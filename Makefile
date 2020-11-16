decrypt-staging:
	cd env/staging &&\
	aws kms decrypt --ciphertext-blob fileb://.env.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env

encrypt-staging:
	cd env/staging &&\
	aws kms encrypt --key-id a92df413-fc30-4f3e-8047-7433e1a8ad02 --plaintext fileb://.env --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.enc.aws

staging:
	kubectl apply -k env/staging --force

staging-clear:
	kubectl delete -k env/staging --force

staging-debug:
	kubectl kustomize env/staging