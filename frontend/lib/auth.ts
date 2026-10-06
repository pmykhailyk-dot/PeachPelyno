import type { AuthProviderProps } from "react-oidc-context";

/** Values are baked in at build time by scripts/deploy-frontend.sh (which
 *  reads them from the auth stack's outputs) - see NEXT_PUBLIC_COGNITO_* in
 *  .env.example. Blank locally until `make deploy-auth` has run once. */
const cognitoClientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? "";

export const cognitoAuthConfig: AuthProviderProps = {
  authority: process.env.NEXT_PUBLIC_COGNITO_AUTHORITY ?? "",
  client_id: cognitoClientId,
  redirect_uri: process.env.NEXT_PUBLIC_COGNITO_REDIRECT_URI ?? "",
  response_type: "code",
  scope: "openid email profile",
  // Drop ?code=&state= from the address bar and land back on the site once
  // the token exchange is done.
  onSigninCallback: () => {
    window.history.replaceState({}, document.title, "/");
    window.location.assign("/");
  },
};

const cognitoDomain = process.env.NEXT_PUBLIC_COGNITO_DOMAIN ?? "";
const logoutUri = process.env.NEXT_PUBLIC_COGNITO_LOGOUT_URI ?? "/";

/** Cognito does not implement OIDC's standard end-session endpoint. Call this
 *  after clearing the local session (useAuth().removeUser()) to also end the
 *  hosted-login session, or a silent re-login would sign the user right back
 *  in on their next visit. */
export function cognitoSignOutUrl(): string {
  const params = new URLSearchParams({
    client_id: cognitoClientId,
    logout_uri: logoutUri,
  });
  return `${cognitoDomain}/logout?${params.toString()}`;
}
