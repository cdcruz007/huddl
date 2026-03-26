/// Represents a message saved by the user from a group or DM conversation.
class SavedMessage {
  final String id;
  final String messageId; // original message id
  final String message; // message text
  final String senderName; // who sent the message
  final DateTime timestamp; // when the message was originally sent
  final DateTime savedAt; // when the user saved it
  final bool isFromGroup; // true = group, false = DM
  // Source info for groups
  final String? groupId;
  final String? groupName;
  final String? groupImageUrl;
  // Source info for DMs
  final String? dmRecipientId;
  final String? dmRecipientName;
  final String? dmRecipientAvatarColor;
  final String? dmConversationId;

  SavedMessage({
    required this.id,
    required this.messageId,
    required this.message,
    required this.senderName,
    required this.timestamp,
    required this.savedAt,
    required this.isFromGroup,
    this.groupId,
    this.groupName,
    this.groupImageUrl,
    this.dmRecipientId,
    this.dmRecipientName,
    this.dmRecipientAvatarColor,
    this.dmConversationId,
  });

  String get sourceName => isFromGroup ? (groupName ?? 'Group') : (dmRecipientName ?? 'DM');

  Map<String, dynamic> toJson() => {
        'id': id,
        'messageId': messageId,
        'message': message,
        'senderName': senderName,
        'timestamp': timestamp.toIso8601String(),
        'savedAt': savedAt.toIso8601String(),
        'isFromGroup': isFromGroup,
        'groupId': groupId,
        'groupName': groupName,
        'groupImageUrl': groupImageUrl,
        'dmRecipientId': dmRecipientId,
        'dmRecipientName': dmRecipientName,
        'dmRecipientAvatarColor': dmRecipientAvatarColor,
        'dmConversationId': dmConversationId,
      };

  factory SavedMessage.fromJson(Map<String, dynamic> json) {
    return SavedMessage(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      message: json['message'] as String,
      senderName: json['senderName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      savedAt: DateTime.parse(json['savedAt'] as String),
      isFromGroup: json['isFromGroup'] as bool? ?? true,
      groupId: json['groupId'] as String?,
      groupName: json['groupName'] as String?,
      groupImageUrl: json['groupImageUrl'] as String?,
      dmRecipientId: json['dmRecipientId'] as String?,
      dmRecipientName: json['dmRecipientName'] as String?,
      dmRecipientAvatarColor: json['dmRecipientAvatarColor'] as String?,
      dmConversationId: json['dmConversationId'] as String?,
    );
  }
}
