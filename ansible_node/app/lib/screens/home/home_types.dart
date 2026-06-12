/// Shared tab/board/filter types for the home experience.
library;

// Persisted screen-style buckets. The current home surface uses feed/forum.
enum ElixTab { feed, circle, inbox, you }

/// The primary swipe boards: 個人版 │ 時間軸 │ 討論區.
enum HomeBoard { personal, timeline, forum }

enum PersonalFilter { all, murmur, note }

// Within the "圈內" room, a sub-selection between murmur and notes.
enum CircleTab { murmur, notes }
