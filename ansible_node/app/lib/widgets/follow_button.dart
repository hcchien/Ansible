import 'package:flutter/material.dart';

enum FollowButtonStatus { notFollowing, requested, following, failed, blocked }

class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.status,
    required this.onPressed,
  });

  final FollowButtonStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      FollowButtonStatus.notFollowing => 'Follow',
      FollowButtonStatus.requested => 'Requested',
      FollowButtonStatus.following => 'Following',
      FollowButtonStatus.failed => 'Retry',
      FollowButtonStatus.blocked => 'Blocked',
    };
    return FilledButton.tonal(
      onPressed: status == FollowButtonStatus.blocked ? null : onPressed,
      child: Text(label),
    );
  }
}
