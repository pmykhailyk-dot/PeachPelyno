"""Verify a Cognito ID token against the pool's JWKS (Lab 6, Part 4, Step 3).

The agenda-parser Lambda runs outside the VPC and takes no API Gateway
authorizer, so it checks the bearer token itself - every call costs money,
and JWKS is a public key set anyone can fetch, including a function with no
NAT and no VPC endpoint.
"""

import os
from dataclasses import dataclass

import jwt
from jwt import PyJWKClient

from app.config import get_settings


class AuthError(Exception):
    """Any reason a token is rejected. The Lambda handler maps this to 401."""


@dataclass
class CognitoUser:
    sub: str
    email: str | None


_jwks_client: PyJWKClient | None = None


def _get_jwks_client(user_pool_id: str, region: str) -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        url = f"https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json"
        # Cached for the life of the execution environment: a warm Lambda
        # invocation never re-fetches the key set.
        _jwks_client = PyJWKClient(url, cache_keys=True)
    return _jwks_client


def verify_cognito_token(authorization: str) -> CognitoUser:
    """Verify a bearer ID token from Cognito's hosted login (Lab 4).

    Raises AuthError for anything not a valid, current, correctly issued
    token: missing header, bad signature, expired token, wrong audience or
    issuer, or a token that is not an ID token.
    """
    if not authorization.startswith("Bearer "):
        raise AuthError("missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise AuthError("missing bearer token")

    settings = get_settings()
    if not settings.auth_user_pool_id:
        raise AuthError("AUTH_USER_POOL_ID is not configured")
    region = os.environ.get("AWS_REGION", "us-east-1")
    issuer = f"https://cognito-idp.{region}.amazonaws.com/{settings.auth_user_pool_id}"

    try:
        signing_key = _get_jwks_client(settings.auth_user_pool_id, region).get_signing_key_from_jwt(
            token
        )
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=issuer,
            audience=settings.auth_client_id or None,
            options={"require": ["exp", "iss", "sub"]},
        )
    except jwt.PyJWTError as e:
        raise AuthError(f"invalid token: {e}") from e

    if claims.get("token_use") != "id":
        raise AuthError("not an ID token")

    return CognitoUser(sub=claims["sub"], email=claims.get("email"))
