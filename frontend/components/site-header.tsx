"use client";

import { useAuth } from "react-oidc-context";

import { Button } from "@/components/ui/button";
import { cognitoSignOutUrl } from "@/lib/auth";

export function SiteHeader() {
  const auth = useAuth();

  const signOut = async () => {
    // Clears the local session first; the redirect then ends the hosted
    // login's session too, or the next sign-in would be silent.
    await auth.removeUser();
    window.location.assign(cognitoSignOutUrl());
  };

  return (
    <header className="sticky top-0 z-40 border-b border-border/70 bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 w-full max-w-5xl items-center gap-2 px-6 sm:px-8">
        <span
          aria-hidden
          className="grid size-6 place-items-center rounded-md bg-foreground font-heading text-[13px] leading-none font-semibold text-background"
        >
          S
        </span>
        <span className="font-heading text-[15px] font-semibold tracking-tight">
          Spry
        </span>

        <div className="ml-auto flex items-center gap-3">
          {auth.isLoading ? null : auth.isAuthenticated ? (
            <>
              <span className="text-sm text-muted-foreground">
                {auth.user?.profile.email}
              </span>
              <Button variant="outline" size="sm" onClick={signOut}>
                Sign out
              </Button>
            </>
          ) : (
            <Button size="sm" onClick={() => auth.signinRedirect()}>
              Sign in
            </Button>
          )}
        </div>
      </div>
    </header>
  );
}
