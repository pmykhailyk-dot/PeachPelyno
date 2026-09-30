"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";

const formSchema = z
  .object({
    title: z
      .string()
      .trim()
      .min(1, "Title is required")
      .max(200, "Title is too long"),
    date: z.string().min(1, "Pick a date"),
    start: z.string().min(1, "Pick a start time"),
    end: z.string().min(1, "Pick an end time"),
    attendee_count: z.coerce
      .number<string>()
      .int("Whole people only")
      .min(0, "Cannot be negative")
      .max(10_000, "That is a conference"),
  })
  .refine((v) => v.end > v.start, {
    path: ["end"],
    message: "Must end after it starts",
  });

type FormInput = z.input<typeof formSchema>;
type FormOutput = z.output<typeof formSchema>;

/** Local wall-clock date + time -> ISO 8601 in UTC ("...Z"), which the API requires. */
function toIso(date: string, time: string): string {
  return new Date(`${date}T${time}`).toISOString();
}

function today(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

export function MeetingFormDialog({ open, onOpenChange }: Props) {
  const queryClient = useQueryClient();
  const form = useForm<FormInput, unknown, FormOutput>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      title: "",
      date: "",
      start: "10:00",
      end: "10:30",
      attendee_count: "3",
    },
  });

  useEffect(() => {
    if (open) {
      form.reset({
        title: "",
        date: today(),
        start: "10:00",
        end: "10:30",
        attendee_count: "3",
      });
    }
  }, [open, form]);

  const mutation = useMutation({
    mutationFn: (values: FormOutput) =>
      api.createMeeting({
        title: values.title,
        starts_at: toIso(values.date, values.start),
        ends_at: toIso(values.date, values.end),
        attendee_count: values.attendee_count,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["meetings"] });
      toast.success("Meeting added");
      onOpenChange(false);
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const { errors } = form.formState;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>New meeting</DialogTitle>
          <DialogDescription>
            Times are in your local timezone.
          </DialogDescription>
        </DialogHeader>

        <form
          className="grid gap-4"
          onSubmit={form.handleSubmit((values) => mutation.mutate(values))}
        >
          <Field data-invalid={Boolean(errors.title)}>
            <FieldLabel htmlFor="title">Title</FieldLabel>
            <Input id="title" autoComplete="off" {...form.register("title")} />
            {errors.title && <FieldError errors={[errors.title]} />}
          </Field>

          <div className="grid gap-4 sm:grid-cols-3">
            <Field data-invalid={Boolean(errors.date)}>
              <FieldLabel htmlFor="date">Date</FieldLabel>
              <Input id="date" type="date" {...form.register("date")} />
              {errors.date && <FieldError errors={[errors.date]} />}
            </Field>
            <Field data-invalid={Boolean(errors.start)}>
              <FieldLabel htmlFor="start">Starts</FieldLabel>
              <Input id="start" type="time" {...form.register("start")} />
              {errors.start && <FieldError errors={[errors.start]} />}
            </Field>
            <Field data-invalid={Boolean(errors.end)}>
              <FieldLabel htmlFor="end">Ends</FieldLabel>
              <Input id="end" type="time" {...form.register("end")} />
              {errors.end && <FieldError errors={[errors.end]} />}
            </Field>
          </div>

          <Field data-invalid={Boolean(errors.attendee_count)}>
            <FieldLabel htmlFor="attendee_count">Attendees</FieldLabel>
            <Input
              id="attendee_count"
              type="number"
              min={0}
              inputMode="numeric"
              {...form.register("attendee_count")}
            />
            {errors.attendee_count && (
              <FieldError errors={[errors.attendee_count]} />
            )}
          </Field>

          <DialogFooter>
            <Button
              type="button"
              size="lg"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" size="lg" disabled={mutation.isPending}>
              {mutation.isPending ? "Saving..." : "Add meeting"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
