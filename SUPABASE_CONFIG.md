# GeoRemind — full database setup
---
`Paste this into the Supabase SQL Editor.`
`I created this file with the help of AI by asking it to make a concise and easy to follow sql script for recreating my db. Mine was created via trial and error, fixes, crashes and other issues.`

-- ---------------------------------------------------------------------------
`-- Helpers`
-- ---------------------------------------------------------------------------

`create or replace function public.is_group_member(_group_id uuid)`
`returns boolean`
`language sql`
`stable`
`security definer`
`set search_path = public`
`as $$`
`  select exists (`
    select 1
    from public.group_members
    where group_id = _group_id
      and user_id = auth.uid()
`  );`
`$$;`

`revoke all on function public.is_group_member(uuid) from public, anon;`
`grant execute on function public.is_group_member(uuid) to authenticated;`

-- ---------------------------------------------------------------------------
`-- Tables`
-- ---------------------------------------------------------------------------

`create table if not exists public.profiles (`
`  id uuid primary key references auth.users (id) on delete cascade,`
`  username text unique not null,`
`  avatar_url text,`
`  created_at timestamptz not null default now()`
`);`

`create table if not exists public.groups (`
`  id uuid primary key default gen_random_uuid(),`
`  name text not null,`
`  owner_id uuid not null references public.profiles (id) on delete cascade,`
`  created_at timestamptz not null default now()`
`);`

`create table if not exists public.group_members (`
`  group_id uuid not null references public.groups (id) on delete cascade,`
`  user_id uuid not null references public.profiles (id) on delete cascade,`
`  role text not null default 'member' check (role in ('owner', 'member')),`
`  joined_at timestamptz not null default now(),`
`  primary key (group_id, user_id)`
`);`

`create table if not exists public.reminders (`
`  id uuid primary key default gen_random_uuid(),`
`  owner_id uuid not null references public.profiles (id) on delete cascade,`
`  group_id uuid references public.groups (id) on delete set null,`
`  title text not null,`
`  description text not null default '',`
`  latitude double precision not null,`
`  longitude double precision not null,`
`  radius double precision not null,`
`  is_active boolean not null default true,`
`  notify_on_entry boolean not null default true,`
`  notify_on_exit boolean not null default false,`
`  repeats boolean not null default true,`
`  weekdays smallint not null default 127,`
`  active_from_minutes integer,`
`  active_to_minutes integer,`
`  created_at timestamptz not null default now()`
`);`

`create table if not exists public.group_invites (`
`  id uuid primary key default gen_random_uuid(),`
`  group_id uuid not null references public.groups (id) on delete cascade,`
`  code text unique not null,`
`  created_by uuid not null references public.profiles (id) on delete cascade,`
`  created_at timestamptz not null default now(),`
`  expires_at timestamptz,`
`  max_uses int,`
`  use_count int not null default 0`
`);`

`create index if not exists reminders_owner_idx on public.reminders (owner_id);`
`create index if not exists reminders_group_idx on public.reminders (group_id);`
`create index if not exists group_members_user_idx on public.group_members (user_id);`
`create index if not exists group_invites_group_idx on public.group_invites (group_id);`

-- ---------------------------------------------------------------------------
`-- Auth → profile`
-- ---------------------------------------------------------------------------

`create or replace function public.handle_new_user()`
`returns trigger`
`language plpgsql`
`security definer`
`set search_path = public`
`as $$`
`declare`
`  base text;`
`  candidate text;`
`begin`
`  base := coalesce(`
    nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
    split_part(coalesce(new.email, 'user'), '@', 1),
    'user'
`  );`
`  base := left(regexp_replace(base, '[^a-zA-Z0-9._-]', '', 'g'), 24);`
`  if base = '' then`
    base := 'user';
`  end if;`

`  candidate := base;`
`  while exists (select 1 from public.profiles where username = candidate) loop`
    candidate := base || '_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4);
`  end loop;`

`  insert into public.profiles (id, username, avatar_url)`
`  values (`
    new.id,
    candidate,
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
`  );`
`  return new;`
`end;`
`$$;`

`drop trigger if exists on_auth_user_created on auth.users;`
`create trigger on_auth_user_created`
`  after insert on auth.users`
`  for each row execute function public.handle_new_user();`

-- ---------------------------------------------------------------------------
`-- Group owner becomes a member`
-- ---------------------------------------------------------------------------

`create or replace function public.handle_new_group()`
`returns trigger`
`language plpgsql`
`security definer`
`set search_path = public`
`as $$`
`begin`
`  insert into public.group_members (group_id, user_id, role)`
`  values (new.id, new.owner_id, 'owner')`
`  on conflict do nothing;`
`  return new;`
`end;`
`$$;`

`drop trigger if exists on_group_created on public.groups;`
`create trigger on_group_created`
`  after insert on public.groups`
`  for each row execute function public.handle_new_group();`

-- ---------------------------------------------------------------------------
`-- Kick / leave → those reminders become Personal (kept by the owner)`
-- ---------------------------------------------------------------------------

`create or replace function public.handle_group_member_removed()`
`returns trigger`
`language plpgsql`
`security definer`
`set search_path = public`
`as $$`
`begin`
`  update public.reminders`
`  set group_id = null`
`  where owner_id = old.user_id`
    and group_id = old.group_id;
`  return old;`
`end;`
`$$;`

`drop trigger if exists on_group_member_removed on public.group_members;`
`create trigger on_group_member_removed`
`  after delete on public.group_members`
`  for each row execute function public.handle_group_member_removed();`

-- ---------------------------------------------------------------------------
`-- RPCs used by the app`
-- ---------------------------------------------------------------------------

`create or replace function public.join_group_with_code(invite_code text)`
`returns uuid`
`language plpgsql`
`security definer`
`set search_path = public`
`as $$`
`declare`
`  inv public.group_invites%rowtype;`
`  uid uuid := auth.uid();`
`  normalized text := upper(trim(invite_code));`
`begin`
`  if uid is null then`
    raise exception 'Not authenticated';
`  end if;`

`  if normalized = '' then`
    raise exception 'Invalid invite code';
`  end if;`

`  select * into inv`
`  from public.group_invites`
`  where code = normalized`
`  for update;`

`  if not found then`
    raise exception 'Invalid invite code';
`  end if;`

`  if inv.expires_at is not null and inv.expires_at < now() then`
    raise exception 'Invite expired';
`  end if;`

`  if inv.max_uses is not null and inv.use_count >= inv.max_uses then`
    raise exception 'Invite already used';
`  end if;`

`  if exists (`
    select 1 from public.group_members
    where group_id = inv.group_id and user_id = uid
`  ) then`
    return inv.group_id;
`  end if;`

`  insert into public.group_members (group_id, user_id, role)`
`  values (inv.group_id, uid, 'member');`

`  update public.group_invites`
`  set use_count = use_count + 1`
`  where id = inv.id;`

`  return inv.group_id;`
`end;`
`$$;`

`revoke all on function public.join_group_with_code(text) from public, anon;`
`grant execute on function public.join_group_with_code(text) to authenticated;`

`create or replace function public.delete_own_account()`
`returns void`
`language plpgsql`
`security definer`
`set search_path = public`
`as $$`
`declare`
`  uid uuid := auth.uid();`
`begin`
`  if uid is null then`
    raise exception 'Not authenticated';
`  end if;`
`  -- Avatars are removed from the client via the Storage API.`
`  delete from auth.users where id = uid;`
`end;`
`$$;`

`revoke all on function public.delete_own_account() from public, anon;`
`grant execute on function public.delete_own_account() to authenticated;`

-- ---------------------------------------------------------------------------
`-- RLS`
-- ---------------------------------------------------------------------------

`alter table public.profiles enable row level security;`
`alter table public.groups enable row level security;`
`alter table public.group_members enable row level security;`
`alter table public.reminders enable row level security;`
`alter table public.group_invites enable row level security;`

`-- profiles`
`drop policy if exists "profiles readable by authenticated" on public.profiles;`
`create policy "profiles readable by authenticated"`
`  on public.profiles for select`
`  to authenticated`
`  using (true);`

`drop policy if exists "profiles updatable by owner" on public.profiles;`
`create policy "profiles updatable by owner"`
`  on public.profiles for update`
`  to authenticated`
`  using (id = auth.uid())`
`  with check (id = auth.uid());`

`-- groups`
`drop policy if exists "groups readable by members" on public.groups;`
`create policy "groups readable by members"`
`  on public.groups for select`
`  to authenticated`
`  using (owner_id = auth.uid() or public.is_group_member(id));`

`drop policy if exists "groups insertable by owner" on public.groups;`
`create policy "groups insertable by owner"`
`  on public.groups for insert`
`  to authenticated`
`  with check (owner_id = auth.uid());`

`drop policy if exists "groups updatable by owner" on public.groups;`
`create policy "groups updatable by owner"`
`  on public.groups for update`
`  to authenticated`
`  using (owner_id = auth.uid())`
`  with check (owner_id = auth.uid());`

`drop policy if exists "groups deletable by owner" on public.groups;`
`create policy "groups deletable by owner"`
`  on public.groups for delete`
`  to authenticated`
`  using (owner_id = auth.uid());`

`-- group_members (no client inserts — join is join_group_with_code / handle_new_group)`
`drop policy if exists "group_members readable by members" on public.group_members;`
`drop policy if exists "group_members insertable by group owner" on public.group_members;`
`create policy "group_members readable by members"`
`  on public.group_members for select`
`  to authenticated`
`  using (public.is_group_member(group_id));`

`drop policy if exists "group_members removable by self or owner" on public.group_members;`
`create policy "group_members removable by self or owner"`
`  on public.group_members for delete`
`  to authenticated`
`  using (`
    user_id = auth.uid()
    or exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
`  );`

`-- reminders`
`drop policy if exists "reminders readable by owner or group members" on public.reminders;`
`create policy "reminders readable by owner or group members"`
`  on public.reminders for select`
`  to authenticated`
`  using (`
    owner_id = auth.uid()
    or (
      group_id is not null
      and public.is_group_member(group_id)
    )
`  );`

`drop policy if exists "reminders writable by owner" on public.reminders;`
`create policy "reminders writable by owner"`
`  on public.reminders for insert`
`  to authenticated`
`  with check (`
    owner_id = auth.uid()
    and (
      group_id is null
      or public.is_group_member(group_id)
    )
`  );`

`drop policy if exists "reminders editable by owner" on public.reminders;`
`create policy "reminders editable by owner"`
`  on public.reminders for update`
`  to authenticated`
`  using (owner_id = auth.uid())`
`  with check (`
    owner_id = auth.uid()
    and (
      group_id is null
      or public.is_group_member(group_id)
    )
`  );`

`drop policy if exists "reminders deletable by owner" on public.reminders;`
`create policy "reminders deletable by owner"`
`  on public.reminders for delete`
`  to authenticated`
`  using (owner_id = auth.uid());`

`-- invites — owner only; redeem is join_group_with_code`
`drop policy if exists "invites readable by group owner" on public.group_invites;`
`create policy "invites readable by group owner"`
`  on public.group_invites for select`
`  to authenticated`
`  using (`
    exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
`  );`

`drop policy if exists "invites insertable by group owner" on public.group_invites;`
`create policy "invites insertable by group owner"`
`  on public.group_invites for insert`
`  to authenticated`
`  with check (`
    created_by = auth.uid()
    and exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
`  );`

`drop policy if exists "invites deletable by group owner" on public.group_invites;`
`create policy "invites deletable by group owner"`
`  on public.group_invites for delete`
`  to authenticated`
`  using (`
    exists (
      select 1 from public.groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
`  );`

-- ---------------------------------------------------------------------------
`-- Storage: public avatars bucket  ({userId}/avatar.jpg)`
-- ---------------------------------------------------------------------------

`insert into storage.buckets (id, name, public)`
`values ('avatars', 'avatars', true)`
`on conflict (id) do update set public = true;`

`drop policy if exists "avatar images are publicly readable" on storage.objects;`
`create policy "avatar images are publicly readable"`
`  on storage.objects for select`
`  using (bucket_id = 'avatars');`

`drop policy if exists "users can upload own avatar" on storage.objects;`
`create policy "users can upload own avatar"`
`  on storage.objects for insert`
`  to authenticated`
`  with check (`
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
`  );`

`drop policy if exists "users can update own avatar" on storage.objects;`
`create policy "users can update own avatar"`
`  on storage.objects for update`
`  to authenticated`
`  using (`
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
`  );`

`drop policy if exists "users can delete own avatar" on storage.objects;`
`create policy "users can delete own avatar"`
`  on storage.objects for delete`
`  to authenticated`
`  using (`
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
`  );`

-- ---------------------------------------------------------------------------
`-- Realtime (list tab / map refresh when someone else adds a pin)`
-- ---------------------------------------------------------------------------

`do $$`
`begin`
`  alter publication supabase_realtime add table public.reminders;`
`exception`
`  when duplicate_object then null;`
`end $$;``

## Guest mode doesn't need any of this. Sync, groups, avatars, and sign-in do.
---
1. SQL

New project → SQL Editor → paste supabase/schema.sql → Run.

That creates profiles, groups, group_members, reminders, group_invites, RLS, the join/delete RPCs, the kick-to-personal trigger, the avatars bucket, and adds reminders to realtime.

2. Auth (dashboard)

Authentication → URL Configuration

Site URL: georemind://auth-callback (or leave the default and just add the redirect)

Redirect URLs, add exactly: georemind://auth-callback

Authentication → Sign In / Providers

Email: on. Confirm email is your call. Off = people get in immediately, but the same address can be grabbed by someone else before Google linking works. On = you need working mail (and you will hit the free-tier rate limit if you spam it).

Google: on. In Google Cloud, authorized redirect is
https://<project-ref>.supabase.co/auth/v1/callback
Paste Client ID + secret here.

Facebook: same idea, Facebook Login redirect
https://<project-ref>.supabase.co/auth/v1/callback

Allow manual linking: on. That's Settings → Link Google / Facebook while already signed in. Without it, linkIdentity 422s.

Skip Apple unless you have a paid Apple Developer account.

3. What you should see after
- Table Editor: five public tables.
- Storage: avatars, public.
- Authentication → Users: empty until the first sign-up. First user should get a profiles row automatically.


If sign-in opens Safari instead of the in-app sheet, the URL scheme isn't registered or Redirect URLs doesn't include georemind://auth-callback. If avatars fail, the bucket isn't public or the policy on storage.objects didn't run.

## Recurring reminders (existing projects)

Run this in the SQL Editor if `reminders` already exists:

```sql
alter table public.reminders
  add column if not exists repeats boolean not null default true,
  add column if not exists weekdays smallint not null default 127,
  add column if not exists active_from_minutes integer,
  add column if not exists active_to_minutes integer;
```

`weekdays` is a bitmask (Mon = 1, Tue = 2, … Sun = 64). `127` = every day.
`active_from_minutes` / `active_to_minutes` are minutes from midnight in the phone's local time. Null = any hour.

