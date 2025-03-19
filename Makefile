decrypt-production:
	@cd env/production &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip -o .env.zip

decrypt-staging:
	@cd env/staging &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip -o .env.zip

decrypt-dev:
	@cd env/dev &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip -o .env.zip

decrypt-sandbox:
	@cd env/sandbox &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip -o .env.zip

decrypt-scratch:
	@cd env/scratch &&\
	aws kms decrypt --ciphertext-blob fileb://.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .env.zip &&\
	unzip -o .env.zip

decrypt-previous-dev:
	@cd env/dev &&\
	git cat-file blob origin/main:env/dev/.env.zip.enc.aws > .previous.env.zip.enc.aws &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env.zip &&\
	unzip -o .previous.env.zip && mv .env .previous.env

decrypt-previous-staging:
	@cd env/staging &&\
	git cat-file blob origin/main:env/staging/.env.zip.enc.aws > .previous.env.zip.enc.aws &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env.zip &&\
	unzip -o .previous.env.zip && mv .env .previous.env

decrypt-previous-production:
	@cd env/production &&\
	git cat-file blob origin/main:env/production/.env.zip.enc.aws > .previous.env.zip.enc.aws &&\
	aws kms decrypt --ciphertext-blob fileb://.previous.env.zip.enc.aws --output text --query Plaintext --region ca-central-1 | base64 --decode > .previous.env.zip &&\
	unzip -o .previous.env.zip && mv .env .previous.env

check-staging: decrypt-previous-staging decrypt-staging
	@cd env/staging &&\
	sed -i.bak 's/=.*/=<hidden>/' .env &&\
	sed -i.bak 's/=.*/=<hidden>/' .previous.env &&\
	rm .*.bak &&\
	diff -wB --old-line-format='-%L' --new-line-format='' --unchanged-line-format='' .previous.env .env | wc -l | xargs test 0 -eq

check-production:decrypt-previous-production decrypt-production 
	@cd env/production &&\
	sed -i.bak 's/=.*/=<hidden>/' .env &&\
	sed -i.bak 's/=.*/=<hidden>/' .previous.env &&\
	rm *.bak &&\
	diff -wB --old-line-format='-%L' --new-line-format='' --unchanged-line-format='' .previous.env .env | wc -l | xargs test 0 -eq

diff-dev: decrypt-previous-dev decrypt-dev
	@cd env/dev &&\
	diff .previous.env .env

diff-staging: decrypt-previous-staging decrypt-staging
	@cd env/staging &&\
	diff .previous.env .env

diff-production: decrypt-previous-production decrypt-production
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

encrypt-dev:
	cd env/dev &&\
	zip .env.zip .env &&\
	aws kms encrypt --key-id a48012af-07a2-419d-8200-a1a8a2378ecf --plaintext fileb://.env.zip --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.zip.enc.aws	

encrypt-sandbox:
	cd env/sandbox &&\
	zip .env.zip .env &&\
	aws kms encrypt --key-id 1c729503-4bcc-445a-b2ff-bd0146282271 --plaintext fileb://.env.zip --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.zip.enc.aws	

encrypt-scratch:
	cd env/scratch &&\
	zip .env.zip .env &&\
	aws kms encrypt --key-id 7d2595b2-65ad-4093-b1df-b820b473d81c --plaintext fileb://.env.zip --output text --query CiphertextBlob --region ca-central-1 | base64 --decode > .env.zip.enc.aws	

production-debug:
	cd helmfile
	source getContext.sh
	helmfile -e production template

staging:
	kubectl apply -k env/staging --force

staging-clear:
	kubectl delete -k env/staging --force

staging-debug:
	cd helmfile
	source getContext.sh
	helmfile -e staging template

env-vars:
	@cat $(ENV_FILE) | xargs -0 -L1 | grep ":" | cut -f1 -d":" | sort | tr "\n" "|"
