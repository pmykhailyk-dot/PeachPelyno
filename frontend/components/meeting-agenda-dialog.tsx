"use client";

import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Plus, RotateCw, Sparkles, X } from "lucide-react";
import { useAuth } from "react-oidc-context";
import { toast } from "sonner";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { api, type Agenda, type Meeting } from "@/lib/api";
import { ParserError, type ParsedAgenda, parseAgenda } from "@/lib/parser";

type DraftItem = {
  topic: string;
  owner: string;
  minutes: string;
  suggested: boolean;
};
type DraftAction = {
  task: string;
  owner: string;
  due: string;
  suggested: boolean;
};

const emptyItem: DraftItem = {
  topic: "",
  owner: "",
  minutes: "",
  suggested: false,
};
const emptyAction: DraftAction = {
  task: "",
  owner: "",
  due: "",
  suggested: false,
};

function draftItemsFrom(agenda: Agenda | null): DraftItem[] {
  return (agenda?.items ?? []).map((i) => ({
    topic: i.topic,
    owner: i.owner ?? "",
    minutes: i.minutes != null ? String(i.minutes) : "",
    suggested: false,
  }));
}

function draftActionsFrom(agenda: Agenda | null): DraftAction[] {
  return (agenda?.action_items ?? []).map((a) => ({
    task: a.task,
    owner: a.owner ?? "",
    due: a.due ?? "",
    suggested: false,
  }));
}

function describeMentioned(parsed: ParsedAgenda): string | null {
  const parts: string[] = [];
  if (parsed.title) parts.push(`"${parsed.title}"`);
  if (parsed.starts_at) parts.push(parsed.starts_at);
  if (parsed.duration_minutes) parts.push(`${parsed.duration_minutes} min`);
  return parts.length > 0 ? parts.join(", ") : null;
}

type Props = {
  meeting: Meeting | null;
  onOpenChange: (open: boolean) => void;
};

/** Thin shell that owns the Dialog's open state and the data fetch. The
 *  actual form lives in AgendaFormBody, mounted only once the fetch has
 *  settled and keyed by meeting id - so it always starts from the right
 *  data with no effect required to "sync" it in after the fact. */
export function MeetingAgendaDialog({ meeting, onOpenChange }: Props) {
  const open = meeting !== null;
  const agendaQuery = useQuery({
    queryKey: ["agenda", meeting?.id],
    queryFn: () => api.getAgenda(meeting!.id),
    enabled: open,
  });

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onOpenChange(false)}>
      <DialogContent className="flex max-h-[85vh] flex-col sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>
            Agenda{meeting ? ` — ${meeting.title}` : ""}
          </DialogTitle>
          <DialogDescription>
            Paste the email, chat message or notes an agenda arrived as, or fill
            it in by hand.
          </DialogDescription>
        </DialogHeader>

        {meeting && agendaQuery.isPending && (
          <div className="grid gap-3">
            <Skeleton className="h-24 rounded-xl" />
            <Skeleton className="h-10 rounded-xl" />
          </div>
        )}

        {meeting && agendaQuery.isError && (
          <Alert variant="destructive">
            <AlertTitle>Could not load this meeting&apos;s agenda</AlertTitle>
            <AlertDescription className="flex flex-wrap items-center gap-3">
              {agendaQuery.error.message}
              <Button
                size="sm"
                variant="outline"
                onClick={() => agendaQuery.refetch()}
              >
                <RotateCw data-icon="inline-start" className="size-3.5" />
                Retry
              </Button>
            </AlertDescription>
          </Alert>
        )}

        {meeting && agendaQuery.isSuccess && (
          <AgendaFormBody
            key={meeting.id}
            meeting={meeting}
            initialAgenda={agendaQuery.data}
            onOpenChange={onOpenChange}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function AgendaFormBody({
  meeting,
  initialAgenda,
  onOpenChange,
}: {
  meeting: Meeting;
  initialAgenda: Agenda | null;
  onOpenChange: (open: boolean) => void;
}) {
  const auth = useAuth();
  const queryClient = useQueryClient();

  const [text, setText] = useState("");
  const [parsing, setParsing] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  const [items, setItems] = useState<DraftItem[]>(() =>
    draftItemsFrom(initialAgenda),
  );
  const [actions, setActions] = useState<DraftAction[]>(() =>
    draftActionsFrom(initialAgenda),
  );
  const [suggestionNote, setSuggestionNote] = useState<string | null>(null);
  // Seeded from the saved agenda, like the model and prompt version below: a
  // later save without a new parse must keep the suggestion, not erase it.
  const [aiSuggestion, setAiSuggestion] = useState<Record<
    string,
    unknown
  > | null>(initialAgenda?.ai_suggestion ?? null);
  const [aiModel, setAiModel] = useState<string | null>(
    initialAgenda?.ai_model ?? null,
  );
  const [aiPromptVersion, setAiPromptVersion] = useState<string | null>(
    initialAgenda?.ai_prompt_version ?? null,
  );

  const idToken = auth.user?.id_token;

  async function handleParse() {
    if (!text.trim()) {
      toast.error("Paste some text first");
      return;
    }
    if (!idToken) {
      toast.error("Sign in to use Paste an agenda");
      return;
    }
    const controller = new AbortController();
    abortRef.current = controller;
    setParsing(true);
    try {
      const result = await parseAgenda(text, idToken, controller.signal);
      const parsed = result.agenda;
      setItems(
        parsed.items.map((i) => ({
          topic: i.topic,
          owner: i.owner ?? "",
          minutes: i.minutes != null ? String(i.minutes) : "",
          suggested: true,
        })),
      );
      setActions(
        parsed.action_items.map((a) => ({
          task: a.task,
          owner: a.owner ?? "",
          due: a.due ?? "",
          suggested: true,
        })),
      );
      setAiSuggestion(parsed);
      setAiModel(result.model);
      setAiPromptVersion(result.prompt_version);
      setSuggestionNote(describeMentioned(parsed));
      toast.success("Parsed - check the form below, then save");
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") {
        // Cancelled on purpose - nothing to report.
      } else if (err instanceof ParserError) {
        toast.error(err.message);
      } else {
        toast.error("Could not parse that text");
      }
    } finally {
      setParsing(false);
      abortRef.current = null;
    }
  }

  function cancelParse() {
    abortRef.current?.abort();
  }

  const saveMutation = useMutation({
    mutationFn: () =>
      api.saveAgenda(meeting.id, {
        items: items
          .filter((i) => i.topic.trim())
          .map((i) => ({
            topic: i.topic.trim(),
            owner: i.owner.trim() || null,
            minutes: i.minutes.trim() ? Number(i.minutes) : null,
          })),
        action_items: actions
          .filter((a) => a.task.trim())
          .map((a) => ({
            task: a.task.trim(),
            owner: a.owner.trim() || null,
            due: a.due.trim() || null,
          })),
        ai_suggestion: aiSuggestion,
        ai_model: aiModel,
        ai_prompt_version: aiPromptVersion,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["agenda", meeting.id] });
      toast.success("Agenda saved");
      onOpenChange(false);
    },
    onError: (error: Error) => toast.error(error.message),
  });

  function touchItem(index: number, patch: Partial<DraftItem>) {
    setItems((prev) =>
      prev.map((item, i) =>
        i === index ? { ...item, ...patch, suggested: false } : item,
      ),
    );
  }

  function touchAction(index: number, patch: Partial<DraftAction>) {
    setActions((prev) =>
      prev.map((action, i) =>
        i === index ? { ...action, ...patch, suggested: false } : action,
      ),
    );
  }

  return (
    <>
      <div className="grid gap-5 overflow-y-auto px-1">
        <Field>
          <FieldLabel htmlFor="paste">Paste an agenda</FieldLabel>
          <Textarea
            id="paste"
            rows={5}
            placeholder="Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв ..."
            value={text}
            onChange={(e) => setText(e.target.value)}
            disabled={parsing}
          />
          <div className="flex items-center gap-2">
            {parsing ? (
              <>
                <Button type="button" variant="outline" disabled>
                  <Loader2
                    data-icon="inline-start"
                    className="size-4 animate-spin"
                  />
                  Parsing…
                </Button>
                <Button type="button" variant="ghost" onClick={cancelParse}>
                  Cancel
                </Button>
              </>
            ) : (
              <Button type="button" variant="outline" onClick={handleParse}>
                <Sparkles data-icon="inline-start" className="size-4" />
                Parse
              </Button>
            )}
            {!idToken && (
              <span className="text-xs text-muted-foreground">
                Sign in to use Parse — you can still fill the form by hand.
              </span>
            )}
          </div>
          {suggestionNote && (
            <p className="text-xs text-muted-foreground">
              Also mentioned: {suggestionNote}
            </p>
          )}
        </Field>

        <div className="grid gap-2">
          <div className="flex items-center justify-between">
            <FieldLabel>Agenda items</FieldLabel>
            <Button
              type="button"
              size="sm"
              variant="ghost"
              onClick={() => setItems((prev) => [...prev, { ...emptyItem }])}
            >
              <Plus data-icon="inline-start" className="size-3.5" />
              Add item
            </Button>
          </div>
          {items.length === 0 && (
            <p className="text-sm text-muted-foreground">
              No agenda items yet.
            </p>
          )}
          {items.map((item, index) => (
            <div key={index} className="flex items-start gap-2">
              <div className="flex flex-1 items-center gap-2">
                <Input
                  aria-label="Topic"
                  placeholder="Topic"
                  value={item.topic}
                  onChange={(e) => touchItem(index, { topic: e.target.value })}
                />
                {item.suggested && (
                  <Badge variant="info" className="shrink-0">
                    suggested
                  </Badge>
                )}
              </div>
              <Input
                aria-label="Owner"
                placeholder="Owner"
                className="w-32 shrink-0"
                value={item.owner}
                onChange={(e) => touchItem(index, { owner: e.target.value })}
              />
              <Input
                aria-label="Minutes"
                placeholder="min"
                type="number"
                min={1}
                className="w-20 shrink-0"
                value={item.minutes}
                onChange={(e) => touchItem(index, { minutes: e.target.value })}
              />
              <Button
                type="button"
                size="icon"
                variant="ghost"
                aria-label="Remove item"
                onClick={() =>
                  setItems((prev) => prev.filter((_, i) => i !== index))
                }
              >
                <X className="size-4" />
              </Button>
            </div>
          ))}
        </div>

        <div className="grid gap-2">
          <div className="flex items-center justify-between">
            <FieldLabel>Action items</FieldLabel>
            <Button
              type="button"
              size="sm"
              variant="ghost"
              onClick={() =>
                setActions((prev) => [...prev, { ...emptyAction }])
              }
            >
              <Plus data-icon="inline-start" className="size-3.5" />
              Add action
            </Button>
          </div>
          {actions.length === 0 && (
            <p className="text-sm text-muted-foreground">
              No action items yet.
            </p>
          )}
          {actions.map((action, index) => (
            <div key={index} className="flex items-start gap-2">
              <div className="flex flex-1 items-center gap-2">
                <Input
                  aria-label="Task"
                  placeholder="Task"
                  value={action.task}
                  onChange={(e) => touchAction(index, { task: e.target.value })}
                />
                {action.suggested && (
                  <Badge variant="info" className="shrink-0">
                    suggested
                  </Badge>
                )}
              </div>
              <Input
                aria-label="Owner"
                placeholder="Owner"
                className="w-32 shrink-0"
                value={action.owner}
                onChange={(e) => touchAction(index, { owner: e.target.value })}
              />
              <Input
                aria-label="Due"
                type="date"
                className="w-40 shrink-0"
                value={action.due}
                onChange={(e) => touchAction(index, { due: e.target.value })}
              />
              <Button
                type="button"
                size="icon"
                variant="ghost"
                aria-label="Remove action item"
                onClick={() =>
                  setActions((prev) => prev.filter((_, i) => i !== index))
                }
              >
                <X className="size-4" />
              </Button>
            </div>
          ))}
        </div>
      </div>

      <DialogFooter>
        <Button
          type="button"
          size="lg"
          variant="outline"
          onClick={() => onOpenChange(false)}
          disabled={saveMutation.isPending}
        >
          Close
        </Button>
        <Button
          type="button"
          size="lg"
          onClick={() => saveMutation.mutate()}
          disabled={saveMutation.isPending}
        >
          {saveMutation.isPending ? "Saving..." : "Save agenda"}
        </Button>
      </DialogFooter>
    </>
  );
}
