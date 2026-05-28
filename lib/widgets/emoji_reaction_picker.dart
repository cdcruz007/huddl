import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import '../theme/huddl_animations.dart';
import '../constants/app_text_styles.dart';

/// The 6 quick-access emojis shown in the floating bar above a message.
const List<String> kQuickEmojis = ['❤️', '😂', '😮', '😢', '👍', '🙏'];

/// Full emoji categories for the expanded picker.
const Map<String, List<String>> kEmojiCategories = {
  'Smileys': [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
    '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
    '🥲', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫',
    '🤔', '🫡', '🤐', '🤨', '😐', '😑', '😶', '🫥', '😏', '😒',
    '🙄', '😬', '🤥', '🫨', '😌', '😔', '😪', '🤤', '😴', '😷',
    '🤒', '🤕', '🤢', '🤮', '🥵', '🥶', '🥴', '😵', '🤯', '🤠',
    '🥳', '🥸', '😎', '🤓', '🧐', '😕', '🫤', '😟', '🙁', '😮',
    '😯', '😲', '😳', '🥺', '🥹', '😦', '😧', '😨', '😰', '😥',
    '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱',
  ],
  'Gestures': [
    '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌', '🫶', '👐',
    '🤲', '🤝', '🙏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈',
    '👉', '👆', '🖕', '👇', '☝️', '🫵', '👋', '🤚', '🖐️', '✋',
    '🖖', '🫱', '🫲', '🫳', '🫴', '💪', '🦾', '🖖', '✍️', '🤳',
    '💅', '🦵', '🦶', '👂', '🦻', '👃', '👀', '👁️', '👅', '👄',
  ],
  'Hearts': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝',
    '💟', '♥️', '🫀', '💋', '💌', '💐', '🌹', '🥀', '🌺', '🌸',
  ],
  'Animals': [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐻‍❄️', '🐨',
    '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒',
    '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇',
    '🐺', '🐗', '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌', '🐞',
  ],
  'Food': [
    '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈',
    '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🫛',
    '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🧄', '🧅', '🥔',
    '🍞', '🥐', '🥖', '🫓', '🥨', '🥯', '🥞', '🧇', '🧀', '🍖',
  ],
  'Objects': [
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
    '🪀', '🏓', '🏸', '🏒', '🥅', '⛳', '🪁', '🏹', '🎣', '🤿',
    '🎯', '🎮', '🕹️', '🎰', '🎲', '🧩', '🎭', '🎨', '🎬', '🎤',
    '🎧', '🎼', '🎹', '🥁', '🪘', '🎷', '🎺', '🪗', '🎸', '🎻',
  ],
  'Flags': [
    '🏳️', '🏴', '🏁', '🚩', '🏳️‍🌈', '🏳️‍⚧️', '🏴‍☠️', '🇬🇧', '🇺🇸', '🇫🇷',
    '🇩🇪', '🇮🇹', '🇪🇸', '🇯🇵', '🇰🇷', '🇨🇳', '🇮🇳', '🇧🇷', '🇦🇺', '🇨🇦',
  ],
};

/// Shows a quick-access emoji row floating above a message, plus a "+" to open
/// the full picker. Returns the chosen emoji string, or null if dismissed.
Future<String?> showEmojiReactionPicker(BuildContext context) async {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black26,
    builder: (ctx) => const _EmojiPickerDialog(),
  );
}

class _EmojiPickerDialog extends StatefulWidget {
  const _EmojiPickerDialog();

  @override
  State<_EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<_EmojiPickerDialog> {
  bool _showFull = false;
  String _selectedCategory = 'Smileys';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: _showFull ? _buildFullPicker() : _buildQuickBar(),
      ),
    );
  }

  Widget _buildQuickBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...kQuickEmojis.map((emoji) => _emojiButton(emoji)),
          // "+" button to expand full picker
          GestureDetector(
            onTap: () => setState(() => _showFull = true),
            child: Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: context.hc.scaffold,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: context.hc.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiButton(String emoji) {
    return Semantics(
      label: 'React with $emoji',
      button: true,
      child: ScaleOnPress(
        scale: 0.85,
        duration: const Duration(milliseconds: 100),
        onTap: () => Navigator.pop(context, emoji),
        child: Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  Widget _buildFullPicker() {
    final emojis = kEmojiCategories[_selectedCategory] ?? [];
    final categories = kEmojiCategories.keys.toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text(
                  'Choose a reaction',
                  style: HuddlText.body(weight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Quick access row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: kQuickEmojis.map((e) => _emojiButton(e)).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: context.hc.divider),

          // Category tabs
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: categories.map((cat) {
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? HuddlColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      cat,
                      style: HuddlText.caption(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Emoji grid
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: emojis.length,
              itemBuilder: (ctx, i) {
                return ScaleOnPress(
                  scale: 0.85,
                  duration: const Duration(milliseconds: 100),
                  onTap: () => Navigator.pop(context, emojis[i]),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(emojis[i], style: const TextStyle(fontSize: 22)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a row of emoji reaction chips below a chat bubble.
class EmojiReactionDisplay extends StatelessWidget {
  final Map<String, int> reactions; // emoji → count
  final bool isMe;
  final void Function(String emoji)? onTapReaction;

  const EmojiReactionDisplay({
    super.key,
    required this.reactions,
    required this.isMe,
    this.onTapReaction,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isMe ? 60 : 40,
        right: isMe ? 0 : 60,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          children: reactions.entries.map((entry) {
            return GestureDetector(
              onTap: () => onTapReaction?.call(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.hc.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.hc.divider,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 14)),
                    if (entry.value > 1) ...[
                      const SizedBox(width: 2),
                      Text(
                        '${entry.value}',
                        style: HuddlText.caption(weight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
