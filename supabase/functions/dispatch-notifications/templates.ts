export type NotificationEvent = {
  event_id: string;
  event_type: string;
  crew_id: string;
  payload: Record<string, unknown>;
};
export type PushContent = { title: string; body: string; data: Record<string, string> };
type Renderer = (payload: Record<string, unknown>) => { title: string; body: string };
const text = (value: unknown, fallback: string, max: number) =>
  typeof value === "string" && value.trim() ? value.trim().replace(/[\r\n\t]/g, " ").slice(0, max) : fallback;
const whole = (value: unknown, fallback: number) =>
  typeof value === "number" && Number.isInteger(value) && value > 0 ? value : fallback;

// Add new notification types here; queueing and transport remain unchanged.
const templates: Record<string, Renderer> = {
  crew_nudge: (payload) => ({
    title: "A little encouragement",
    body: `${text(payload.actor_name, "A crew member", 60)} is cheering you on. A small step on one pact today counts. You've got this!`,
  }),
  // The count is the claps this push announces, so the first name plus the
  // others reads as one round of applause rather than a running total.
  check_in_clapped: (payload) => {
    const others = whole(payload.clap_count, 1) - 1;
    const applause = others === 0 ? "" : others === 1 ? " and 1 other" : ` and ${others} others`;
    return {
      title: "Your crew is clapping",
      body: `${text(payload.actor_name, "A crew member", 60)}${applause} clapped your ${text(payload.pact_title, "pact", 120)} check-in.`,
    };
  },
  // One push per clapper, so there is no count to fold in; the achievement's
  // own words say which one, since an author may post a few in a day.
  achievement_clapped: (payload) => ({
    title: "Your crew is clapping",
    body: typeof payload.achievement_text === "string" && payload.achievement_text.trim()
      ? `${text(payload.actor_name, "A crew member", 60)} clapped your achievement: “${text(payload.achievement_text, "", 120)}”`
      : `${text(payload.actor_name, "A crew member", 60)} clapped your achievement.`,
  }),
  // The crew as the title, then who said what; just who and where when the
  // event carries no text.
  chat_message: (payload) => {
    const actor = text(payload.actor_name, "A crew member", 60);
    return {
      title: text(payload.crew_name, "Crew chat", 60),
      body: typeof payload.text === "string" && payload.text.trim()
        ? `${actor}: ${text(payload.text, "", 180)}`
        : `${actor} sent a message in ${text(payload.crew_name, "your crew", 60)}.`,
    };
  },
  pact_completed: (payload) => ({
    title: "A pact checked off!",
    body: `${text(payload.actor_name, "A crew member", 60)} completed ${text(payload.pact_title, "a pact", 120)}.`,
  }),
};

export function renderNotification(event: NotificationEvent): PushContent {
  const renderer = templates[event.event_type];
  if (!renderer) throw new Error("unsupported_notification_type");
  return { ...renderer(event.payload), data: {
    version: "1", type: event.event_type, notification_id: event.event_id,
    crew_id: event.crew_id,
    ...(typeof event.payload.pact_id === "string" ? { pact_id: event.payload.pact_id } : {}),
  } };
}
