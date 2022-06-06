# Cosign usage with AWS CI/CD services

> NOTE: Inspiration from Chainguard. Please note that there will be changes to scripts and an intention to migrate parts of Terraform to Pulumi
* https://github.com/strongjz/cosign-aws-codepipeline
* https://github.com/chainguard-dev/cosign-ecs-verify

Services
1. CodePipeline
    * S3 Bucket
    * IAM Role
    * IAM Role Policy
2. AWS CodeCommit Repository
3. CodeBuild Project
    * S3 Bucket
    * IAM Role
    * CloudWatch Log Group and Stream
4. ECR - Container Registry
5. KMS - Asymmetric key use for Cosign key signing

Create IAM user and ensure that user has `AWSCodeCommitPowerUser` in order to create repositories and push repositories. Generate the CodeCommit credentials for later use.

Create an S3 bucket for Terraform remote state storage

`aws s3 mb s3://<BUCKET_NAME>`

Initialize Terraform

`make tf_init`

Create the Terraform plan

`make tf_plan`

Apply the changes

`make tf_apply`

If you built and deploy from Terraform tfstate, you may have resources that are still hanging around.

1. Empty the s3 buckets
`aws s3 rm s3://${var.name}-cosign-cicd-cb --recursive && \
    aws s3 rm s3://${var.name}-cosign-cicd-cp --recursive`

2. Import existing buckets if Terraform complains that there are s3 buckets still available if the bucket are not empty
`terraform import aws_s3_bucket.codebuild_s3 ${var.name}-cosign-cicd-cb && \
    terraform import aws_s3_bucket.codepipeline_bucket ${var.name}-cosign-cicd-cp`

Push your current repository to AWS CodeCommit by creating a new remote

```bash
export AWS_CODE_COMMIT_REPO=https://git-codecommit.us-east-2.amazonaws.com/v1/repos/foto-sharing-cicd
git remote add aws $AWS_CODE_COMMIT_REPO
git push aws main
```

3. You can obtain the copy of the public key from AWS KMS. You can copy to verify the signed image.

4. Here are the commands to run the `unsigned` and `signed` task. Please note that the ECR images are immutable so in order to test, you will need to deploy a newer version of the docker image for verification.

```bash
make run_unsigned_task
make task_status
```