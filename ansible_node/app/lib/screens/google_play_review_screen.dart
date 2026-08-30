import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../services/discovery_client.dart';
import '../theme/ansible_design.dart';

/// Public, credential-free surface for a Google Play review artifact.
///
/// Constitution Review:
/// - No DID, passkey, private key, profile, or private content is created or
///   read here.
/// - The only network request is the AppView's existing public explore feed.
/// - This screen deliberately has no write, follow, sync, or identity action.
class GooglePlayReviewScreen extends StatefulWidget {
  const GooglePlayReviewScreen({super.key, this.client});

  final DiscoveryClient? client;

  @override
  State<GooglePlayReviewScreen> createState() => _GooglePlayReviewScreenState();
}

class _GooglePlayReviewScreenState extends State<GooglePlayReviewScreen> {
  late final Future<List<DiscoveredPost>> _posts;

  @override
  void initState() {
    super.initState();
    final client =
        widget.client ??
        DiscoveryClient(
          appViewBaseUrl: AppEnvironment.appViewBaseUrl,
          relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
        );
    _posts = client.explore(limit: 30);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elix public content')),
      body: FutureBuilder<List<DiscoveredPost>>(
        future: _posts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Google Play review access',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'This is a read-only view of public Elix content. It does not '
                'create an account, a DID, or a passkey, and it cannot access '
                'private content or make changes.',
              ),
              const SizedBox(height: 20),
              if (snapshot.hasError)
                Text(
                  'Public content could not be loaded. Please verify the AppView '
                  'endpoint in this review build.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (posts == null || posts.isEmpty)
                const Text('No public posts are available at this time.')
              else
                ...posts.map(_postCard),
            ],
          );
        },
      ),
    );
  }

  Widget _postCard(DiscoveredPost post) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.authorDid,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(post.body.isEmpty ? '(No text)' : post.body),
        ],
      ),
    ),
  );
}
