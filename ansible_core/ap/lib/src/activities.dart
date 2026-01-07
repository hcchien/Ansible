
import 'activity_object.dart';

class Activity extends ActivityObject {
  final String? actor;
  final dynamic object;
  final dynamic target;
  final List<String>? to;
  final List<String>? cc;

  const Activity({
    String? id,
    required String type,
    this.actor,
    this.object,
    this.target,
    this.to,
    this.cc,
    List<String>? context,
  }) : super(id: id, type: type, context: context);

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'] as String?,
      type: json['type'] as String,
      actor: json['actor'] as String?,
      object: json['object'],
      target: json['target'],
      to: (json['to'] as List?)?.map((e) => e as String).toList(),
      cc: (json['cc'] as List?)?.map((e) => e as String).toList(),
      context: (json['@context'] is List) ? (json['@context'] as List).cast<String>() : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    if (actor != null) map['actor'] = actor;
    if (object != null) map['object'] = object;
    if (target != null) map['target'] = target;
    if (to != null) map['to'] = to;
    if (cc != null) map['cc'] = cc;
    return map;
  }
}
