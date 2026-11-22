import '../../../core/constants/app_constants.dart';
import 'legal_document.dart';

/// The date the policy text below last changed.
const _lastUpdated = '11 November 2026';

/// The youngest someone may be and hold an account.
///
/// Sixteen, not thirteen. App Review guideline 5.1.4 requires compliance with
/// children's privacy statutes for any app that can share personal
/// information from a minor, and this one shares a great deal: a profile, a
/// photo, posts, direct messages, live video, and an Education Passport
/// holding transcripts and identity documents. Keeping the floor at sixteen
/// puts COPPA's under-13 regime out of scope entirely and matches the GDPR
/// Article 8 ceiling, so one rule works everywhere the fair recruits.
const minimumAge = 16;

const privacyPolicy = LegalDocument(
  title: 'Privacy Policy',
  summary: 'What ${AppConstants.appName} collects, why, who can see it, and '
      'how to get rid of it.',
  lastUpdated: _lastUpdated,
  sections: [
    LegalSection(
      heading: 'The short version',
      body: [
        'Your Education Passport is private by default. No institution can '
            'see it until you share it with that institution, and you can '
            'take that access back at any time from Settings → Who can see me.',
        'We do not sell your data, we do not show advertising, and we do not '
            'run third-party analytics or advertising trackers in this app.',
        'You can delete your account, and everything in it, from inside the '
            'app: Settings → Delete account.',
      ],
    ),
    LegalSection(
      heading: 'Who we are',
      body: [
        'This app is operated by the Lekkside Education Fair team. You can '
            'reach us about anything in this policy — including a request to '
            'access, correct, or delete your data — at '
            '${AppConstants.supportEmail}.',
      ],
    ),
    LegalSection(
      heading: 'What we collect, and why',
      body: ['We collect only what the app needs to do its job.'],
      bullets: [
        'Account details — your email address, your name, the country you '
            'are applying from, and your date of birth. Email and password '
            'identify you; your date of birth is collected solely to confirm '
            'you meet the minimum age and is not shown to anyone else.',
        'Your profile — your handle, your bio, and your photo, if you add '
            'one. These are visible to other people using the app.',
        'Your Education Passport — your education history, grades, English '
            'test results, the fields and countries you are interested in, '
            'and any documents you upload, such as transcripts, certificates '
            'or identity pages. This is the sensitive part: no institution '
            'sees it without your say-so.',
        'What you post — posts, comments, likes, reshares, saved items, who '
            'you follow, and any photos you attach.',
        'Messages and meetings — direct messages, voice notes, and your '
            'participation in live Spaces and one-to-one meetings with '
            'institutions.',
        'Technical records — sign-in times and basic error logs, kept so we '
            'can keep accounts secure and fix faults.',
      ],
    ),
    LegalSection(
      heading: 'If you use the app for an institution',
      body: [
        'Staff of a university, college, embassy or agency use the same app. '
            'For them we collect a name, a work email address and a password, '
            'their role on the institution’s team, and what they write — '
            'posts, replies to students, notes on applications and meeting '
            'details.',
        'The institution’s listing — its name, logo, prospectus, programmes, '
            'contacts and posts — is public to everyone using the app, because '
            'that is its purpose. A staff member’s name is shown to students '
            'they message or meet.',
        'A staff member can delete their account from More → Delete account. '
            'If they are the last member of their institution’s team, the '
            'institution’s listing and everything attached to it is deleted '
            'too; otherwise it stays with their colleagues.',
      ],
    ),
    LegalSection(
      heading: 'Who can see your Education Passport',
      body: [
        'Among institutions, only one you have granted access to. That grant is a '
            'record you create — by applying, by requesting a meeting, or by '
            'connecting at a fair booth — and every one of them is listed in '
            'Settings → Who can see me, where you can revoke it.',
        'Before you share anything, institutions can see only a pseudonymous '
            'card: your field of study, your target countries and an '
            'indication of how well you match a programme. It does not carry '
            'your name, your contact details or your documents.',
      ],
    ),
    LegalSection(
      heading: 'What our own team can see',
      body: [
        'A small number of authorised ${AppConstants.appName} staff can '
            'access everything held on your account — your profile, your '
            'Education Passport and the documents in it, your applications, '
            'your posts and comments, and your messages and their '
            'attachments.',
        'They use that access only to run and protect the service: to '
            'verify documents and institutions, to investigate reports and '
            'keep people safe, to enforce our terms, to answer a request '
            'you make to us, and where the law requires it. They do not use '
            'it to advertise to you, and they do not pass it to '
            'institutions.',
        'Staff cannot see your password or the one-time codes we send you, '
            'and cannot sign in as you.',
      ],
    ),
    LegalSection(
      heading: 'Who else we share data with',
      body: [
        'We use a small number of service providers to run the app. They '
            'process data on our instructions only, and are bound to protect '
            'it to the same standard we are. We do not sell personal data to '
            'anyone, and we do not share it with advertisers or data brokers.',
      ],
      bullets: [
        'Supabase — hosting, the database, file storage and sign-in.',
        'LiveKit — carries the audio and video for live Spaces and meetings. '
            'We do not record Spaces or meetings.',
        'Resend — sends account email such as verification codes and '
            'password resets.',
      ],
    ),
    LegalSection(
      heading: 'Things we deliberately do not do',
      bullets: [
        'We do not show advertising in this app.',
        'We do not track you across other apps or websites, and we do not '
            'ask for permission to.',
        'We do not use third-party analytics or advertising software '
            'development kits.',
        'We do not build a profile of you from anything other than what you '
            'entered yourself.',
        'We do not use your data to train machine-learning models.',
      ],
    ),
    LegalSection(
      heading: 'Permissions the app asks for',
      body: [
        'Each is asked for at the moment it is needed, and declining any of '
            'them leaves the rest of the app working.',
      ],
      bullets: [
        'Camera — to join a live Space or a meeting with video, to take a '
            'photo for a post, or to capture a document.',
        'Microphone — to speak in a Space or a meeting, and to record a '
            'voice note.',
        'Photos — to attach an image to a post or upload a document. We only '
            'receive the items you pick.',
      ],
    ),
    LegalSection(
      heading: 'How long we keep things',
      body: [
        'Your account data is kept while your account exists. When you delete '
            'your account we remove your profile, your passport, your '
            'documents, your posts, your comments and your messages.',
        'Two things survive, and we would rather say so plainly than bury '
            'it: records we are required to keep for legal or accounting '
            'reasons, and safety reports.',
        'A report is about the thing reported, not about the person who '
            'filed it. So if you reported someone and then delete your '
            'account, the report stays and your name comes off it. Otherwise '
            'deleting an account would be a way to withdraw a report about '
            'someone else\u2019s conduct, which is exactly the wrong thing '
            'for a service used by people under 18.',
      ],
    ),
    LegalSection(
      heading: 'Your rights',
      body: [
        'You can see and correct most of your data directly in the app. For '
            'anything you cannot, write to ${AppConstants.supportEmail} and '
            'we will respond within 30 days.',
      ],
      bullets: [
        'Access — ask for a copy of what we hold about you.',
        'Correction — fix anything that is wrong.',
        'Deletion — delete your account in the app, or ask us to.',
        'Withdraw consent — revoke an institution’s access at any time '
            'in Settings → Who can see me, or turn off a device permission '
            'in your phone’s own settings.',
        'Complain — if you are in a region with a data protection authority, '
            'you may complain to it.',
      ],
    ),
    LegalSection(
      heading: 'Age',
      body: [
        'You must be at least $minimumAge to hold an account. If you are '
            'under 18, you should have your parent or guardian’s '
            'permission before you sign up and before you share your '
            'Education Passport with any institution.',
        'If we learn that an account belongs to someone under $minimumAge, we '
            'will delete it and the data in it.',
      ],
    ),
    LegalSection(
      heading: 'Security',
      body: [
        'Data is encrypted in transit. Passwords are hashed and we never see '
            'them. Access to your passport is enforced in the database '
            'itself, not only in the app, so a flaw in one screen cannot '
            'expose it.',
      ],
    ),
    LegalSection(
      heading: 'Where your data is handled',
      body: [
        'Our service providers operate internationally, so your data may be '
            'processed outside the country you live in. Where it is, it is '
            'protected by the contractual safeguards those providers offer.',
      ],
    ),
    LegalSection(
      heading: 'Changes',
      body: [
        'If we change this policy we will update the date at the top and, '
            'where the change is significant, tell you in the app before it '
            'takes effect.',
      ],
    ),
  ],
);

const termsOfService = LegalDocument(
  title: 'Terms of Service',
  summary: 'The agreement between you and ${AppConstants.appName}.',
  lastUpdated: _lastUpdated,
  sections: [
    LegalSection(
      heading: 'Agreement',
      body: [
        'By creating an account you agree to these terms and to the '
            'Community Guidelines, which form part of them. If you do not '
            'agree, do not create an account.',
      ],
    ),
    LegalSection(
      heading: 'Who may use it',
      body: [
        'You must be at least $minimumAge years old. If you are under 18 you '
            'need your parent or guardian’s permission. You must give '
            'accurate information about yourself, and you may not create an '
            'account for anyone else or pretend to be an institution you do '
            'not represent.',
      ],
    ),
    // Apple's guideline 1.2 asks for an agreement that makes the no-tolerance
    // position explicit. This is that clause, and it is deliberately blunt.
    LegalSection(
      heading: 'There is no tolerance for abuse',
      body: [
        'There is zero tolerance for objectionable content and for abusive '
            'behaviour on this service.',
        'Content that harasses, threatens, bullies, degrades or '
            'discriminates against a person, sexual content involving '
            'minors, non-consensual intimate imagery, and material that '
            'exists to deceive students about admissions, scholarships or '
            'visas will be removed, and the account that posted it will be '
            'suspended or terminated.',
        'We act on reports. Content reported to us is reviewed, and reports '
            'concerning the safety of a minor are reviewed ahead of '
            'everything else.',
      ],
    ),
    LegalSection(
      heading: 'What you may not do',
      bullets: [
        'Post anything unlawful, hateful, threatening, harassing, or sexually '
            'explicit.',
        'Impersonate another person or misrepresent an institution.',
        'Make false claims about admission, funding, scholarships or visas.',
        'Upload documents that are not yours or that you have forged.',
        'Post someone else’s copyrighted work without permission.',
        'Collect other people’s data by scraping or automated means.',
        'Interfere with the service, or try to reach data you are not '
            'entitled to.',
      ],
    ),
    LegalSection(
      heading: 'Your content',
      body: [
        'What you post stays yours. By posting it you give us permission to '
            'host and display it inside the app so the service can work — '
            'nothing more. That permission ends when you delete the content '
            'or your account.',
        'You are responsible for what you post, and you confirm you have the '
            'right to post it.',
      ],
    ),
    LegalSection(
      heading: 'Your Education Passport',
      body: [
        'Your passport is yours and is private until you share it. Granting '
            'an institution access does not transfer ownership, and you may '
            'revoke access at any time. Institutions receiving it agree to '
            'use it only to assess you for admission.',
      ],
    ),
    LegalSection(
      heading: 'Using the service for an institution',
      body: [
        'If you register an institution you confirm you are authorised to act '
            'for it, and that what you publish about it — programmes, fees, '
            'entry requirements, scholarships and deadlines — is accurate.',
        'A passport or document a student shares with your institution may be '
            'used only to assess that student for admission. You may not copy '
            'it out of the service for any other purpose, sell it, or pass it '
            'to anyone outside your admissions team.',
        'You must not ask students for payment, passwords or identity '
            'documents outside the service’s own document requests, and you '
            'must not promise an outcome you cannot give.',
      ],
    ),
    LegalSection(
      heading: 'Moderation and enforcement',
      body: [
        'We may remove content and restrict, suspend or terminate an account '
            'that breaks these terms or the Community Guidelines. Where we '
            'reasonably can, we will tell you why. Serious cases — in '
            'particular anything involving the safety of a minor — may be '
            'acted on immediately and reported to the relevant authorities.',
      ],
    ),
    LegalSection(
      heading: 'Ending your account',
      body: [
        'You can delete your account at any time from Settings → Delete '
            'account, or for institution staff from More → Delete account. '
            'If you are the last member of an institution’s team, the '
            'institution is deleted with you. We may close an account that '
            'has broken these terms.',
      ],
    ),
    LegalSection(
      heading: 'No guarantee of an outcome',
      body: [
        'This service helps you be found by institutions and apply to them. '
            'It does not promise admission, a scholarship, a visa, or any '
            'other outcome, and nothing an institution posts here is an '
            'offer until that institution makes one to you directly.',
      ],
    ),
    LegalSection(
      heading: 'The service is provided as it is',
      body: [
        'We work to keep the service running and accurate, but we provide it '
            'as it is. To the extent the law allows, we are not liable for '
            'indirect or consequential loss arising from your use of it.',
      ],
    ),
    LegalSection(
      heading: 'Changes',
      body: [
        'We may change these terms. If a change is significant we will tell '
            'you in the app before it takes effect, and continuing to use the '
            'service after that means you accept it.',
      ],
    ),
    LegalSection(
      heading: 'Contact',
      body: [
        'Questions about these terms: ${AppConstants.supportEmail}.',
      ],
    ),
  ],
);

const communityGuidelines = LegalDocument(
  title: 'Community Guidelines',
  summary: 'What belongs here, what does not, and what happens when something '
      'is reported.',
  lastUpdated: _lastUpdated,
  sections: [
    LegalSection(
      heading: 'What this place is for',
      body: [
        'Students finding institutions, institutions finding students, and '
            'honest answers to the questions that decide where someone '
            'studies. Everything below follows from that.',
      ],
    ),
    LegalSection(
      heading: 'Not allowed, ever',
      bullets: [
        'Sexual content involving anyone under 18, in any form. This is '
            'reported to the authorities.',
        'Nude or sexual imagery, and any intimate image shared without the '
            'consent of the person in it.',
        'Threats of violence, or encouraging anyone to harm themselves or '
            'others.',
        'Hatred or harassment directed at someone for their race, ethnicity, '
            'nationality, religion, disability, sex, gender, or sexual '
            'orientation.',
        'Bullying, pile-ons, or contacting someone who has asked you to stop.',
        'Pretending to be another person, or to represent a university, '
            'college, embassy or agency you have no authority to speak for.',
        'Scams — fake scholarships, fake admission offers, visa guarantees, '
            'agents charging for a place that is not theirs to sell.',
        'Forged documents, or documents belonging to someone else.',
        'Selling or advertising anything unrelated to study, and bulk '
            'unsolicited messaging.',
      ],
    ),
    LegalSection(
      heading: 'Be accurate about admissions',
      body: [
        'People make expensive, irreversible decisions on what is said here. '
            'Entry requirements, fees, deadlines, scholarship terms and visa '
            'conditions must be stated accurately and kept current. '
            'Institutions that misstate them will have the post removed and '
            'may lose their verified status.',
      ],
    ),
    LegalSection(
      heading: 'Reporting something',
      body: [
        'Every post, comment, profile, message and Space has a report option '
            'behind its "…" menu. Tell us the reason and add a note if it '
            'helps.',
        'Reports are reviewed by a person. Anything flagged as a risk to a '
            'minor goes to the front of the queue. We will act on it by '
            'removing the content, restricting the account, or both — and '
            'where we can, we will tell you what happened.',
      ],
    ),
    LegalSection(
      heading: 'Blocking and muting',
      body: [
        'Blocking someone makes the two of you invisible to one another: '
            'neither sees the other’s posts, replies or profile, and '
            'neither can message the other. Muting is lighter — they vanish '
            'from your feed but remain reachable on their own profile.',
        'In messages, the "…" menu of any conversation lets you block it: '
            'nobody on either side can send anything new until you unblock '
            'it. This works the same for students and for institutions.',
        'You can see and undo every block in Settings → Blocked accounts. '
            'Neither blocking nor muting tells the other person.',
      ],
    ),
    LegalSection(
      heading: 'What happens when a rule is broken',
      body: [
        'Depending on what happened and whether it has happened before, we '
            'remove the content, put the account into read-only, suspend it, '
            'or terminate it. Child safety and credible threats skip '
            'straight to the end of that list.',
      ],
    ),
    LegalSection(
      heading: 'If we got it wrong',
      body: [
        'Write to ${AppConstants.supportEmail} and a person will look at it '
            'again.',
      ],
    ),
  ],
);
