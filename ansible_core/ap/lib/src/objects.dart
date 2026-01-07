
import 'activity_object.dart';

class Note extends ActivityObject {
  final String? content;
  final String? published;
  final String? url;
  final String? attributedTo;
  final List<String>? to;
  final List<String>? cc;
  final dynamic inReplyTo;

  const Note({
    String? id,
    this.content,
    this.published,
    this.url,
    this.attributedTo,
    this.to,
    this.cc,
    this.inReplyTo,
    List<String>? context,
  }) : super(id: id, type: 'Note', context: context);

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String?,
      content: json['content'] as String?,
      published: json['published'] as String?,
      url: json['url'] as String?,
      attributedTo: json['attributedTo'] as String?,
      to: (json['to'] as List?)?.map((e) => e as String).toList(),
      cc: (json['cc'] as List?)?.map((e) => e as String).toList(),
      inReplyTo: json['inReplyTo'],
      context: (json['@context'] is List) ? (json['@context'] as List).cast<String>() : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    if (content != null) map['content'] = content;
    if (published != null) map['published'] = published;
    if (url != null) map['url'] = url;
    if (attributedTo != null) map['attributedTo'] = attributedTo;
    if (to != null) map['to'] = to;
    if (cc != null) map['cc'] = cc;
    if (inReplyTo != null) map['inReplyTo'] = inReplyTo;
    return map;
  }
}

class Person extends ActivityObject {
  final String? preferredUsername;
  final String? name;
  final String? summary;
  final String? inbox;
  final String? outbox;
  final String? followers;
  final String? following;
  final dynamic icon;
  final dynamic publicKey;

  const Person({
    String? id,
    this.preferredUsername,
    this.name,
    this.summary,
    this.inbox,
    this.outbox,
    this.followers,
    this.following,
    this.icon,
    this.publicKey,
    List<String>? context,
  }) : super(id: id, type: 'Person', context: context);

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String?,
      preferredUsername: json['preferredUsername'] as String?,
      name: json['name'] as String?,
      summary: json['summary'] as String?,
      inbox: json['inbox'] as String?,
      outbox: json['outbox'] as String?,
      followers: json['followers'] as String?,
      following: json['following'] as String?,
      icon: json['icon'],
      publicKey: json['publicKey'],
      context: (json['@context'] is List) ? (json['@context'] as List).cast<String>() : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    if (preferredUsername != null) map['preferredUsername'] = preferredUsername;
    if (name != null) map['name'] = name;
    if (summary != null) map['summary'] = summary;
    if (inbox != null) map['inbox'] = inbox;
    if (outbox != null) map['outbox'] = outbox;
    if (followers != null) map['followers'] = followers;
    if (following != null) map['following'] = following;
    if (icon != null) map['icon'] = icon;
    if (publicKey != null) map['publicKey'] = publicKey;
    return map;
  }
}
