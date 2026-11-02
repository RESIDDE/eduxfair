// The in-room protocol exists twice, and this is what stops the two copies
// drifting.
//
//   web/src/lib/livekit.js
//   student_app/lib/features/meet/models/room_protocol.dart
//
// The React console and the Flutter app talk to each other through LiveKit,
// which validates nothing: a reaction topic that differs between them does not
// error, it just never arrives, and an attribute key that differs makes the
// host's roster quietly disagree with the room. There is no type system across
// the two languages to catch it and no test that would fail.
//
// So it is checked the same way verify-console-queries.mjs checks the console's
// select strings: read the values out of both files and insist they match.

import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

const js = await readFile(join(root, 'web/src/lib/livekit.js'), 'utf8');
const dart = await readFile(
  join(root, 'student_app/lib/features/meet/models/room_protocol.dart'),
  'utf8',
);

/** First capture group of `re`, or null. */
const pick = (source, re) => source.match(re)?.[1] ?? null;

/** Every single-quoted string inside the matched block, in order. */
const pickList = (source, re) => {
  const block = source.match(re)?.[1];
  if (!block) return null;
  return [...block.matchAll(/'([^']*)'/g)].map((m) => m[1]);
};

const checks = [
  {
    name: 'protocol version',
    js: pick(js, /PROTOCOL_VERSION\s*=\s*(\d+)/),
    dart: pick(dart, /int version\s*=\s*(\d+)/),
  },
  {
    name: 'attribute: role',
    js: pick(js, /role:\s*'([^']+)'/),
    dart: pick(dart, /attrRole\s*=\s*'([^']+)'/),
  },
  {
    name: 'attribute: participant id',
    js: pick(js, /participantId:\s*'([^']+)'/),
    dart: pick(dart, /attrParticipantId\s*=\s*'([^']+)'/),
  },
  {
    name: 'attribute: handle',
    js: pick(js, /handle:\s*'([^']+)'/),
    dart: pick(dart, /attrHandle\s*=\s*'([^']+)'/),
  },
  {
    name: 'attribute: hand',
    js: pick(js, /hand:\s*'([^']+)'/),
    dart: pick(dart, /attrHand\s*=\s*'([^']+)'/),
  },
  {
    name: 'topic: reaction',
    js: pick(js, /reaction:\s*'([^']+)'/),
    dart: pick(dart, /topicReaction\s*=\s*'([^']+)'/),
  },
  {
    name: 'topic: ask to unmute',
    js: pick(js, /askUnmute:\s*'([^']+)'/),
    dart: pick(dart, /topicAskUnmute\s*=\s*'([^']+)'/),
  },
  {
    name: 'the roles that moderate',
    js: pickList(js, /MODERATOR_ROLES\s*=\s*\[([^\]]+)\]/),
    dart: pickList(dart, /moderatorRoles\s*=\s*\[([^\]]+)\]/),
  },
  {
    name: 'the roles that are staff',
    js: pickList(js, /STAFF_ROLES\s*=\s*\[([^\]]+)\]/),
    dart: pickList(dart, /staffRoles\s*=\s*\[([^\]]+)\]/),
  },
  {
    name: 'the reaction set',
    js: pickList(js, /REACTIONS\s*=\s*\[([^\]]+)\]/),
    dart: pickList(dart, /reactions\s*=\s*\[([^\]]+)\]/),
  },
];

console.log('\nIn-room protocol');
console.log(dim('  web/src/lib/livekit.js  ↔  student_app/.../room_protocol.dart\n'));

let failed = 0;
for (const check of checks) {
  const a = Array.isArray(check.js) ? check.js.join(' ') : check.js;
  const b = Array.isArray(check.dart) ? check.dart.join(' ') : check.dart;

  if (a === null || b === null) {
    // A value that cannot be found is as dangerous as one that disagrees: it
    // means this script is reading a file it no longer understands.
    failed += 1;
    console.log(`  ${red('FAIL')}  ${check.name}`);
    console.log(red(`        not found in ${a === null ? 'the JS' : 'the Dart'} — has it been renamed?`));
  } else if (a !== b) {
    failed += 1;
    console.log(`  ${red('FAIL')}  ${check.name}`);
    console.log(red(`        js: ${a}`));
    console.log(red(`        dart: ${b}`));
  } else {
    console.log(`  ${green('ok')}  ${check.name} ${dim(a)}`);
  }
}

console.log(`\n${checks.length} values, ${failed} mismatched`);
if (failed > 0) {
  console.log(red('\nThe two clients would not understand each other.\n'));
  process.exit(1);
}
console.log(green('\nBoth clients agree.\n'));
