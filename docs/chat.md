# Crew chat

Each crew has one chat, on the **Chat** tab between Home and Crews. It follows
the crew Home is showing; switching crews in either place switches both.

## What it does

- Realtime messages via Supabase `postgres_changes` on `chat_messages`.
- Typing indicator and "who is here" via broadcast and presence on a private
  Realtime channel, `chat:<crew id>`, authorised against crew membership.
- Grouped bubbles, day separators, times, sent / seen ticks ("Seen by Ana").
- Sending state, failed messages with retry or discard, delete for everyone,
  copy, loading older messages on scroll, jump to newest.
- An unread dot on the Chat tab, from `chat_unread_counts()`.
- Push notifications for new messages (below).

## Privacy

Messages are stored as plain text in `chat_messages`. What keeps them private:

- **Row-level security.** Only a crew's current members can read or post in
  its chat, and only the sender can unsend a message. Realtime feeds follow
  the same policies.
- **TLS** on every connection, and Supabase's encryption of the database at
  rest.

Messages are not end-to-end encrypted: anyone with database access, such as
the project's operators, can read them. In exchange, every device a member
signs in on reads the whole history straight away, with no keys to pass
around, and pushes can show the message itself.

## Rollout

1. Apply `supabase/migrations/20261021130000_add_crew_chat.sql`. It adds the
   tables to the `supabase_realtime` publication and creates the
   `realtime.messages` policies for the private channel.
2. Ship the app build. Older builds simply do not show the tab.

3. Apply `supabase/migrations/20261021140000_add_chat_push_notifications.sql`
   and deploy `dispatch-notifications` with the `chat_message` template.

## Push notifications

A new message pushes the crew's other members, with the crew's name as the
title and "Ana: running late" as the body (the first 200 characters). Tapping
it opens Chat on that crew. Unsending a message removes its text from the
queued push event, and cancels the push if it has not gone out.

- **Push only.** Chat pushes do not go into the in-app notification list; the
  Chat tab's unread dot already covers them. The trigger
  (`private.notify_chat_message`) writes delivery rows itself instead of using
  `private.enqueue_crew_notification`, which also writes the inbox.
- **Throttled.** At most one push per recipient per crew every three minutes
  (`private.chat_push_window()`). Later messages in the window are left to the
  unread dot.
- **Not while reading.** Each chat push waits 15 seconds before it can be sent
  (`private.chat_push_grace()`). An open chat marks arrivals read within a
  moment, so if the recipient's `chat_reads.last_read_at` has reached the
  message by then, the push is cancelled. A cancelled push does not use up the
  window. A push is also cancelled if the message is unsent first.
- The dispatcher runs every minute, so the grace period adds no delay anyone
  would notice.

Checks: `node tool/test_chat_push_database.mjs` (with `PGLITE_MODULE` set if
needed), `node tool/test_notification_sender.mjs` and
`flutter test test/chat_push_test.dart`.
