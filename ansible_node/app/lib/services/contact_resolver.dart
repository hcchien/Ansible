import 'package:ansible_store/ansible_store.dart';

typedef HandleResolver = Future<String> Function(String handle);

class ContactResolver {
  ContactResolver({
    required this.repository,
    this.handleResolver,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime.now().toUtc());

  final ContactRepository repository;
  final HandleResolver? handleResolver;
  final DateTime Function() now;

  Future<ContactRecord> resolveInput(String input) async {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(input, 'input', 'contact input is required');
    }

    if (normalized.startsWith('did:')) {
      final existing = await repository.contactForDid(normalized);
      if (existing != null) return existing;

      final timestamp = now();
      final contact = ContactRecord(
        subjectDid: normalized,
        source: 'manual',
        trustState: ContactTrustState.unverified,
        createdAt: timestamp,
        updatedAt: timestamp,
        lastResolvedAt: timestamp,
      );
      await repository.upsertContact(contact);
      return contact;
    }

    final resolve = handleResolver;
    if (resolve == null) {
      throw StateError('handle_resolver_unavailable');
    }

    final resolvedDid = await resolve(normalized);
    return repository.recordHandleResolution(
      handle: normalized,
      resolvedDid: resolvedDid,
      resolvedAt: now(),
    );
  }
}
