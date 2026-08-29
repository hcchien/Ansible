import 'package:ansible_node/services/terms_acceptance_store.dart';

/// Keeps pre-existing navigation tests focused on their original surface.
/// The mandatory first-run Terms gate has dedicated coverage elsewhere.
class AcceptedTermsStore extends TermsAcceptanceStore {
  const AcceptedTermsStore();

  @override
  Future<bool> hasAcceptedCurrent() async => true;
}
