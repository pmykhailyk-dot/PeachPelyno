export function SiteHeader() {
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
      </div>
    </header>
  );
}
