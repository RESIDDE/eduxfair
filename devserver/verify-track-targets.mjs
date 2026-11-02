// What "mute their microphone" selects, checked against the real protobuf.
//
// This exists because of a bug that could not fail loudly. `livekit-room`
// chose tracks with a hardcoded `track.type === 1`, commented as AUDIO. In
// LiveKit's protocol TrackType is AUDIO=0, VIDEO=1, DATA=2 — so muting a
// microphone silenced the student's CAMERA, and turning a camera off asked
// for DATA and matched nothing at all. LiveKit answered both perfectly
// happily, because both were valid questions.
//
// Nothing in a type system spans Postgres, a Deno function and a protobuf
// enum, so this is checked the same way verify-room-protocol.mjs checks the
// two clients: read the real values, and insist the code uses them.

import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TrackSource, TrackType } from '@livekit/protocol';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

const source = await readFile(
  join(root, 'supabase/functions/livekit-room/index.ts'), 'utf8');

let failed = 0;
const ok = (label, detail) => console.log(`  ${green('ok')}  ${label} ${dim(detail ?? '')}`);
const fail = (label, detail) => {
  failed += 1;
  console.log(`  ${red('FAIL')}  ${label}`);
  if (detail) console.log(red(`        ${detail}`));
};

console.log('\nTrack selection');
console.log(dim('  supabase/functions/livekit-room/index.ts  ↔  @livekit/protocol\n'));

// 1. The assumptions the comments in that file state, against the real enum.
const expected = {
  'TrackType.AUDIO': [TrackType.AUDIO, 0],
  'TrackType.VIDEO': [TrackType.VIDEO, 1],
  'TrackSource.CAMERA': [TrackSource.CAMERA, 1],
  'TrackSource.MICROPHONE': [TrackSource.MICROPHONE, 2],
};
for (const [name, [actual, assumed]] of Object.entries(expected)) {
  if (actual === assumed) ok(`${name} is ${actual}`);
  else fail(name, `the SDK says ${actual}, this check assumed ${assumed}`);
}

// 2. The function must name the enum, never a literal. A number here is the
//    exact shape of the original bug.
for (const member of ['TrackSource.MICROPHONE', 'TrackSource.CAMERA',
                      'TrackType.AUDIO', 'TrackType.VIDEO']) {
  if (source.includes(member)) ok(`selects by ${member}`);
  else fail(`selects by ${member}`, 'not referenced — has the mapping been inlined?');
}

const literal = source.match(/track\.(?:type|source)\s*===\s*-?\d+/);
if (literal) {
  fail('no hardcoded track numbers', `found \`${literal[0]}\` — use the enum`);
} else {
  ok('no hardcoded track numbers');
}

// 3. The selection predicate itself, against a realistic publication list.
//    Mirrors the one in the function; if that changes shape this has to too,
//    which is the point — it is a tripwire, not a copy to be ignored.
const TARGETS = {
  microphone: { source: TrackSource.MICROPHONE, type: TrackType.AUDIO },
  camera: { source: TrackSource.CAMERA, type: TrackType.VIDEO },
};
const select = (tracks, names) => tracks.filter((t) => !t.muted && names
  .map((n) => TARGETS[n])
  .some((w) => t.source === w.source
    || (t.source === TrackSource.UNKNOWN && t.type === w.type)))
  .map((t) => t.sid);

const published = [
  { sid: 'mic',     source: TrackSource.MICROPHONE,         type: TrackType.AUDIO },
  { sid: 'cam',     source: TrackSource.CAMERA,             type: TrackType.VIDEO },
  { sid: 'screen',  source: TrackSource.SCREEN_SHARE,       type: TrackType.VIDEO },
  { sid: 'scraudio',source: TrackSource.SCREEN_SHARE_AUDIO, type: TrackType.AUDIO },
  { sid: 'already', source: TrackSource.MICROPHONE,         type: TrackType.AUDIO, muted: true },
  { sid: 'legacy',  source: TrackSource.UNKNOWN,            type: TrackType.AUDIO },
];

const cases = [
  ['mute a microphone',        ['microphone'],           ['mic', 'legacy']],
  ['turn a camera off',        ['camera'],               ['cam']],
  ['mute everyone + cameras',  ['microphone', 'camera'], ['mic', 'cam', 'legacy']],
];
for (const [label, names, want] of cases) {
  const got = select(published, names);
  if (JSON.stringify(got) === JSON.stringify(want)) ok(label, `(${got.join(', ')})`);
  else fail(label, `selected ${JSON.stringify(got)}, expected ${JSON.stringify(want)}`);
}

if (failed > 0) {
  console.log(red(`\n${failed} failed — the wrong device would be muted.\n`));
  process.exit(1);
}
console.log(green('\nMuting selects what it says it selects.\n'));
