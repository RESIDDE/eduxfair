-- Searching what people have posted.
--
-- Discover could search programs and nothing else. The institutions it fetched
-- were thrown away unrendered, and posts were not reachable at all — so a
-- student looking for "scholarship" found course listings and none of the
-- announcements actually about scholarships.
--
-- Deliberately modelled on feed_by_topic rather than querying `posts`: every
-- visibility rule — soft deletes, blocks in both directions, the author's own
-- restrictions, handle resolution — already lives in the `feed_posts` view,
-- and a second query over the base table is how those rules drift apart.
-- Muting is applied the same way the feed applies it.
--
-- Matching is `ilike` over the body, not full-text search. That is a
-- deliberate limit: tsvector would need an index, a language configuration and
-- a decision about stemming across the languages these students write in, and
-- none of that is worth committing to before anyone has posted enough for it
-- to matter. `ilike` on a few thousand rows is immediate, and the signature
-- here does not change when it is replaced.

create or replace function search_posts(
  p_query  text,
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
     and coalesce(trim(p_query), '') <> ''
     and (
       f.body ilike '%' || trim(p_query) || '%'
       -- The author is worth matching too: "maplecrest" should find what
       -- Maplecrest has said, not only posts that say the word.
       or f.author_name ilike '%' || trim(p_query) || '%'
       or f.author_handle ilike '%' || trim(p_query) || '%'
       -- And a topic, so "computer science" reaches posts tagged with it
       -- whether or not the phrase appears in the text.
       or exists (
         select 1 from post_topics t
          where t.post_id = f.id
            and replace(t.value, '-', ' ') ilike '%' || replace(trim(p_query), '-', ' ') || '%'
       )
     )
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

revoke all on function search_posts(text, int, timestamptz) from public;
grant execute on function search_posts(text, int, timestamptz) to authenticated;
