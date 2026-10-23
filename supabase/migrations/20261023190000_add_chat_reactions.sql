-- Reactions on crew chat messages: one emoji per member per message, from a
-- short fixed set.
--
-- Taking a reaction back clears the emoji rather than removing the row, the
-- same way unsending empties a message: Realtime can filter updates by crew,
-- but not deletes, so every change reaches the crew as an insert or update.

create table public.chat_reactions (
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- The message's crew, copied here for the read policy and the live filter.
  crew_id uuid not null references public.crews(id) on delete cascade,
  -- Null once taken back.
  emoji text check (emoji in ('👍', '❤️', '😂', '🔥', '👏', '😮')),
  updated_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index chat_reactions_crew_idx on public.chat_reactions(crew_id);
create index chat_reactions_user_idx on public.chat_reactions(user_id);

alter table public.chat_reactions enable row level security;
revoke all on public.chat_reactions from public, anon, authenticated;
grant select on public.chat_reactions to authenticated;
create policy chat_reactions_read on public.chat_reactions for select to authenticated
  using (private.is_crew_member(crew_id, (select auth.uid())));

-- Sets the caller's reaction to a message, or takes it back with null.
create function public.react_to_chat_message(target_message_id uuid, reaction text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  target_crew uuid;
begin
  select crew_id into target_crew from public.chat_messages
  where id = target_message_id and deleted_at is null;
  if auth.uid() is null or target_crew is null
    or not private.is_crew_member(target_crew, auth.uid()) then
    raise exception 'Crew membership required' using errcode = '42501';
  end if;
  insert into public.chat_reactions(message_id, user_id, crew_id, emoji)
  values (target_message_id, auth.uid(), target_crew, reaction)
  on conflict (message_id, user_id) do update
    set emoji = excluded.emoji, updated_at = now()
    where public.chat_reactions.emoji is distinct from excluded.emoji;
end;
$$;
revoke all on function public.react_to_chat_message(uuid, text) from public, anon;
grant execute on function public.react_to_chat_message(uuid, text) to authenticated;

-- An unsent message takes its reactions with it.
create function private.clear_unsent_chat_reactions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.chat_reactions
  set emoji = null, updated_at = now()
  where message_id = new.id and emoji is not null;
  return new;
end;
$$;
revoke all on function private.clear_unsent_chat_reactions() from public, anon, authenticated;
create trigger chat_message_unsent_reactions after update of deleted_at on public.chat_messages
for each row when (old.deleted_at is null and new.deleted_at is not null)
execute function private.clear_unsent_chat_reactions();

alter publication supabase_realtime add table public.chat_reactions;
