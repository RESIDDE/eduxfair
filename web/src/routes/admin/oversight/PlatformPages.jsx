import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { SegmentedControl } from '../../../components/ui';
import { OPEN_STAGES, CLOSED_STAGES } from '../../../lib/status';
import {
  ApplicationsList, CommentsList, ConversationsPanel, DocumentsList,
  MeetingsList, PostsList,
} from './lists';

/**
 * The platform-wide views: everything of one kind, across every account and
 * institution. Each is the same list the person and institution pages use,
 * with no scope — or a filter on top.
 */

export function AdminPostsPage() {
  const [view, setView] = useState('live');
  return (
    <div className="flex flex-col gap-5 pb-6">
      <SegmentedControl
        value={view}
        onChange={setView}
        options={[
          { value: 'live', label: 'Posts' },
          { value: 'comments', label: 'Comments' },
          { value: 'removed', label: 'Removed posts' },
        ]}
      />
      {view === 'live' && <PostsList scope={(q) => q.is('deleted_at', null)} scopeKey="live" />}
      {view === 'removed' && <PostsList scope={(q) => q.not('deleted_at', 'is', null)} scopeKey="removed" />}
      {view === 'comments' && <CommentsList scopeKey="all-comments" />}
    </div>
  );
}

export function AdminMessagesPage() {
  // A report links here with ?conversation=<id>, so it opens on that thread.
  const [params] = useSearchParams();
  return (
    <div className="flex flex-col gap-4 pb-6">
      <p className="text-[13px] text-muted">
        Every conversation between a student and an institution, newest first —
        including messages the sender later deleted, and their attachments.
      </p>
      <ConversationsPanel scopeKey="all-conversations" initialId={params.get('conversation')} />
    </div>
  );
}

export function AdminApplicationsPage() {
  const [view, setView] = useState('open');
  const scopes = {
    open: (q) => q.in('stage', OPEN_STAGES),
    closed: (q) => q.in('stage', CLOSED_STAGES),
    drafts: (q) => q.eq('stage', 'draft'),
    all: (q) => q,
  };
  return (
    <div className="flex flex-col gap-5 pb-6">
      <SegmentedControl
        value={view}
        onChange={setView}
        options={[
          { value: 'open', label: 'In progress' },
          { value: 'closed', label: 'Closed' },
          { value: 'drafts', label: 'Drafts' },
          { value: 'all', label: 'All' },
        ]}
      />
      <ApplicationsList scope={scopes[view]} scopeKey={view} />
    </div>
  );
}

export function AdminDocumentsPage() {
  const [view, setView] = useState('pending');
  return (
    <div className="flex flex-col gap-5 pb-6">
      <SegmentedControl
        value={view}
        onChange={setView}
        options={[
          { value: 'pending', label: 'Waiting for review' },
          { value: 'unverified', label: 'Not reviewed' },
          { value: 'verified', label: 'Verified' },
          { value: 'rejected', label: 'Rejected' },
          { value: 'all', label: 'All' },
        ]}
      />
      <DocumentsList
        scope={view === 'all' ? (q) => q : (q) => q.eq('verification_status', view)}
        scopeKey={view}
      />
    </div>
  );
}

export function AdminMeetingsPage() {
  const [view, setView] = useState('upcoming');
  const now = new Date().toISOString();
  const scopes = {
    upcoming: (q) => q.gte('scheduled_for', now).in('status', ['requested', 'confirmed', 'rescheduled']),
    requested: (q) => q.eq('status', 'requested'),
    past: (q) => q.lt('scheduled_for', now),
    all: (q) => q,
  };
  return (
    <div className="flex flex-col gap-5 pb-6">
      <SegmentedControl
        value={view}
        onChange={setView}
        options={[
          { value: 'upcoming', label: 'Upcoming' },
          { value: 'requested', label: 'Awaiting a reply' },
          { value: 'past', label: 'Past' },
          { value: 'all', label: 'All' },
        ]}
      />
      {/* now is per render, so the key is the view, not the timestamp. */}
      <MeetingsList scope={scopes[view]} scopeKey={view} />
    </div>
  );
}
