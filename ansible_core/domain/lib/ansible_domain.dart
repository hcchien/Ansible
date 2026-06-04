// Sync primitives — cursor-based Op stream (transport-agnostic)
export 'src/content/content_lineage_projector.dart';
export 'src/content/content_transformation_service.dart';
export 'src/follow/follow_feed_projector.dart';
export 'src/follow/content_item_feed_projector.dart';
export 'src/follow/follow_feed_source.dart';
export 'src/follow/follow_result.dart';
export 'src/follow/follow_service.dart';
export 'src/sync/delta_response.dart';
export 'src/sync/sync_result.dart';

// TODO(v1.1 Comp B): libp2p transport — will live in ansible_core/p2p (Rust FFI)
// TODO(v1.1 Comp A): DID identity service — lives in ansible_core/did
