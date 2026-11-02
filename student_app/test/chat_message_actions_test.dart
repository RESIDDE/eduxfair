import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/auth/models/app_user.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/messages/models/conversation.dart';
import 'package:lekkside_connect/features/messages/providers/messages_provider.dart';
import 'package:lekkside_connect/features/messages/screens/chat_screen.dart';

const conversationId = 'c1';
const myId = 'me';

class FakeMessages extends MessagesProvider {
  final List<Message> rows;
  FakeMessages(this.rows);

  @override
  List<Message> messagesFor(String id) => rows;
  @override
  Future<void> loadMessages(String id) async {}
  @override
  void subscribe(String id) {}
  @override
  void unsubscribe() {}
  @override
  Future<void> loadConversations() async {}
  @override
  Future<void> markRead(String id) async {}
}

/// `isMine` is read from the signed-in user, which a widget test has none of.
class FakeAuth extends AuthProvider {
  @override
  AppUser? get user => AppUser(
        id: myId,
        role: 'student',
        fullName: 'Samuel',
        createdAt: DateTime.now(),
      );
}

Message msg(
  String id,
  String body, {
  required String sender,
  bool forwarded = false,
  String? replyTo,
  Map<String, List<String>> reactions = const {},
}) =>
    Message(
      id: id,
      conversationId: conversationId,
      senderId: sender,
      body: body,
      isForwarded: forwarded,
      replyToId: replyTo,
      reactions: reactions,
      createdAt: DateTime.now(),
    );

Future<void> pumpChat(WidgetTester tester, List<Message> rows) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MessagesProvider>(create: (_) => FakeMessages(rows)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ChatScreen(conversationId: conversationId, title: 'Thread'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  testWidgets('holding a message offers both deletions for your own',
      (tester) async {
    await pumpChat(tester, [msg('m1', 'mine', sender: myId)]);
    expect(find.text('mine'), findsOneWidget);

    await tester.longPress(find.text('mine'));
    await tester.pumpAndSettle();

    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);
  });

  testWidgets("and only delete-for-me on somebody else's", (tester) async {
    await pumpChat(tester, [msg('m2', 'theirs', sender: 'them')]);

    await tester.longPress(find.text('theirs'));
    await tester.pumpAndSettle();

    expect(find.text('Delete for me'), findsOneWidget);
    // Withdrawing the other party's words is not on offer, and the server
    // refuses it too.
    expect(find.text('Delete for everyone'), findsNothing);
  });

  testWidgets('a withdrawn message shows the tombstone and nothing else',
      (tester) async {
    await pumpChat(tester, [
      Message(
        id: 'm3',
        conversationId: conversationId,
        senderId: myId,
        body: null,
        deletedAt: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    ]);

    expect(find.text('This message was deleted'), findsOneWidget);
  });

  testWidgets('holding also offers reactions, reply and forward',
      (tester) async {
    await pumpChat(tester, [msg('m4', 'mine', sender: myId)]);

    await tester.longPress(find.text('mine'));
    await tester.pumpAndSettle();

    for (final emoji in MessagesProvider.reactionChoices) {
      expect(find.text(emoji), findsOneWidget, reason: emoji);
    }
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
  });

  testWidgets('a forwarded message is labelled, like WhatsApp', (tester) async {
    await pumpChat(tester,
        [msg('m5', 'passed along', sender: 'them', forwarded: true)]);

    expect(find.text('Forwarded'), findsOneWidget);
  });

  testWidgets('a reply quotes what it answers', (tester) async {
    await pumpChat(tester, [
      msg('orig', 'what are the fees?', sender: myId),
      msg('ans', 'twelve thousand', sender: 'them', replyTo: 'orig'),
    ]);

    // The quote and the original both render the same text, so two.
    expect(find.text('what are the fees?'), findsNWidgets(2));
    expect(find.text('twelve thousand'), findsOneWidget);
  });

  testWidgets('reactions show on the bubble, with a count when shared',
      (tester) async {
    await pumpChat(tester, [
      msg('m6', 'thanks', sender: 'them', reactions: {
        '🙏': [myId, 'them'],
        '😂': ['them'],
      }),
    ]);

    expect(find.text('🙏 2'), findsOneWidget);
    expect(find.text('😂'), findsOneWidget);
  });

  testWidgets('swiping right starts a reply', (tester) async {
    await pumpChat(tester, [msg('m7', 'swipe me', sender: 'them')]);

    await tester.drag(find.text('swipe me'), const Offset(320, 0));
    await tester.pumpAndSettle();

    // The composer now shows what it is answering.
    expect(find.text('Replying'), findsOneWidget);
    expect(find.text('swipe me'), findsNWidgets(2));
  });

  testWidgets('swiping left opens the actions, and deletes nothing on its own',
      (tester) async {
    await pumpChat(tester, [msg('m8', 'careful', sender: myId)]);

    await tester.drag(find.text('careful'), const Offset(-320, 0));
    await tester.pumpAndSettle();

    // A swipe asks; it does not act. The message is still there behind it.
    expect(find.text('Delete for everyone'), findsOneWidget);
    expect(find.text('careful'), findsOneWidget);
  });
}
