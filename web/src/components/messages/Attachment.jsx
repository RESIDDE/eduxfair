import { useEffect, useRef, useState } from 'react';
import { FileText, Pause, Play, Square, Trash2 } from 'lucide-react';
import { supabase } from '../../lib/supabase';

/** The private bucket both clients write message attachments into. */
export const BUCKET = 'message-attachments';

/**
 * Signs a URL for one attachment.
 *
 * The bucket is private, so nothing can be rendered or played from a path
 * alone. Signed on demand rather than for the whole thread: a long
 * conversation would otherwise be a hundred requests to draw rows nobody
 * opened.
 */
export async function signedUrl(path) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrl(path, 3600);
  if (error) return null;
  return data?.signedUrl ?? null;
}

/** Uploads a file and returns the storage path, mirroring the Flutter naming. */
export async function uploadAttachment(conversationId, file, name) {
  // Timestamp-prefixed so re-sending the same filename cannot collide, and
  // keyed on the conversation because that is the segment the storage policy
  // authorizes on.
  const safe = (name ?? file.name ?? 'file').replace(/[^A-Za-z0-9._-]/g, '_');
  const path = `${conversationId}/${Date.now()}-${safe}`;
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { contentType: file.type || undefined });
  if (error) throw error;
  return path;
}

/** A picture, in the thread rather than behind a download. */
export function InlineImage({ message }) {
  const [url, setUrl] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    signedUrl(message.attachment_path).then((next) => {
      if (!live) return;
      setUrl(next);
      if (!next) setFailed(true);
    });
    return () => { live = false; };
  }, [message.attachment_path]);

  if (failed) return <AttachmentChip message={message} />;
  if (!url) return <div className="h-32 w-48 animate-pulse rounded-[10px] bg-white/10" />;

  return (
    <a href={url} target="_blank" rel="noreferrer" className="block">
      <img
        src={url}
        alt={message.attachment_name ?? 'Attachment'}
        onError={() => setFailed(true)}
        className="max-h-64 max-w-full rounded-[10px] object-cover"
      />
    </a>
  );
}

/** Anything that is not a picture or a voice note. */
export function AttachmentChip({ message }) {
  const [busy, setBusy] = useState(false);

  async function open() {
    setBusy(true);
    const url = await signedUrl(message.attachment_path);
    setBusy(false);
    if (url) window.open(url, '_blank', 'noopener');
  }

  return (
    <button
      type="button"
      onClick={open}
      disabled={busy}
      className="flex cursor-pointer items-center gap-2 underline underline-offset-2 disabled:opacity-60"
    >
      <FileText size={15} className="shrink-0" />
      <span className="truncate">{message.attachment_name ?? 'Attachment'}</span>
    </button>
  );
}

/** Plays one voice note, with the length it was recorded at. */
export function VoiceNote({ message, mine }) {
  const audioRef = useRef(null);
  const [url, setUrl] = useState(null);
  const [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0);

  const total = (message.duration_ms ?? 0) / 1000;

  async function toggle() {
    if (!url) {
      // First press signs the URL; the effect below starts playback once the
      // <audio> element actually has a source.
      const next = await signedUrl(message.attachment_path);
      if (next) setUrl(next);
      return;
    }
    const el = audioRef.current;
    if (!el) return;
    if (el.paused) {
      if (el.currentTime >= el.duration) el.currentTime = 0;
      el.play();
    } else {
      el.pause();
    }
  }

  useEffect(() => {
    if (url) audioRef.current?.play().catch(() => {});
  }, [url]);

  const progress = total > 0 ? Math.min(100, (position / total) * 100) : 0;
  const shown = position > 0 ? position : total;

  return (
    <div className="flex min-w-[180px] items-center gap-2.5">
      <button
        type="button"
        onClick={toggle}
        aria-label={playing ? 'Pause' : 'Play'}
        className="grid size-7 shrink-0 cursor-pointer place-items-center rounded-full bg-white/15"
      >
        {playing ? <Pause size={14} /> : <Play size={14} />}
      </button>
      <div className="flex-1">
        <div className={`h-[3px] rounded-full ${mine ? 'bg-white/30' : 'bg-white/15'}`}>
          <div
            className={`h-full rounded-full ${mine ? 'bg-white' : 'bg-accent'}`}
            style={{ width: `${progress}%` }}
          />
        </div>
        <div className={`mt-1 text-[10.5px] tabular-nums ${mine ? 'text-white/75' : 'text-subtle'}`}>
          {formatSeconds(shown)}
        </div>
      </div>
      {url && (
        <audio
          ref={audioRef}
          src={url}
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
          onEnded={() => { setPlaying(false); setPosition(0); }}
          onTimeUpdate={(e) => setPosition(e.currentTarget.currentTime)}
          className="hidden"
        />
      )}
    </div>
  );
}

function formatSeconds(value) {
  const whole = Math.floor(value || 0);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

/**
 * The composer's recorder.
 *
 * MediaRecorder rather than a library: the browser already has this, and the
 * only real decision is the container. Chrome and Firefox produce webm/opus,
 * Safari produces mp4 — both are in the bucket's allowlist, and the mime the
 * blob reports is what gets stored, so nothing downstream has to guess.
 */
export function VoiceRecorder({ onComplete, onCancel }) {
  const recorderRef = useRef(null);
  const chunksRef = useRef([]);
  const startedRef = useRef(0);
  const [elapsed, setElapsed] = useState(0);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let stream;
    let timer;
    let cancelled = false;

    (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop());
          return;
        }
        const recorder = new MediaRecorder(stream);
        recorderRef.current = recorder;
        chunksRef.current = [];
        recorder.ondataavailable = (event) => {
          if (event.data.size > 0) chunksRef.current.push(event.data);
        };
        recorder.start();
        startedRef.current = Date.now();
        setReady(true);
        timer = setInterval(() => setElapsed(Date.now() - startedRef.current), 200);
      } catch {
        onCancel('Allow microphone access to record a voice note.');
      }
    })();

    return () => {
      cancelled = true;
      clearInterval(timer);
      const recorder = recorderRef.current;
      if (recorder && recorder.state !== 'inactive') recorder.stop();
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, [onCancel]);

  function stop() {
    const recorder = recorderRef.current;
    if (!recorder || recorder.state === 'inactive') return;
    const ms = Date.now() - startedRef.current;
    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: recorder.mimeType });
      recorder.stream.getTracks().forEach((track) => track.stop());
      // Under about a second is a slip, not a message.
      if (ms < 700) onCancel();
      else onComplete(blob, ms);
    };
    recorder.stop();
  }

  // Two minutes, so a tab left open does not become a twenty-megabyte upload.
  useEffect(() => {
    if (elapsed >= 120_000) stop();
  }, [elapsed]);

  return (
    <div className="flex flex-1 items-center gap-3">
      <button
        type="button"
        onClick={() => onCancel()}
        aria-label="Discard"
        className="grid size-9 cursor-pointer place-items-center rounded-full text-error hover:bg-error-bg"
      >
        <Trash2 size={16} />
      </button>
      <span className="size-2 animate-pulse rounded-full bg-error" />
      <span className="text-[13px] font-semibold tabular-nums text-white">
        {ready ? formatSeconds(elapsed / 1000) : 'Starting…'}
      </span>
      <span className="text-[12px] text-subtle">Recording</span>
      <div className="flex-1" />
      <button
        type="button"
        onClick={stop}
        disabled={!ready}
        aria-label="Stop and send"
        className="grid size-9 cursor-pointer place-items-center rounded-full bg-accent text-on-accent disabled:opacity-50"
      >
        <Square size={14} />
      </button>
    </div>
  );
}
