import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8C9EFF),
      brightness: Brightness.dark,
      background: const Color(0xFF0B1428),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ansible Forum',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        textTheme: ThemeData.dark().textTheme,
        useMaterial3: true,
      ),
      home: const ForumHomePage(),
    );
  }
}

class ForumHomePage extends StatelessWidget {
  const ForumHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1428), Color(0xFF0F1C34)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: const [
              SizedBox(width: 280, child: _Sidebar()),
              Expanded(child: _MainPanel()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final boards = [
      BoardNavItem(title: '全部動態', badge: '全部動態'),
      BoardNavItem(title: '公告', badge: '23', subtitle: '公', accent: Colors.deepPurple),
      BoardNavItem(title: '新手入門', badge: '156', subtitle: '新', accent: Colors.blue),
      BoardNavItem(title: '智能合約', badge: '342', subtitle: '智', accent: Colors.teal),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '我的看板',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: boards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = boards[index];
                return _BoardTile(item: item, selected: index == 0);
              },
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('管理看板'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.item, this.selected = false});

  final BoardNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.white.withOpacity(0.06) : Colors.transparent;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.accent.withOpacity(0.15),
          foregroundColor: item.accent,
          child: Text(item.subtitle ?? item.title.characters.first),
        ),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: item.subtitle != null
            ? Text(item.subtitle!, style: TextStyle(color: Colors.white70, fontSize: 12))
            : null,
        trailing: item.badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.badge!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            : null,
        onTap: () {},
      ),
    );
  }
}

class BoardNavItem {
  BoardNavItem({
    required this.title,
    this.badge,
    this.subtitle,
    this.accent = Colors.indigo,
  });

  final String title;
  final String? badge;
  final String? subtitle;
  final Color accent;
}

class _MainPanel extends StatelessWidget {
  const _MainPanel();

  @override
  Widget build(BuildContext context) {
    final posts = [
      PostCardData(
        category: '公告',
        title: '【維運通知】12/21 00:00~02:00 系統維護',
        author: 'Admin',
        board: '公告',
        timeAgo: '1 小時前',
        reactions: const {'👍': 2, '❤️': 1},
        comments: 1,
      ),
      PostCardData(
        category: '新手入門',
        title: '新手快速上手指南',
        author: 'Admin',
        board: '新手入門',
        timeAgo: '2 小時前',
        reactions: const {'😂': 1},
        comments: 0,
      ),
      PostCardData(
        category: '智能合約',
        title: '聊聊近期智能合約風險案例',
        author: 'Alice',
        board: '智能合約',
        timeAgo: '15 分鐘前',
        reactions: const {},
        comments: 0,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TopBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: posts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) => PostCard(data: posts[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: const Icon(Icons.bolt, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ansible Forum',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('連接錢包'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Colors.white.withOpacity(0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.view_sidebar_outlined),
          color: Colors.white70,
        ),
        const SizedBox(width: 8),
        const Text(
          '全部動態',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class PostCardData {
  PostCardData({
    required this.category,
    required this.title,
    required this.author,
    required this.board,
    required this.timeAgo,
    required this.reactions,
    required this.comments,
  });

  final String category;
  final String title;
  final String author;
  final String board;
  final String timeAgo;
  final Map<String, int> reactions;
  final int comments;
}

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.data});

  final PostCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  data.category,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_horiz),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            data.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Text(data.author, style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              const Icon(Icons.forum_outlined, size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Text(data.board, style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              const Icon(Icons.access_time, size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Text(data.timeAgo, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ...data.reactions.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ReactionChip(label: entry.key, count: entry.value),
                ),
              ),
              _CommentChip(count: data.comments),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {},
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text('$label $count'),
    );
  }
}

class _CommentChip extends StatelessWidget {
  const _CommentChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.chat_bubble_outline, size: 18),
      label: Text('$count 則留言'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
