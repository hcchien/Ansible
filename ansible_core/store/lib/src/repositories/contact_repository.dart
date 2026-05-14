import '../entities/contact_entities.dart';

abstract class ContactRepository {
  Future<void> upsertContact(ContactRecord contact);
  Future<ContactRecord?> contactForDid(String subjectDid);
  Future<ContactRecord?> contactForHandle(String handle);
  Future<List<ContactRecord>> listContacts();

  Future<ContactRecord> recordHandleResolution({
    required String handle,
    required String resolvedDid,
    required DateTime resolvedAt,
  });
}
