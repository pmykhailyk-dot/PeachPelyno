# Sign-in (Lab 4, was infra/auth.yaml): a Cognito user pool with managed
# login, email + password and "Continue with Google". The user pool holds
# every account that signed up - it was imported, never re-created, and a
# change to a "forces replacement" attribute here (name, username_attributes,
# schema) would delete all of them.

resource "aws_cognito_user_pool" "main" {
  name           = "${var.project_name}-users"
  user_pool_tier = "ESSENTIALS"

  # Sign in with an email, not a separate chosen username.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Self sign-up stays on - the lab requires it, and the lecturer signs up
  # with their own account.
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }
}

# Google has to exist before a client can list it as a supported provider.
resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
    # Filled in by Cognito for every Google provider; listed so a plan does
    # not offer to remove them.
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  # Without this a Google user arrives with no email, and the header has
  # nothing to show.
  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    username       = "sub"
  }
}

resource "aws_cognito_user_pool_client" "frontend" {
  name         = "${var.project_name}-frontend"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client: a browser cannot keep a secret. generate_secret is left
  # unset on purpose - the client was imported with it unset, and any value
  # there forces a new client (a new client id in every built frontend).
  explicit_auth_flows           = []
  prevent_user_existence_errors = "ENABLED"

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO", aws_cognito_identity_provider.google.provider_name]

  # Registered with and without a trailing slash: CloudFront serves
  # /auth/callback and /auth/callback/ the same, but Cognito matches the
  # redirect_uri byte for byte.
  callback_urls = [
    "${local.site_url}/auth/callback",
    "${local.site_url}/auth/callback/",
    "${var.local_origin}/auth/callback",
    "${var.local_origin}/auth/callback/",
  ]
  logout_urls = [
    "${local.site_url}/",
    local.site_url,
    "${var.local_origin}/",
    var.local_origin,
  ]
}

# A Cognito domain prefix is unique across every AWS account; the account id
# makes a collision practically impossible.
resource "aws_cognito_user_pool_domain" "main" {
  domain                = "${var.project_name}-${local.account_id}"
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

# A version-2 domain shows nothing without a branding - Cognito's own default
# styling here, not a hand-built theme.
resource "aws_cognito_managed_login_branding" "main" {
  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.frontend.id
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.main]
}
