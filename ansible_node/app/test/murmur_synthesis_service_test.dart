import 'package:ansible_node/services/ai/ai_provider.dart';
import 'package:ansible_node/services/ai/murmur_synthesis_service.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocks remote synthesis for private context without consent', () async {
    final provider = _RecordingAiProvider();
    final service = MurmurSynthesisService(
      provider,
      providerType: AiProviderType.openaiCompatible,
    );

    await expectLater(
      service.synthesize(
        selectedMurmurs: [
          ContentItem(
            id: 'murmur-private',
            authorDid: 'did:plc:alice',
            mode: ContentMode.murmur,
            body: 'private thought',
            status: ContentStatus.active,
            visibility: ContentVisibility.private,
            createdAt: DateTime.utc(2026, 5, 23),
            updatedAt: DateTime.utc(2026, 5, 23),
            localOnly: true,
          ),
        ],
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(provider.requests, isEmpty);
  });

  test('allows remote synthesis after explicit consent', () async {
    final provider = _RecordingAiProvider();
    final service = MurmurSynthesisService(
      provider,
      providerType: AiProviderType.openaiCompatible,
      explicitRemoteConsent: true,
    );

    final draft = await service.synthesize(
      selectedMurmurs: [
        ContentItem(
          id: 'murmur-private',
          authorDid: 'did:plc:alice',
          mode: ContentMode.murmur,
          body: 'private thought',
          status: ContentStatus.active,
          visibility: ContentVisibility.private,
          createdAt: DateTime.utc(2026, 5, 23),
          updatedAt: DateTime.utc(2026, 5, 23),
          localOnly: true,
        ),
      ],
    );

    expect(draft, 'draft');
    expect(provider.requests, hasLength(1));
  });

  test('treats note title context as private for remote synthesis', () async {
    final provider = _RecordingAiProvider();
    final service = MurmurSynthesisService(
      provider,
      providerType: AiProviderType.openaiCompatible,
    );

    await expectLater(
      service.synthesize(
        selectedMurmurs: [
          ContentItem(
            id: 'murmur-public',
            authorDid: 'did:plc:alice',
            mode: ContentMode.murmur,
            body: 'public thought',
            status: ContentStatus.active,
            visibility: ContentVisibility.public,
            createdAt: DateTime.utc(2026, 5, 23),
            updatedAt: DateTime.utc(2026, 5, 23),
          ),
        ],
        noteTitle: 'private draft title',
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(provider.requests, isEmpty);
  });
}

class _RecordingAiProvider implements AiProvider {
  final requests = <AiProviderRequest>[];

  @override
  Future<AiProviderResult> complete(AiProviderRequest request) async {
    requests.add(request);
    return const AiProviderResult(
      providerType: 'openaiCompatible',
      structuredJson: {'draft_paragraph': 'draft'},
      rawText: '{"draft_paragraph":"draft"}',
    );
  }
}
