"use client";

import { useEffect } from "react";
import { useAuth } from "react-oidc-context";

/** The URL to submit for the lab. It starts the sign-in itself rather than
 *  being a hand-copied Cognito link, so the library's state and PKCE verifier
 *  - generated here, in the browser, before the redirect - are the ones the
 *  callback checks against. Already signed in, it just sends you home. */
export default function LoginPage() {
  const auth = useAuth();

  useEffect(() => {
    if (auth.isLoading) return;
    if (auth.isAuthenticated) {
      window.location.replace("/");
      return;
    }
    if (!auth.activeNavigator) {
      auth.signinRedirect();
    }
  }, [auth, auth.isLoading, auth.isAuthenticated, auth.activeNavigator]);

  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <p className="text-sm text-muted-foreground">Redirecting to sign in…</p>
    </div>
  );
}
