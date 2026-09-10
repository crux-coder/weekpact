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

// Add new notification types here; queueing and transport remain unchanged.
const templates: Record<string, Renderer> = {
  goal_completed: (payload) => ({
    title: "A goal checked off!",
    body: `${text(payload.actor_name, "A crew member", 60)} completed ${text(payload.goal_title, "a goal", 120)}.`,
  }),
};

export function renderNotification(event: NotificationEvent): PushContent {
  const renderer = templates[event.event_type];
  if (!renderer) throw new Error("unsupported_notification_type");
  return { ...renderer(event.payload), data: {
    version: "1", type: event.event_type, notification_id: event.event_id,
    crew_id: event.crew_id,
    ...(typeof event.payload.goal_id === "string" ? { goal_id: event.payload.goal_id } : {}),
  } };
}
