"use client";

/** Where Cognito sends the browser back with ?code=&state=. AuthProvider
 *  (components/providers.tsx) wraps the whole app, sees the callback params
 *  on mount and exchanges the code for tokens itself; its onSigninCallback
 *  then sends the browser on to "/". This page only needs to exist and render
 *  something while that happens. */
export default function AuthCallbackPage() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <p className="text-sm text-muted-foreground">Completing sign-in…</p>
    </div>
  );
}
