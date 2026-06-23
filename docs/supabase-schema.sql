-- MotionDock Supabase schema
-- Run this in the Supabase SQL editor, then enable Google Auth in Supabase Auth settings.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  email text,
  avatar_url text,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles are readable" on public.profiles;
create policy "profiles are readable"
on public.profiles for select
to anon, authenticated
using (true);

drop policy if exists "users can upsert own profile" on public.profiles;
create policy "users can upsert own profile"
on public.profiles for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile"
on public.profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create table if not exists public.marketplace_moderators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.marketplace_moderators enable row level security;

create or replace function public.is_marketplace_moderator(check_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.marketplace_moderators
    where marketplace_moderators.user_id = check_user_id
  );
$$;

drop policy if exists "moderators can read own moderator grant" on public.marketplace_moderators;
create policy "moderators can read own moderator grant"
on public.marketplace_moderators for select
to authenticated
using (auth.uid() = user_id or public.is_marketplace_moderator(auth.uid()));

create table if not exists public.wallpapers (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null check (kind in ('video', 'gif')),
  filename text not null,
  file_size integer not null default 0,
  storage_path text not null unique,
  uploader_id uuid not null references public.profiles(id) on delete cascade,
  uploader_name text,
  moderation_status text not null default 'pending' check (moderation_status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now()
);

alter table public.wallpapers
  add column if not exists moderation_status text not null default 'pending',
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists description text,
  add column if not exists thumbnail_url text,
  add column if not exists video_url text,
  add column if not exists category text,
  add column if not exists downloads integer not null default 0,
  add column if not exists likes_count integer not null default 0,
  add column if not exists uploader_confirmed_rights boolean not null default false,
  add column if not exists report_count integer not null default 0,
  add column if not exists is_hidden boolean not null default false;

alter table public.wallpapers
  alter column moderation_status set default 'approved';

update public.wallpapers
set moderation_status = 'approved'
where moderation_status = 'pending';

alter table public.wallpapers
  drop constraint if exists wallpapers_moderation_status_check;
alter table public.wallpapers
  add constraint wallpapers_moderation_status_check
  check (moderation_status in ('pending', 'approved', 'rejected'));
alter table public.wallpapers
  drop constraint if exists wallpapers_report_count_check;
alter table public.wallpapers
  add constraint wallpapers_report_count_check
  check (report_count >= 0);

create index if not exists wallpapers_created_at_idx on public.wallpapers(created_at desc);
create index if not exists wallpapers_uploader_id_idx on public.wallpapers(uploader_id);
create index if not exists wallpapers_moderation_status_idx on public.wallpapers(moderation_status);

create or replace function public.enforce_wallpaper_storage_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  max_storage_bytes bigint := 1073741824;
  used_storage_bytes bigint;
begin
  select coalesce(sum(file_size), 0)
  into used_storage_bytes
  from public.wallpapers
  where uploader_id = new.uploader_id
    and id <> new.id;

  if used_storage_bytes + new.file_size > max_storage_bytes then
    raise exception 'MotionDock marketplace user storage quota exceeded';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_wallpaper_storage_quota on public.wallpapers;
create trigger enforce_wallpaper_storage_quota
before insert or update of file_size, uploader_id
on public.wallpapers
for each row
execute function public.enforce_wallpaper_storage_quota();

alter table public.wallpapers enable row level security;

drop policy if exists "wallpapers are readable" on public.wallpapers;
create policy "wallpapers are readable"
on public.wallpapers for select
to anon, authenticated
using (
  (moderation_status = 'approved' and coalesce(is_hidden, false) = false)
  or auth.uid() = uploader_id
  or public.is_marketplace_moderator(auth.uid())
);

drop policy if exists "users can insert own wallpapers" on public.wallpapers;
create policy "users can insert own wallpapers"
on public.wallpapers for insert
to authenticated
with check (
  auth.uid() = uploader_id
  and moderation_status = 'approved'
  and uploader_confirmed_rights = true
  and coalesce(is_hidden, false) = false
);

drop policy if exists "moderators can update wallpaper moderation" on public.wallpapers;
create policy "moderators can update wallpaper moderation"
on public.wallpapers for update
to authenticated
using (public.is_marketplace_moderator(auth.uid()))
with check (public.is_marketplace_moderator(auth.uid()));

drop policy if exists "authenticated users can update wallpaper like counts" on public.wallpapers;

create table if not exists public.wallpaper_likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  wallpaper_id uuid not null references public.wallpapers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, wallpaper_id)
);

create index if not exists wallpaper_likes_wallpaper_id_idx
on public.wallpaper_likes(wallpaper_id);

alter table public.wallpaper_likes enable row level security;

drop policy if exists "users can read own wallpaper likes" on public.wallpaper_likes;
create policy "users can read own wallpaper likes"
on public.wallpaper_likes for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "users can insert own wallpaper likes" on public.wallpaper_likes;
create policy "users can insert own wallpaper likes"
on public.wallpaper_likes for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "users can delete own wallpaper likes" on public.wallpaper_likes;
create policy "users can delete own wallpaper likes"
on public.wallpaper_likes for delete
to authenticated
using (auth.uid() = user_id);

create table if not exists public.wallpaper_reports (
  id uuid primary key default gen_random_uuid(),
  wallpaper_id uuid not null references public.wallpapers(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  details text,
  created_at timestamptz not null default now(),
  unique(wallpaper_id, reporter_id)
);

create index if not exists wallpaper_reports_wallpaper_id_idx
on public.wallpaper_reports(wallpaper_id);

create index if not exists wallpaper_reports_reporter_id_idx
on public.wallpaper_reports(reporter_id);

alter table public.wallpaper_reports enable row level security;

drop policy if exists "users can read own wallpaper reports" on public.wallpaper_reports;
create policy "users can read own wallpaper reports"
on public.wallpaper_reports for select
to authenticated
using (auth.uid() = reporter_id);

drop policy if exists "users can insert own wallpaper reports" on public.wallpaper_reports;
create policy "users can insert own wallpaper reports"
on public.wallpaper_reports for insert
to authenticated
with check (auth.uid() = reporter_id);

grant select, insert on public.wallpaper_reports to authenticated;

create or replace function public.toggle_wallpaper_like(p_wallpaper_id uuid)
returns table(liked boolean, likes_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_liked boolean;
  v_likes_count integer;
  v_inserted_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.wallpapers
    where id = p_wallpaper_id
  ) then
    raise exception 'Wallpaper not found';
  end if;

  if exists (
    select 1
    from public.wallpaper_likes
    where user_id = v_user_id
      and wallpaper_id = p_wallpaper_id
  ) then
    delete from public.wallpaper_likes
    where user_id = v_user_id
      and wallpaper_id = p_wallpaper_id;

    update public.wallpapers
    set likes_count = greatest(coalesce(public.wallpapers.likes_count, 0) - 1, 0)
    where id = p_wallpaper_id
    returning public.wallpapers.likes_count into v_likes_count;

    v_liked := false;
  else
    insert into public.wallpaper_likes (user_id, wallpaper_id)
    values (v_user_id, p_wallpaper_id)
    on conflict do nothing;

    get diagnostics v_inserted_count = row_count;

    if v_inserted_count > 0 then
      update public.wallpapers
      set likes_count = coalesce(public.wallpapers.likes_count, 0) + 1
      where id = p_wallpaper_id
      returning public.wallpapers.likes_count into v_likes_count;
    else
      select coalesce(public.wallpapers.likes_count, 0)
      into v_likes_count
      from public.wallpapers
      where id = p_wallpaper_id;
    end if;

    v_liked := true;
  end if;

  return query select v_liked, coalesce(v_likes_count, 0);
end;
$$;

grant execute on function public.toggle_wallpaper_like(uuid) to authenticated;

create or replace function public.increment_wallpaper_downloads(p_wallpaper_id uuid)
returns table(downloads integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_downloads integer;
begin
  update public.wallpapers
  set downloads = coalesce(public.wallpapers.downloads, 0) + 1
  where id = p_wallpaper_id
  returning public.wallpapers.downloads into v_downloads;

  if v_downloads is null then
    raise exception 'Wallpaper not found';
  end if;

  return query select coalesce(v_downloads, 0);
end;
$$;

grant execute on function public.increment_wallpaper_downloads(uuid) to anon, authenticated;

create or replace function public.report_wallpaper(
  p_wallpaper_id uuid,
  p_reason text,
  p_details text
)
returns table(report_count integer, is_hidden boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_details text := nullif(trim(coalesce(p_details, '')), '');
  v_report_count integer;
  v_is_hidden boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if v_reason is null or v_reason not in (
    'Copyright',
    'Portrait Rights',
    'Adult Content',
    'Illegal Content',
    'Spam',
    'Other'
  ) then
    raise exception 'Invalid report reason';
  end if;

  if not exists (
    select 1
    from public.wallpapers
    where id = p_wallpaper_id
  ) then
    raise exception 'Wallpaper not found';
  end if;

  if exists (
    select 1
    from public.wallpaper_reports
    where wallpaper_id = p_wallpaper_id
      and reporter_id = v_user_id
  ) then
    raise exception 'You already reported this wallpaper.';
  end if;

  insert into public.wallpaper_reports (
    wallpaper_id,
    reporter_id,
    reason,
    details
  )
  values (
    p_wallpaper_id,
    v_user_id,
    v_reason,
    v_details
  );

  update public.wallpapers
  set
    report_count = coalesce(public.wallpapers.report_count, 0) + 1,
    is_hidden = (coalesce(public.wallpapers.report_count, 0) + 1 >= 3)
  where id = p_wallpaper_id
  returning
    public.wallpapers.report_count,
    public.wallpapers.is_hidden
  into v_report_count, v_is_hidden;

  return query select coalesce(v_report_count, 0), coalesce(v_is_hidden, false);
end;
$$;

grant execute on function public.report_wallpaper(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

create or replace function public.update_own_wallpaper_metadata(
  p_wallpaper_id uuid,
  p_title text,
  p_description text,
  p_category text
)
returns table(
  id uuid,
  title text,
  description text,
  uploader_id uuid,
  thumbnail_url text,
  video_url text,
  category text,
  downloads integer,
  likes_count integer,
  uploader_confirmed_rights boolean,
  report_count integer,
  is_hidden boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(p_title), '') is null then
    raise exception 'Title is required';
  end if;

  return query
  update public.wallpapers
  set
    title = trim(p_title),
    description = nullif(trim(coalesce(p_description, '')), ''),
    category = coalesce(nullif(trim(p_category), ''), 'Other')
  where public.wallpapers.id = p_wallpaper_id
    and public.wallpapers.uploader_id = v_user_id
  returning
    public.wallpapers.id,
    public.wallpapers.title,
    public.wallpapers.description,
    public.wallpapers.uploader_id,
    public.wallpapers.thumbnail_url,
    public.wallpapers.video_url,
    public.wallpapers.category,
    coalesce(public.wallpapers.downloads, 0),
    coalesce(public.wallpapers.likes_count, 0),
    public.wallpapers.uploader_confirmed_rights,
    coalesce(public.wallpapers.report_count, 0),
    coalesce(public.wallpapers.is_hidden, false),
    public.wallpapers.created_at;

  if not found then
    raise exception 'Wallpaper not found or not owned by current user';
  end if;
end;
$$;

grant execute on function public.update_own_wallpaper_metadata(uuid, text, text, text) to authenticated;

create or replace function public.delete_own_wallpaper(p_wallpaper_id uuid)
returns table(deleted boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_deleted_count integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  delete from public.wallpaper_likes
  where wallpaper_id = p_wallpaper_id;

  delete from public.wallpapers
  where id = p_wallpaper_id
    and uploader_id = v_user_id;

  get diagnostics v_deleted_count = row_count;

  if v_deleted_count = 0 then
    raise exception 'Wallpaper not found or not owned by current user';
  end if;

  return query select true;
end;
$$;

grant execute on function public.delete_own_wallpaper(uuid) to authenticated;

insert into storage.buckets (id, name, public)
values ('wallpapers', 'wallpapers', false)
on conflict (id) do nothing;

drop policy if exists "wallpaper files are readable" on storage.objects;
create policy "wallpaper files are readable"
on storage.objects for select
to anon, authenticated
using (
  bucket_id = 'wallpapers'
  and exists (
    select 1
    from public.wallpapers
    where wallpapers.storage_path = storage.objects.name
      and (
        (wallpapers.moderation_status = 'approved' and coalesce(wallpapers.is_hidden, false) = false)
        or wallpapers.uploader_id = auth.uid()
        or public.is_marketplace_moderator(auth.uid())
      )
  )
);

drop policy if exists "users can upload own wallpaper files" on storage.objects;
create policy "users can upload own wallpaper files"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'wallpapers'
  and split_part(name, '/', 1) = auth.uid()::text
);
