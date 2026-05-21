import 'package:flutter/material.dart';
import 'huddl_character.dart';
import '../theme/huddl_colors.dart';

// ─────────────────────────────────────────────
// CONNECT TAB — No conversations
// ─────────────────────────────────────────────
class ConnectEmptyState extends StatelessWidget {
  const ConnectEmptyState({super.key, required this.onCta});
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) => HuddlEmptyState(
        mood: HuddlMood.waving,
        title: 'It starts with hello',
        subtitle:
            'Join a group in Discover and your conversations will live here.',
        ctaLabel: 'Explore groups',
        onCta: onCta,
      );
}

// ─────────────────────────────────────────────
// CONNECT — Saved messages
// ─────────────────────────────────────────────
class SavedMessagesEmptyState extends StatelessWidget {
  const SavedMessagesEmptyState({super.key});

  @override
  Widget build(BuildContext context) => const HuddlEmptyState(
        mood: HuddlMood.waving,
        title: 'Save the good stuff',
        subtitle:
            'Long-press any message in a group chat to save it here for later.',
      );
}

// ─────────────────────────────────────────────
// PROFILE — My Groups
// ─────────────────────────────────────────────
class MyGroupsEmptyState extends StatelessWidget {
  const MyGroupsEmptyState({super.key, required this.onCta});
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) => HuddlEmptyState(
        mood: HuddlMood.neutral,
        title: 'Your crew is out there',
        subtitle:
            'Parents near you are already chatting — jump in and say hi.',
        ctaLabel: 'Find my groups',
        onCta: onCta,
      );
}

// ─────────────────────────────────────────────
// PROFILE — My Meetups
// ─────────────────────────────────────────────
class MyMeetupsEmptyState extends StatelessWidget {
  const MyMeetupsEmptyState({super.key, required this.onCta});
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) => HuddlEmptyState(
        mood: HuddlMood.celebrating,
        title: "No plans yet — let's fix that",
        subtitle:
            'There are meetups this week in Cambridge that match your family perfectly.',
        ctaLabel: 'Browse meetups',
        onCta: onCta,
      );
}

// ─────────────────────────────────────────────
// PROFILE — My Listings
// ─────────────────────────────────────────────
class MyListingsEmptyState extends StatelessWidget {
  const MyListingsEmptyState({super.key, required this.onCta});
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) => HuddlEmptyState(
        mood: HuddlMood.curious,
        title: 'That barely-used bouncer deserves a new home',
        subtitle:
            'List it in 60 seconds. Local parents are looking for exactly what you\'ve outgrown.',
        ctaLabel: 'List something',
        onCta: onCta,
      );
}

// ─────────────────────────────────────────────
// MARKET — Saved listings
// ─────────────────────────────────────────────
class MarketSavedEmptyState extends StatelessWidget {
  const MarketSavedEmptyState({super.key});

  @override
  Widget build(BuildContext context) => const HuddlEmptyState(
        mood: HuddlMood.neutral,
        title: 'Nothing saved yet',
        subtitle:
            'Tap the ❤️ on any listing to save it. Great deals go fast in Cambridge.',
      );
}

// ─────────────────────────────────────────────
// INSIGHTS — Community wisdom
// ─────────────────────────────────────────────
class CommunityInsightsEmptyState extends StatelessWidget {
  const CommunityInsightsEmptyState({super.key});

  @override
  Widget build(BuildContext context) => const HuddlEmptyState(
        mood: HuddlMood.curious,
        title: 'Wisdom is brewing',
        subtitle:
            'When Cambridge parents share great advice in group chats, it surfaces here. The more active your groups, the richer this gets.',
      );
}

// ─────────────────────────────────────────────
// SEND — Support empty state
// ─────────────────────────────────────────────
class SendSupportEmptyState extends StatelessWidget {
  const SendSupportEmptyState({super.key});

  @override
  Widget build(BuildContext context) => const HuddlEmptyState(
        mood: HuddlMood.supportive,
        characterSize: 140,
        title: "You're not alone in this",
        subtitle:
            'The SEND journey is tough. Huddl is here to help you find the right support and connect with other families.',
      );
}

// ─────────────────────────────────────────────
// CO-PILOT — Welcome state
// ─────────────────────────────────────────────
class CopilotWelcomeState extends StatelessWidget {
  const CopilotWelcomeState({
    super.key,
    required this.firstName,
    required this.suggestionChips,
    required this.onChipTap,
    required this.onQuickAction,
  });

  final String firstName;
  final List<String> suggestionChips;
  final void Function(String) onChipTap;
  final void Function(String) onQuickAction;

  static const _quickActions = [
    '📋 What should I be doing this week?',
    '💬 Help me write a group message',
    '🤔 Is this meetup right for us?',
    '🗒️ Explain my child\'s EHCP rights',
    '🌟 Surprise me',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          HuddlCharacter(mood: HuddlMood.waving, size: 140),
          const SizedBox(height: 20),
          Text(
            'Hi $firstName! 👋 What\'s on your mind?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'I know your family, your area, and what\'s on locally. Ask me anything.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF666666),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Dynamic suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: suggestionChips
                .map(
                  (chip) => ActionChip(
                    label: Text(chip),
                    onPressed: () => onChipTap(chip),
                    backgroundColor: HuddlColors.peachLight,
                    labelStyle: const TextStyle(
                      color: HuddlColors.primary,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: const BorderSide(color: HuddlColors.primary, width: 1),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick actions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF666666),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickActions
                .map(
                  (action) => ActionChip(
                    label: Text(action, style: const TextStyle(fontSize: 13)),
                    onPressed: () => onQuickAction(action),
                    backgroundColor: const Color(0xFFF7F7F7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: const BorderSide(
                        color: Color(0xFFE8E8E8),
                        width: 0.5,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
