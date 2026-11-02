-- Letting a student write the bio their profile has always displayed.
--
-- `social_profiles.bio` has existed since 20251010000015 and `public_profiles`
-- has been selecting it ever since — the handle profile renders it, the
-- follower lists fall back to it as a subtitle. Nothing could ever set it.
-- claim_handle() accepts a bio, but no client passed one, and it could not
-- have cleared one if it had:
--
--   bio = coalesce(excluded.bio, social_profiles.bio)
--
-- That coalesce is right for a rename — re-claiming a handle should not wipe a
-- bio nobody was editing — and wrong for an editor, where deleting the text
-- and saving has to mean deleting the text. So the editor gets its own
-- setter instead of the rename growing a second meaning.

create or replace function set_social_bio(p_bio text)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_bio text := nullif(trim(coalesce(p_bio, '')), '');
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  -- A cap, because this renders in a list row as well as on a profile. Checked
  -- here rather than as a column constraint: existing rows were written by
  -- claim_handle() with no limit, and a constraint would make them invalid.
  if length(v_bio) > 280 then
    raise exception 'A bio is up to 280 characters. That one is %.', length(v_bio);
  end if;

  if not exists (select 1 from social_profiles where profile_id = auth.uid()) then
    raise exception 'Claim a handle first — a bio hangs off your public profile.';
  end if;

  update social_profiles
     set bio = v_bio, updated_at = now()
   where profile_id = auth.uid();

  return v_bio;
end;
$$;

comment on function set_social_bio(text) is
  'Sets or clears the caller''s PUBLIC bio. Deliberately separate from '
  'claim_handle(), whose coalesce is correct for a rename and wrong for an '
  'editor: passing null here clears the bio, which is what an empty field '
  'means.';

revoke all on function set_social_bio(text) from public;
grant execute on function set_social_bio(text) to authenticated;
