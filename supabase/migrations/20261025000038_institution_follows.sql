-- Lekkside Connect — institution follows.
--
-- Enables students to follow universities, and universities to track their follower count
-- and audience. Followed institutions' updates appear in the student's Following feed.

-- 1. Add follower_count to institutions
alter table institutions add column if not exists follower_count int not null default 0;

-- 2. Create institution_follows table
create table if not exists institution_follows (
  student_id     uuid not null references profiles (id) on delete cascade,
  institution_id uuid not null references institutions (id) on delete cascade,
  created_at     timestamptz not null default now(),
  primary key (student_id, institution_id)
);

create index if not exists institution_follows_inst_idx on institution_follows (institution_id, created_at desc);
create index if not exists institution_follows_student_idx on institution_follows (student_id);

-- 3. RLS
alter table institution_follows enable row level security;

drop policy if exists institution_follows_select on institution_follows;
create policy institution_follows_select on institution_follows
  for select using (
    student_id = auth.uid()
    or is_member_of(institution_id)
    or is_admin()
  );

drop policy if exists institution_follows_insert on institution_follows;
create policy institution_follows_insert on institution_follows
  for insert with check (student_id = auth.uid());

drop policy if exists institution_follows_delete on institution_follows;
create policy institution_follows_delete on institution_follows
  for delete using (student_id = auth.uid());

-- 4. Trigger to bump institutions.follower_count
create or replace function bump_institution_follower_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.institution_id, old.institution_id);
  delta  int := case when tg_op = 'INSERT' then 1 else -1 end;
begin
  update institutions
     set follower_count = greatest(0, follower_count + delta)
   where id = target;
  return coalesce(new, old);
end;
$$;

drop trigger if exists institution_follows_count on institution_follows;
create trigger institution_follows_count
  after insert or delete on institution_follows
  for each row execute function bump_institution_follower_counts();

-- 5. RPC: follow_institution
create or replace function follow_institution(
  p_institution_id uuid,
  p_follow         boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_is_following boolean;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_follow then
    insert into institution_follows (student_id, institution_id)
    values (auth.uid(), p_institution_id)
    on conflict do nothing;
  else
    delete from institution_follows
     where student_id = auth.uid() and institution_id = p_institution_id;
  end if;

  select count(*) into v_count from institution_follows where institution_id = p_institution_id;
  v_is_following := exists (
    select 1 from institution_follows
     where student_id = auth.uid() and institution_id = p_institution_id
  );

  return jsonb_build_object(
    'is_following', v_is_following,
    'follower_count', v_count
  );
end;
$$;

revoke all on function follow_institution(uuid, boolean) from public;
grant execute on function follow_institution(uuid, boolean) to authenticated;

-- 6. RPC: get_institution_follow_status
create or replace function get_institution_follow_status(
  p_institution_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'is_following', exists (
      select 1 from institution_follows
       where student_id = auth.uid() and institution_id = p_institution_id
    ),
    'follower_count', (
      select count(*) from institution_follows
       where institution_id = p_institution_id
    )
  );
$$;

revoke all on function get_institution_follow_status(uuid) from public;
grant execute on function get_institution_follow_status(uuid) to authenticated;

-- 7. RPC: my_institution_followers
create or replace function my_institution_followers(
  p_institution_id uuid,
  p_limit          int default 100
)
returns table (
  student_id  uuid,
  full_name   text,
  avatar_url  text,
  country     text,
  followed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id as student_id,
    p.full_name,
    p.avatar_url,
    p.country,
    f.created_at as followed_at
  from institution_follows f
  join profiles p on p.id = f.student_id
  where f.institution_id = p_institution_id
    and (is_member_of(p_institution_id) or is_admin())
  order by f.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

revoke all on function my_institution_followers(uuid, int) from public;
grant execute on function my_institution_followers(uuid, int) to authenticated;

-- 8. Update my_institution_demand to include followers
create or replace function my_institution_demand(p_institution_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_member_of(p_institution_id) and not is_admin() then
    raise exception 'not authorized';
  end if;

  return jsonb_build_object(
    'matched_students', (
      select count(distinct ms.student_id)
        from match_scores ms
        join programs g on g.id = ms.program_id
       where g.institution_id = p_institution_id and g.is_active),
    'shared_passports', (
      select count(*) from passport_shares
       where institution_id = p_institution_id and revoked_at is null),
    'open_applications', (
      select count(*) from applications
       where institution_id = p_institution_id
         and stage not in ('rejected', 'withdrawn', 'enrolled')),
    'pending_appointments', (
      select count(*) from appointments
       where institution_id = p_institution_id and status = 'requested'),
    'unread_conversations', (
      select count(*)
        from conversations c
       where c.institution_id = p_institution_id
         and c.last_message_at is not null
         and not exists (
           select 1 from conversation_participants cp
            where cp.conversation_id = c.id
              and cp.profile_id = auth.uid()
              and cp.last_read_at >= c.last_message_at)),
    'followers', (
      select count(*) from institution_follows
       where institution_id = p_institution_id),
    'top_fields', (
      select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select g.field_of_study as field, count(distinct ms.student_id) as students
          from match_scores ms
          join programs g on g.id = ms.program_id
         where g.institution_id = p_institution_id and g.is_active
         group by g.field_of_study
         order by 2 desc
         limit 6
      ) t)
  );
end;
$$;

-- 9. Update feed_following to include posts from followed institutions
create or replace function feed_following(
  p_limit  int default 30,
  p_before timestamptz default null
)
returns setof feed_posts
language sql
stable
security definer
set search_path = public
as $$
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and (
       exists (select 1 from follows fl
                where fl.follower_id = auth.uid()
                  and fl.followee_id = f._author_id)
       or exists (select 1 from institution_follows ifl
                   where ifl.student_id = auth.uid()
                     and ifl.institution_id = f._institution_id)
       or f._author_id = auth.uid()
     )
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;
