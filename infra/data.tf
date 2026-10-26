# What this configuration reads but does not own: the account, and the
# outputs of the stacks that are still CloudFormation (backend, frontend).

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_cloudformation_stack" "backend" {
  name = "${var.project_name}-backend"
}

data "aws_cloudformation_stack" "frontend" {
  name = "${var.project_name}-frontend"
}

# The backend function is the source of the image the report builder and the
# agenda parser reuse (a different handler each), and of the VPC, subnets and
# security group the builder joins - Aurora's security group already lets
# that security group in.
data "aws_lambda_function" "backend" {
  function_name = data.aws_cloudformation_stack.backend.outputs["FunctionName"]
}

# The builder's DATABASE_URL comes from the backend's secret, not from a
# variable: nobody pastes a database password anywhere. It still ends up in
# the state and in the function's environment - see the ADR.
data "aws_secretsmanager_secret_version" "database_url" {
  secret_id = data.aws_cloudformation_stack.backend.outputs["DatabaseUrlSecretArn"]
}

# The S3 gateway endpoint routes through the VPC's main route table, so the
# builder reaches S3 with no NAT.
data "aws_route_table" "main" {
  vpc_id = one(data.aws_lambda_function.backend.vpc_config).vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  site_url    = trimsuffix(data.aws_cloudformation_stack.frontend.outputs["SiteUrl"], "/")
  image_uri   = data.aws_lambda_function.backend.image_uri
  backend_vpc = one(data.aws_lambda_function.backend.vpc_config)
}
