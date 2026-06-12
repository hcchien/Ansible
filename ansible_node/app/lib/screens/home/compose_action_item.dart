import 'package:flutter/material.dart';

import '../../theme/ansible_design.dart';

class ComposeActionItem extends StatelessWidget {
  const ComposeActionItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AnsibleDesign.paperElev,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: AnsibleDesign.ink),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1.0,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right,
              color: AnsibleDesign.inkFaint,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
