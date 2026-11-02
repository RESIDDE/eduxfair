-- Lekkside Connect — posts, replies, reposts and the follow graph.
--
-- The reason to open the app on a day you are not applying to anything.
-- Institutions can describe themselves now but cannot say anything, and
-- students have nowhere to read it.
--
-- Everything here is keyed on account ids internally and exposed only through
-- the handle-based views in the next migration — the rule step 1 established,
-- because a readable `profile_id` is what would let an institution turn an
-- anonymous match card into a named minor.

create type post_kind as enum (
  'update',        -- an institution's news
  'question',      -- someone asking
  'announcement',  -- a deadline, an intake opening
  'requirement'    -- visa or entry guidance, usually from an embassy
);

-- Who may reply. A question thrown open to everyone and a deadline notice
-- need different answers.
create type reply_policy as enum (
  'everyone',
  'following',   -- only accounts the author follows
  'verified'     -- only verified accounts
);

-- ------------------------------------------------------------------- posts

create table posts (
  id             uuid primary key default gen_random_uuid(),
  author_id      uuid not null references profiles (id) on delete cascade,

  -- Set when posting as the organisation rather than as the person. The feed
  -- then shows the institution's name and logo, not the staff member's.
  institution_id uuid references institutions (id) on delete cascade,

  body           text,
  kind           post_kind not null default 'update',
  link_url       text,
  reply_policy   reply_policy not null default 'everyone',

  -- A repost is a post referencing another. Body null is a plain repost, body
  -- present is a quote — one mechanism rather than two, and a repost of
  -- removed content disappears with it instead of leaving a hole in the feed.
  repost_of      uuid references posts (id) on delete cascade,

  pinned_at      timestamptz,
  deleted_at     timestamptz,

  -- Trigger-maintained so the feed is one query rather than three aggregates.
  like_count     int not null default 0,
  comment_count  int not null default 0,
  repost_count   int not null default 0,

  created_at     timestamptz not null default now(),
  edited_at      timestamptz,

  -- A post has to say something: text, media (checked below), or be a repost.
  constraint post_has_content
    check (repost_of is not null
           or coalesce(trim(body), '') <> ''
           or link_url is not null),
  -- A plain repost carries no kind of its own; it inherits the original's.
  constraint repost_is_not_pinned
    check (repost_of is null or pinned_at is null)
);

create index posts_author_idx on posts (author_id, created_at desc)
  where deleted_at is null;
create index posts_institution_idx on posts (institution_id, created_at desc)
  where deleted_at is null and institution_id is not null;
create index posts_feed_idx on posts (created_at desc) where deleted_at is null;
create index posts_repost_idx on posts (repost_of) where repost_of is not null;

comment on column posts.repost_of is
  'The post being reshared. Reposts are flattened by repost() — resharing a '
  'repost reshares the original — so this never chains.';

-- ------------------------------------------------------------------- media

create table post_media (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references posts (id) on delete cascade,
  -- Path within the public `post-media` bucket, prefixed with the author's
  -- uuid so the storage policy can authorize on the first segment alone.
  storage_path text not null,
  mime         text,
  width        int,
  height       int,
  alt_text     text,
  ord          int not null default 0,
  created_at   timestamptz not null default now()
);

create index post_media_order on post_media (post_id, ord);

-- ---------------------------------------------------------------- comments

create table comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references posts (id) on delete cascade,
  author_id  uuid not null references profiles (id) on delete cascade,
  -- One level of threading. Deeper nesting is unreadable on a phone and makes
  -- moderation harder to reason about.
  parent_id  uuid references comments (id) on delete cascade,
  body       text not null,
  like_count int not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint comment_has_body check (coalesce(trim(body), '') <> '')
);

create index comments_post_idx on comments (post_id, created_at)
  where deleted_at is null;

-- -------------------------------------------------- likes, bookmarks, follows

create table post_likes (
  post_id    uuid not null references posts (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);

create table comment_likes (
  comment_id uuid not null references comments (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, profile_id)
);

-- Private to the person who saved it; never counted or shown to the author.
create table post_bookmarks (
  post_id    uuid not null references posts (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, post_id)
);

create table follows (
  follower_id uuid not null references profiles (id) on delete cascade,
  followee_id uuid not null references profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint no_self_follow check (follower_id <> followee_id)
);

create index follows_followee_idx on follows (followee_id);

-- ------------------------------------------------------------------ topics
--
-- What a post is about, so the feed can be assembled from a student's own
-- passport rather than from a graph they have not built yet.

create type topic_kind as enum ('field', 'country');

create table post_topics (
  post_id uuid not null references posts (id) on delete cascade,
  kind    topic_kind not null,
  -- A field slug from `fields_of_study`, or an ISO 3166-1 alpha-2 country.
  -- Reusing that vocabulary is what makes this match `target_fields` directly.
  value   text not null,
  primary key (post_id, kind, value)
);

create index post_topics_lookup on post_topics (kind, value);

-- ------------------------------------------------------------ count upkeep

create or replace function bump_post_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
  delta  int := case when tg_op = 'INSERT' then 1 else -1 end;
begin
  if tg_table_name = 'post_likes' then
    target := coalesce(new.post_id, old.post_id);
    update posts set like_count = greatest(0, like_count + delta) where id = target;

  elsif tg_table_name = 'comments' then
    target := coalesce(new.post_id, old.post_id);
    update posts set comment_count = greatest(0, comment_count + delta)
     where id = target;

  elsif tg_table_name = 'comment_likes' then
    update comments set like_count = greatest(0, like_count + delta)
     where id = coalesce(new.comment_id, old.comment_id);

  elsif tg_table_name = 'posts' then
    -- A repost bumps the original's count, not its own.
    target := coalesce(new.repost_of, old.repost_of);
    if target is not null then
      update posts set repost_count = greatest(0, repost_count + delta)
       where id = target;
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger post_likes_count after insert or delete on post_likes
  for each row execute function bump_post_counts();
create trigger comments_count after insert or delete on comments
  for each row execute function bump_post_counts();
create trigger comment_likes_count after insert or delete on comment_likes
  for each row execute function bump_post_counts();
create trigger reposts_count after insert or delete on posts
  for each row execute function bump_post_counts();

-- Soft deletes have to move counts too, or a removed reply leaves the number
-- overstated for ever.
create or replace function sync_soft_delete_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (old.deleted_at is null) = (new.deleted_at is null) then
    return new;
  end if;

  if tg_table_name = 'comments' then
    update posts
       set comment_count = greatest(0, comment_count +
             case when new.deleted_at is null then 1 else -1 end)
     where id = new.post_id;

  elsif tg_table_name = 'posts' and new.repost_of is not null then
    update posts
       set repost_count = greatest(0, repost_count +
             case when new.deleted_at is null then 1 else -1 end)
     where id = new.repost_of;
  end if;

  return new;
end;
$$;

create trigger comments_soft_delete after update of deleted_at on comments
  for each row execute function sync_soft_delete_counts();
create trigger posts_soft_delete after update of deleted_at on posts
  for each row execute function sync_soft_delete_counts();

-- The follow graph feeds the counters on a public profile.
create or replace function bump_follow_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  delta int := case when tg_op = 'INSERT' then 1 else -1 end;
begin
  update social_profiles
     set following_count = greatest(0, following_count + delta)
   where profile_id = coalesce(new.follower_id, old.follower_id);
  update social_profiles
     set follower_count = greatest(0, follower_count + delta)
   where profile_id = coalesce(new.followee_id, old.followee_id);
  return coalesce(new, old);
end;
$$;

create trigger follows_count after insert or delete on follows
  for each row execute function bump_follow_counts();

create or replace function bump_post_count_on_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Reposts do not count toward a profile's post count; they are not authored.
  if coalesce(new.repost_of, old.repost_of) is not null then
    return coalesce(new, old);
  end if;

  update social_profiles
     set post_count = greatest(0, post_count +
           case when tg_op = 'INSERT' then 1 else -1 end)
   where profile_id = coalesce(new.author_id, old.author_id);

  return coalesce(new, old);
end;
$$;

create trigger posts_profile_count after insert or delete on posts
  for each row execute function bump_post_count_on_profile();

-- --------------------------------------------------------------- the bucket

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('post-media', 'post-media', true, 10485760,  -- 10 MB
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/gif'])
on conflict (id) do nothing;
