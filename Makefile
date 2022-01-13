decrypt-production:
	@cd env/production &&\
	aws kms decrypt --ciphertext-blob fileb://.env.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env

decrypt-staging:
	@cd env/staging &&\
	aws kms decrypt --ciphertext-blob fileb://.env.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env

diff-staging: decrypt-staging
	@cd env/staging &&\
	curl -L -o .previous.env.enc.aws https://github.com/cds-snc/notification-manifests/blob/main/env/staging/.env.enc.aws?raw=true > /dev/null 2>&1 &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env &&\
	diff .previous.env .env

diff-production: decrypt-production
	@cd env/production &&\
	curl -L -o .previous.env.enc.aws https://github.com/cds-snc/notification-manifests/blob/main/env/production/.env.enc.aws?raw=true > /dev/null 2>&1 &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env &&\
	diff .previous.env .env

encrypt-production:
	cd env/production &&\
	aws kms encrypt --key-id e9461cc1-4524-4b50-b6e6-583013da2904 --plaintext fileb://.env --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.enc.aws

encrypt-staging:
	cd env/staging &&\
	aws kms encrypt --key-id a92df413-fc30-4f3e-8047-7433e1a8ad02 --plaintext fileb://.env --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.enc.aws

production-debug:
	kubectl kustomize env/production

staging:
	kubectl apply -k env/staging --force

staging-clear:
	kubectl delete -k env/staging --force

staging-debug:
	kubectl kustomize env/staging