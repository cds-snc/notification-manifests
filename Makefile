decrypt-production:
	@cd env/production &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip .env.zip

decrypt-staging:
	@cd env/staging &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip .env.zip

decrypt-previous-staging:
	@cd env/staging &&\
	curl -L -o .previous.env.zip.enc.aws https://github.com/cds-snc/notification-manifests/blob/main/env/staging/.env.zip.enc.aws?raw=true > /dev/null 2>&1 &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env.zip &&\
	unzip .previous.env.zip &&\

decrypt-previous-production:
	@cd env/production &&\
	curl -L -o .previous.env.zip.enc.aws https://github.com/cds-snc/notification-manifests/blob/main/env/production/.env.zip.enc.aws?raw=true > /dev/null 2>&1 &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env.zip &&\
	unzip .previous.env.zip &&\

check-staging: decrypt-staging decrypt-previous-staging
	@cd env/staging &&\
	sed -i.bak 's/=.*/=<hidden>/' .env &&\
	sed -i.bak 's/=.*/=<hidden>/' .previous.env &&\
	rm .*.bak &&\
	diff -wB --old-line-format='-%L' --new-line-format='' --unchanged-line-format='' .previous.env .env | wc -l | xargs test 0 -eq

check-production: decrypt-production decrypt-previous-production
	@cd env/production &&\
	sed -i.bak 's/=.*/=<hidden>/' .env &&\
	sed -i.bak 's/=.*/=<hidden>/' .previous.env &&\
	rm *.bak &&\
	diff -wB --old-line-format='-%L' --new-line-format='' --unchanged-line-format='' .previous.env .env | wc -l | xargs test 0 -eq

diff-staging: decrypt-staging decrypt-previous-staging
	@cd env/staging &&\
	diff .previous.env .env

diff-production: decrypt-production decrypt-previous-production
	@cd env/production &&\
	diff .previous.env .env

encrypt-production:
	cd env/production &&\
	zip .env.zip .env &&\
	aws kms encrypt --key-id e9461cc1-4524-4b50-b6e6-583013da2904 --plaintext fileb://.env.zip --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.zip.enc.aws

encrypt-staging:
	cd env/staging &&\
	zip .env.zip .env &&\
	aws kms encrypt --key-id a92df413-fc30-4f3e-8047-7433e1a8ad02 --plaintext fileb://.env.zip --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.zip.enc.aws

production-debug:
	kubectl kustomize env/production

staging:
	kubectl apply -k env/staging --force

staging-clear:
	kubectl delete -k env/staging --force

staging-debug:
	kubectl kustomize env/staging