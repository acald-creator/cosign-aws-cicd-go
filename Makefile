NAME ?=phxvlabs-cosign-cicd
IMAGE ?=foto-sharing-app
VERSION ?=0.0.1-dev
GOLANG_VERSION ?=1.18.3
AWS_REGION ?=us-east-2
AWS_DEFAULT_REGION = ${AWS_REGION}
STACK_NAME = ${NAME}-stack
SAM_TEMPLATE = template.yml
PACKAGED_TEMPLATE = packaged.yml

REPO_INFO ?= $(shell git config --get remote.origin.url)
COMMIT_SHA ?= git-$(shell git rev-parse --short HEAD)
COSIGN_ROLE_NAME ?= "$(NAME)-codebuild"
ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text)
AWS_SDK_LOAD_CONFIG="true"

export AWS_REGION AWS_DEFAULT_REGION

GO_SRCS := $(wildcard cosign-ecs-function/*.go)

export

.PHONY: sam_build sam_package sam_deploy sam_local sam_local_debug sam_delete
cosign-ecs-function/cosign-ecs-function: $(GO_SRCS) cosign-ecs-function/go.mod cosign-ecs-function/go.sum
	cd ./cosign-ecs-function && go mod tidy && \
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o cosign-ecs-function .

go_build: cosign-ecs-function/cosign-ecs-function

sam_build:
	sam build --cached

sam_package: sam_build $(SAM_TEMPLATE)
	sam package \
		--template-file ${SAM_TEMPLATE} \
		--output-template-file ${PACKAGED_TEMPLATE} \
		--resolve-s3

sam_deploy: sam_package
	KEY_PEM=$$(cat cosign.pub; echo .); var=${var%.}; \
	sam deploy \
		--template-file ${SAM_TEMPLATE} \
		--resolve-s3 \
		--capabilities CAPABILITY_IAM \
		--stack-name ${STACK_NAME} \
		--parameter-overrides \
			"ParameterKey=KeyArn,ParameterValue=''" \
			"ParameterKey=KeyPem,ParameterValue='$${KEY_PEM}'"

sam_local: sam_build
	KEY_PEM=$$(cat cosign.pub; echo .); var=${var%.}; \
	sam local invoke \
		--event ${EVENT} \
		--template ${SAM_TEMPLATE} \
		--parameter-overrides \
			"ParameterKey=KeyArn,ParameterValue=''" \
			"ParameterKey=KeyPem,ParameterValue='$${KEY_PEM}'"

sam_local_debug: sam_build
	KEY_PEM=$$(cat cosign.pub; echo .); var=${var%.}; \
	sam local invoke \
		--event ${EVENT} \
		--template ${SAM_TEMPLATE} \
		--parameter-overrides \
			"ParameterKey=KeyArn,ParameterValue=''" \
			"ParameterKey=KeyPem,ParameterValue='$${KEY_PEM}'" \
		--debug

sam_delete:
	sam delete \
		--stack-name ${STACK_NAME} \
		--region ${AWS_REGION} \
		--no-prompts

.PHONY: run_signed_task run_unsigned_task task_status

run_signed_task:
	TASK_DEF_ARN=$$(cd terraform && terraform output -raw signed_task_arn) && \
	CLUSTER_ARN=$$(cd terraform && terraform output -raw cluster_arn) && \
	SUBNET_ID=$$(cd terraform && terraform output -raw subnet_id) && \
	aws ecs run-task \
		--task-definition $${TASK_DEF_ARN} \
		--cluster $${CLUSTER_ARN} \
		--network-configuration "awsvpcConfiguration={subnets=[$${SUBNET_ID}],assignPublicIp=ENABLED}" \
		--launch-type FARGATE \
		--no-cli-pager

run_unsigned_task:
	TASK_DEF_ARN=$$(cd terraform && terraform output -raw unsigned_task_arn) && \
	CLUSTER_ARN=$$(cd terraform && terraform output -raw cluster_arn) && \
	SUBNET_ID=$$(cd terraform && terraform output -raw subnet_id) && \
	aws ecs run-task \
		--task-definition $${TASK_DEF_ARN} \
		--cluster $${CLUSTER_ARN} \
		--network-configuration "awsvpcConfiguration={subnets=[$${SUBNET_ID}],assignPublicIp=ENABLED}" \
		--launch-type FARGATE \
		--no-cli-pager

task_status:
	CLUSTER_ARN=$$(cd terraform && terraform output -raw cluster_arn) && \
	echo "STOPPED tasks" && \
	aws ecs list-tasks --cluster $$CLUSTER_ARN --desired-status STOPPED && \
	echo "RUNNING tasks" && \
	aws ecs list-tasks --cluster $$CLUSTER_ARN --desired-status RUNNING

.PHONY: aws_acount
aws_acount:
	$(ACCOUNT_ID)

docker_build:
	 docker build https://github.com/acald-creator/foto-sharing-in-go.git\#main -t $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):$(VERSION)

.SILENT: ecr_auth
ecr_auth:
	docker login --username AWS -p $(shell aws ecr get-login-password --region $(AWS_REGION) ) $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

docker_push:
	docker push $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):$(VERSION)

ecr_scan:
	aws ecr start-image-scan --repository-name $(IMAGE) --image-id imageTag=$(VERSION)

ecr_scan_findings:
	aws ecr describe-image-scan-findings --repository-name $(IMAGE) --image-id imageTag=$(VERSION)

docker_run:
	docker run -it --platform $(PLATFORM) --rm $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):$(VERSION)

check:
	terraform -v  >/dev/null 2>&1 || echo "Terraform not installed" || exit 1 && \
	aws --version  >/dev/null 2>&1 || echo "AWS not installed" || exit 1 && \

tf_clean:
	cd terraform/ && \
	rm -rf .terraform \
	rm -rf plan.out

tf_init: 
	cd terraform/ && \
	terraform init

tf_get:
	cd terraform/ && \
	terraform get

tf_plan:
	cd terraform/ && \
	terraform plan -out=plan.out

tf_apply:
	cd terraform/ && \
	terraform apply -auto-approve

tf_destroy:
	cd terraform/ && \
	terraform destroy

sign: ecr_auth
	cosign sign --key awskms:///alias/$(NAME) $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):$(VERSION)

key_gen:
	cosign generate-key-pair --kms awskms:///alias/$(NAME) $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):$(VERSION)

verify: ecr_auth
	cosign verify --key cosign.pub $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):$(VERSION)

stop_tasks:
	CLUSTER_ARN=$$(cd terraform && terraform output -raw cluster_arn) && \
	aws ecs list-tasks --cluster $$CLUSTER_ARN --desired-status RUNNING --output text --query taskArns | \
		xargs --no-run-if-empty --max-args 1 \
			aws ecs stop-task --no-cli-pager --cluster $$CLUSTER_ARN --task