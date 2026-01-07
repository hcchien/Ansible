
abstract class ActivityObject {
  final String? id;
  final String type;
  final List<String>? context;
  final Map<String, dynamic>? extra;

  const ActivityObject({
    this.id,
    required this.type,
    this.context,
    this.extra,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (context != null) '@context': context,
      if (id != null) 'id': id,
      'type': type,
    };
    if (extra != null) {
      map.addAll(extra!);
    }
    return map;
  }
}
