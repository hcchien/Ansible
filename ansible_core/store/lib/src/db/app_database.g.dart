// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BoardsTable extends Boards with TableInfo<$BoardsTable, Board> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    boardId,
    slug,
    title,
    description,
    createdAt,
    updatedAt,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'boards';
  @override
  VerificationContext validateIntegrity(
    Insertable<Board> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {boardId};
  @override
  Board map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Board(
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}board_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $BoardsTable createAlias(String alias) {
    return $BoardsTable(attachedDatabase, alias);
  }
}

class Board extends DataClass implements Insertable<Board> {
  final String boardId;
  final String slug;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  const Board({
    required this.boardId,
    required this.slug,
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['board_id'] = Variable<String>(boardId);
    map['slug'] = Variable<String>(slug);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  BoardsCompanion toCompanion(bool nullToAbsent) {
    return BoardsCompanion(
      boardId: Value(boardId),
      slug: Value(slug),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
    );
  }

  factory Board.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Board(
      boardId: serializer.fromJson<String>(json['boardId']),
      slug: serializer.fromJson<String>(json['slug']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'boardId': serializer.toJson<String>(boardId),
      'slug': serializer.toJson<String>(slug),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  Board copyWith({
    String? boardId,
    String? slug,
    String? title,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) => Board(
    boardId: boardId ?? this.boardId,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  Board copyWithCompanion(BoardsCompanion data) {
    return Board(
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      slug: data.slug.present ? data.slug.value : this.slug,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Board(')
          ..write('boardId: $boardId, ')
          ..write('slug: $slug, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    boardId,
    slug,
    title,
    description,
    createdAt,
    updatedAt,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Board &&
          other.boardId == this.boardId &&
          other.slug == this.slug &&
          other.title == this.title &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted);
}

class BoardsCompanion extends UpdateCompanion<Board> {
  final Value<String> boardId;
  final Value<String> slug;
  final Value<String> title;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const BoardsCompanion({
    this.boardId = const Value.absent(),
    this.slug = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardsCompanion.insert({
    required String boardId,
    required String slug,
    required String title,
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : boardId = Value(boardId),
       slug = Value(slug),
       title = Value(title);
  static Insertable<Board> custom({
    Expression<String>? boardId,
    Expression<String>? slug,
    Expression<String>? title,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (boardId != null) 'board_id': boardId,
      if (slug != null) 'slug': slug,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardsCompanion copyWith({
    Value<String>? boardId,
    Value<String>? slug,
    Value<String>? title,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<int>? rowid,
  }) {
    return BoardsCompanion(
      boardId: boardId ?? this.boardId,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardsCompanion(')
          ..write('boardId: $boardId, ')
          ..write('slug: $slug, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _passwordHashMeta = const VerificationMeta(
    'passwordHash',
  );
  @override
  late final GeneratedColumn<String> passwordHash = GeneratedColumn<String>(
    'password_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    username,
    passwordHash,
    displayName,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('password_hash')) {
      context.handle(
        _passwordHashMeta,
        passwordHash.isAcceptableOrUnknown(
          data['password_hash']!,
          _passwordHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_passwordHashMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      passwordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_hash'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final String userId;
  final String username;
  final String passwordHash;
  final String? displayName;
  final DateTime createdAt;
  final DateTime updatedAt;
  const User({
    required this.userId,
    required this.username,
    required this.passwordHash,
    this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['password_hash'] = Variable<String>(passwordHash);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      userId: Value(userId),
      username: Value(username),
      passwordHash: Value(passwordHash),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      passwordHash: serializer.fromJson<String>(json['passwordHash']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'passwordHash': serializer.toJson<String>(passwordHash),
      'displayName': serializer.toJson<String?>(displayName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  User copyWith({
    String? userId,
    String? username,
    String? passwordHash,
    Value<String?> displayName = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => User(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    passwordHash: passwordHash ?? this.passwordHash,
    displayName: displayName.present ? displayName.value : this.displayName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      passwordHash: data.passwordHash.present
          ? data.passwordHash.value
          : this.passwordHash,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    username,
    passwordHash,
    displayName,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.passwordHash == this.passwordHash &&
          other.displayName == this.displayName &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> userId;
  final Value<String> username;
  final Value<String> passwordHash;
  final Value<String?> displayName;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UsersCompanion({
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String userId,
    required String username,
    required String passwordHash,
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       username = Value(username),
       passwordHash = Value(passwordHash);
  static Insertable<User> custom({
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? passwordHash,
    Expression<String>? displayName,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (passwordHash != null) 'password_hash': passwordHash,
      if (displayName != null) 'display_name': displayName,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? userId,
    Value<String>? username,
    Value<String>? passwordHash,
    Value<String?>? displayName,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (passwordHash.present) {
      map['password_hash'] = Variable<String>(passwordHash.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThreadsTable extends Threads with TableInfo<$ThreadsTable, Thread> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThreadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES boards (board_id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    threadId,
    boardId,
    title,
    authorId,
    createdAt,
    updatedAt,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'threads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Thread> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {threadId};
  @override
  Thread map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Thread(
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}board_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $ThreadsTable createAlias(String alias) {
    return $ThreadsTable(attachedDatabase, alias);
  }
}

class Thread extends DataClass implements Insertable<Thread> {
  final String threadId;
  final String boardId;
  final String title;
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  const Thread({
    required this.threadId,
    required this.boardId,
    required this.title,
    required this.authorId,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['thread_id'] = Variable<String>(threadId);
    map['board_id'] = Variable<String>(boardId);
    map['title'] = Variable<String>(title);
    map['author_id'] = Variable<String>(authorId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  ThreadsCompanion toCompanion(bool nullToAbsent) {
    return ThreadsCompanion(
      threadId: Value(threadId),
      boardId: Value(boardId),
      title: Value(title),
      authorId: Value(authorId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDeleted: Value(isDeleted),
    );
  }

  factory Thread.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Thread(
      threadId: serializer.fromJson<String>(json['threadId']),
      boardId: serializer.fromJson<String>(json['boardId']),
      title: serializer.fromJson<String>(json['title']),
      authorId: serializer.fromJson<String>(json['authorId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'threadId': serializer.toJson<String>(threadId),
      'boardId': serializer.toJson<String>(boardId),
      'title': serializer.toJson<String>(title),
      'authorId': serializer.toJson<String>(authorId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  Thread copyWith({
    String? threadId,
    String? boardId,
    String? title,
    String? authorId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) => Thread(
    threadId: threadId ?? this.threadId,
    boardId: boardId ?? this.boardId,
    title: title ?? this.title,
    authorId: authorId ?? this.authorId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  Thread copyWithCompanion(ThreadsCompanion data) {
    return Thread(
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      title: data.title.present ? data.title.value : this.title,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Thread(')
          ..write('threadId: $threadId, ')
          ..write('boardId: $boardId, ')
          ..write('title: $title, ')
          ..write('authorId: $authorId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    threadId,
    boardId,
    title,
    authorId,
    createdAt,
    updatedAt,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Thread &&
          other.threadId == this.threadId &&
          other.boardId == this.boardId &&
          other.title == this.title &&
          other.authorId == this.authorId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isDeleted == this.isDeleted);
}

class ThreadsCompanion extends UpdateCompanion<Thread> {
  final Value<String> threadId;
  final Value<String> boardId;
  final Value<String> title;
  final Value<String> authorId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const ThreadsCompanion({
    this.threadId = const Value.absent(),
    this.boardId = const Value.absent(),
    this.title = const Value.absent(),
    this.authorId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThreadsCompanion.insert({
    required String threadId,
    required String boardId,
    required String title,
    required String authorId,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : threadId = Value(threadId),
       boardId = Value(boardId),
       title = Value(title),
       authorId = Value(authorId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Thread> custom({
    Expression<String>? threadId,
    Expression<String>? boardId,
    Expression<String>? title,
    Expression<String>? authorId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (threadId != null) 'thread_id': threadId,
      if (boardId != null) 'board_id': boardId,
      if (title != null) 'title': title,
      if (authorId != null) 'author_id': authorId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThreadsCompanion copyWith({
    Value<String>? threadId,
    Value<String>? boardId,
    Value<String>? title,
    Value<String>? authorId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isDeleted,
    Value<int>? rowid,
  }) {
    return ThreadsCompanion(
      threadId: threadId ?? this.threadId,
      boardId: boardId ?? this.boardId,
      title: title ?? this.title,
      authorId: authorId ?? this.authorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadsCompanion(')
          ..write('threadId: $threadId, ')
          ..write('boardId: $boardId, ')
          ..write('title: $title, ')
          ..write('authorId: $authorId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PostsTable extends Posts with TableInfo<$PostsTable, Post> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _postIdMeta = const VerificationMeta('postId');
  @override
  late final GeneratedColumn<String> postId = GeneratedColumn<String>(
    'post_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES threads (thread_id)',
    ),
  );
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES boards (board_id)',
    ),
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id)',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentPostIdMeta = const VerificationMeta(
    'parentPostId',
  );
  @override
  late final GeneratedColumn<String> parentPostId = GeneratedColumn<String>(
    'parent_post_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES posts (post_id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastEditAtMeta = const VerificationMeta(
    'lastEditAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastEditAt = GeneratedColumn<DateTime>(
    'last_edit_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    postId,
    threadId,
    boardId,
    authorId,
    content,
    parentPostId,
    createdAt,
    updatedAt,
    lastEditAt,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'posts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Post> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('post_id')) {
      context.handle(
        _postIdMeta,
        postId.isAcceptableOrUnknown(data['post_id']!, _postIdMeta),
      );
    } else if (isInserting) {
      context.missing(_postIdMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('parent_post_id')) {
      context.handle(
        _parentPostIdMeta,
        parentPostId.isAcceptableOrUnknown(
          data['parent_post_id']!,
          _parentPostIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_edit_at')) {
      context.handle(
        _lastEditAtMeta,
        lastEditAt.isAcceptableOrUnknown(
          data['last_edit_at']!,
          _lastEditAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastEditAtMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {postId};
  @override
  Post map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Post(
      postId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}board_id'],
      )!,
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      parentPostId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_post_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastEditAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_edit_at'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $PostsTable createAlias(String alias) {
    return $PostsTable(attachedDatabase, alias);
  }
}

class Post extends DataClass implements Insertable<Post> {
  final String postId;
  final String threadId;
  final String boardId;
  final String authorId;
  final String content;
  final String? parentPostId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastEditAt;
  final bool isDeleted;
  const Post({
    required this.postId,
    required this.threadId,
    required this.boardId,
    required this.authorId,
    required this.content,
    this.parentPostId,
    required this.createdAt,
    required this.updatedAt,
    required this.lastEditAt,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['post_id'] = Variable<String>(postId);
    map['thread_id'] = Variable<String>(threadId);
    map['board_id'] = Variable<String>(boardId);
    map['author_id'] = Variable<String>(authorId);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || parentPostId != null) {
      map['parent_post_id'] = Variable<String>(parentPostId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['last_edit_at'] = Variable<DateTime>(lastEditAt);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  PostsCompanion toCompanion(bool nullToAbsent) {
    return PostsCompanion(
      postId: Value(postId),
      threadId: Value(threadId),
      boardId: Value(boardId),
      authorId: Value(authorId),
      content: Value(content),
      parentPostId: parentPostId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentPostId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastEditAt: Value(lastEditAt),
      isDeleted: Value(isDeleted),
    );
  }

  factory Post.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Post(
      postId: serializer.fromJson<String>(json['postId']),
      threadId: serializer.fromJson<String>(json['threadId']),
      boardId: serializer.fromJson<String>(json['boardId']),
      authorId: serializer.fromJson<String>(json['authorId']),
      content: serializer.fromJson<String>(json['content']),
      parentPostId: serializer.fromJson<String?>(json['parentPostId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastEditAt: serializer.fromJson<DateTime>(json['lastEditAt']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'postId': serializer.toJson<String>(postId),
      'threadId': serializer.toJson<String>(threadId),
      'boardId': serializer.toJson<String>(boardId),
      'authorId': serializer.toJson<String>(authorId),
      'content': serializer.toJson<String>(content),
      'parentPostId': serializer.toJson<String?>(parentPostId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastEditAt': serializer.toJson<DateTime>(lastEditAt),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  Post copyWith({
    String? postId,
    String? threadId,
    String? boardId,
    String? authorId,
    String? content,
    Value<String?> parentPostId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastEditAt,
    bool? isDeleted,
  }) => Post(
    postId: postId ?? this.postId,
    threadId: threadId ?? this.threadId,
    boardId: boardId ?? this.boardId,
    authorId: authorId ?? this.authorId,
    content: content ?? this.content,
    parentPostId: parentPostId.present ? parentPostId.value : this.parentPostId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastEditAt: lastEditAt ?? this.lastEditAt,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  Post copyWithCompanion(PostsCompanion data) {
    return Post(
      postId: data.postId.present ? data.postId.value : this.postId,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      content: data.content.present ? data.content.value : this.content,
      parentPostId: data.parentPostId.present
          ? data.parentPostId.value
          : this.parentPostId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastEditAt: data.lastEditAt.present
          ? data.lastEditAt.value
          : this.lastEditAt,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Post(')
          ..write('postId: $postId, ')
          ..write('threadId: $threadId, ')
          ..write('boardId: $boardId, ')
          ..write('authorId: $authorId, ')
          ..write('content: $content, ')
          ..write('parentPostId: $parentPostId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastEditAt: $lastEditAt, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    postId,
    threadId,
    boardId,
    authorId,
    content,
    parentPostId,
    createdAt,
    updatedAt,
    lastEditAt,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Post &&
          other.postId == this.postId &&
          other.threadId == this.threadId &&
          other.boardId == this.boardId &&
          other.authorId == this.authorId &&
          other.content == this.content &&
          other.parentPostId == this.parentPostId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastEditAt == this.lastEditAt &&
          other.isDeleted == this.isDeleted);
}

class PostsCompanion extends UpdateCompanion<Post> {
  final Value<String> postId;
  final Value<String> threadId;
  final Value<String> boardId;
  final Value<String> authorId;
  final Value<String> content;
  final Value<String?> parentPostId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime> lastEditAt;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const PostsCompanion({
    this.postId = const Value.absent(),
    this.threadId = const Value.absent(),
    this.boardId = const Value.absent(),
    this.authorId = const Value.absent(),
    this.content = const Value.absent(),
    this.parentPostId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastEditAt = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PostsCompanion.insert({
    required String postId,
    required String threadId,
    required String boardId,
    required String authorId,
    required String content,
    this.parentPostId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime lastEditAt,
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : postId = Value(postId),
       threadId = Value(threadId),
       boardId = Value(boardId),
       authorId = Value(authorId),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       lastEditAt = Value(lastEditAt);
  static Insertable<Post> custom({
    Expression<String>? postId,
    Expression<String>? threadId,
    Expression<String>? boardId,
    Expression<String>? authorId,
    Expression<String>? content,
    Expression<String>? parentPostId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastEditAt,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (postId != null) 'post_id': postId,
      if (threadId != null) 'thread_id': threadId,
      if (boardId != null) 'board_id': boardId,
      if (authorId != null) 'author_id': authorId,
      if (content != null) 'content': content,
      if (parentPostId != null) 'parent_post_id': parentPostId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastEditAt != null) 'last_edit_at': lastEditAt,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PostsCompanion copyWith({
    Value<String>? postId,
    Value<String>? threadId,
    Value<String>? boardId,
    Value<String>? authorId,
    Value<String>? content,
    Value<String?>? parentPostId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime>? lastEditAt,
    Value<bool>? isDeleted,
    Value<int>? rowid,
  }) {
    return PostsCompanion(
      postId: postId ?? this.postId,
      threadId: threadId ?? this.threadId,
      boardId: boardId ?? this.boardId,
      authorId: authorId ?? this.authorId,
      content: content ?? this.content,
      parentPostId: parentPostId ?? this.parentPostId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastEditAt: lastEditAt ?? this.lastEditAt,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (postId.present) {
      map['post_id'] = Variable<String>(postId.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (parentPostId.present) {
      map['parent_post_id'] = Variable<String>(parentPostId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastEditAt.present) {
      map['last_edit_at'] = Variable<DateTime>(lastEditAt.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PostsCompanion(')
          ..write('postId: $postId, ')
          ..write('threadId: $threadId, ')
          ..write('boardId: $boardId, ')
          ..write('authorId: $authorId, ')
          ..write('content: $content, ')
          ..write('parentPostId: $parentPostId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastEditAt: $lastEditAt, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReactionsTable extends Reactions
    with TableInfo<$ReactionsTable, Reaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id)',
    ),
  );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reactionTypeMeta = const VerificationMeta(
    'reactionType',
  );
  @override
  late final GeneratedColumn<String> reactionType = GeneratedColumn<String>(
    'reaction_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    targetType,
    targetId,
    reactionType,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Reaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('reaction_type')) {
      context.handle(
        _reactionTypeMeta,
        reactionType.isAcceptableOrUnknown(
          data['reaction_type']!,
          _reactionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reactionTypeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Reaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Reaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      reactionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reaction_type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReactionsTable createAlias(String alias) {
    return $ReactionsTable(attachedDatabase, alias);
  }
}

class Reaction extends DataClass implements Insertable<Reaction> {
  final String id;
  final String userId;
  final String targetType;
  final String targetId;
  final String reactionType;
  final DateTime createdAt;
  const Reaction({
    required this.id,
    required this.userId,
    required this.targetType,
    required this.targetId,
    required this.reactionType,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['target_type'] = Variable<String>(targetType);
    map['target_id'] = Variable<String>(targetId);
    map['reaction_type'] = Variable<String>(reactionType);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReactionsCompanion toCompanion(bool nullToAbsent) {
    return ReactionsCompanion(
      id: Value(id),
      userId: Value(userId),
      targetType: Value(targetType),
      targetId: Value(targetId),
      reactionType: Value(reactionType),
      createdAt: Value(createdAt),
    );
  }

  factory Reaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Reaction(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<String>(json['targetId']),
      reactionType: serializer.fromJson<String>(json['reactionType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<String>(targetId),
      'reactionType': serializer.toJson<String>(reactionType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Reaction copyWith({
    String? id,
    String? userId,
    String? targetType,
    String? targetId,
    String? reactionType,
    DateTime? createdAt,
  }) => Reaction(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    targetType: targetType ?? this.targetType,
    targetId: targetId ?? this.targetId,
    reactionType: reactionType ?? this.reactionType,
    createdAt: createdAt ?? this.createdAt,
  );
  Reaction copyWithCompanion(ReactionsCompanion data) {
    return Reaction(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      reactionType: data.reactionType.present
          ? data.reactionType.value
          : this.reactionType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Reaction(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('reactionType: $reactionType, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, targetType, targetId, reactionType, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Reaction &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.reactionType == this.reactionType &&
          other.createdAt == this.createdAt);
}

class ReactionsCompanion extends UpdateCompanion<Reaction> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> targetType;
  final Value<String> targetId;
  final Value<String> reactionType;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ReactionsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.reactionType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReactionsCompanion.insert({
    required String id,
    required String userId,
    required String targetType,
    required String targetId,
    required String reactionType,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       targetType = Value(targetType),
       targetId = Value(targetId),
       reactionType = Value(reactionType),
       createdAt = Value(createdAt);
  static Insertable<Reaction> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? targetType,
    Expression<String>? targetId,
    Expression<String>? reactionType,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (reactionType != null) 'reaction_type': reactionType,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? targetType,
    Value<String>? targetId,
    Value<String>? reactionType,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ReactionsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      reactionType: reactionType ?? this.reactionType,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (reactionType.present) {
      map['reaction_type'] = Variable<String>(reactionType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReactionsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('reactionType: $reactionType, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BoardAclTable extends BoardAcl
    with TableInfo<$BoardAclTable, BoardAclData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardAclTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES boards (board_id)',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (user_id)',
    ),
  );
  static const VerificationMeta _canReadMeta = const VerificationMeta(
    'canRead',
  );
  @override
  late final GeneratedColumn<bool> canRead = GeneratedColumn<bool>(
    'can_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_read" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _canWriteMeta = const VerificationMeta(
    'canWrite',
  );
  @override
  late final GeneratedColumn<bool> canWrite = GeneratedColumn<bool>(
    'can_write',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("can_write" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isAdminMeta = const VerificationMeta(
    'isAdmin',
  );
  @override
  late final GeneratedColumn<bool> isAdmin = GeneratedColumn<bool>(
    'is_admin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_admin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    boardId,
    userId,
    canRead,
    canWrite,
    isAdmin,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'board_acl';
  @override
  VerificationContext validateIntegrity(
    Insertable<BoardAclData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('can_read')) {
      context.handle(
        _canReadMeta,
        canRead.isAcceptableOrUnknown(data['can_read']!, _canReadMeta),
      );
    }
    if (data.containsKey('can_write')) {
      context.handle(
        _canWriteMeta,
        canWrite.isAcceptableOrUnknown(data['can_write']!, _canWriteMeta),
      );
    }
    if (data.containsKey('is_admin')) {
      context.handle(
        _isAdminMeta,
        isAdmin.isAcceptableOrUnknown(data['is_admin']!, _isAdminMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {boardId, userId};
  @override
  BoardAclData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoardAclData(
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}board_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      canRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_read'],
      )!,
      canWrite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}can_write'],
      )!,
      isAdmin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_admin'],
      )!,
    );
  }

  @override
  $BoardAclTable createAlias(String alias) {
    return $BoardAclTable(attachedDatabase, alias);
  }
}

class BoardAclData extends DataClass implements Insertable<BoardAclData> {
  final String boardId;
  final String userId;
  final bool canRead;
  final bool canWrite;
  final bool isAdmin;
  const BoardAclData({
    required this.boardId,
    required this.userId,
    required this.canRead,
    required this.canWrite,
    required this.isAdmin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['board_id'] = Variable<String>(boardId);
    map['user_id'] = Variable<String>(userId);
    map['can_read'] = Variable<bool>(canRead);
    map['can_write'] = Variable<bool>(canWrite);
    map['is_admin'] = Variable<bool>(isAdmin);
    return map;
  }

  BoardAclCompanion toCompanion(bool nullToAbsent) {
    return BoardAclCompanion(
      boardId: Value(boardId),
      userId: Value(userId),
      canRead: Value(canRead),
      canWrite: Value(canWrite),
      isAdmin: Value(isAdmin),
    );
  }

  factory BoardAclData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoardAclData(
      boardId: serializer.fromJson<String>(json['boardId']),
      userId: serializer.fromJson<String>(json['userId']),
      canRead: serializer.fromJson<bool>(json['canRead']),
      canWrite: serializer.fromJson<bool>(json['canWrite']),
      isAdmin: serializer.fromJson<bool>(json['isAdmin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'boardId': serializer.toJson<String>(boardId),
      'userId': serializer.toJson<String>(userId),
      'canRead': serializer.toJson<bool>(canRead),
      'canWrite': serializer.toJson<bool>(canWrite),
      'isAdmin': serializer.toJson<bool>(isAdmin),
    };
  }

  BoardAclData copyWith({
    String? boardId,
    String? userId,
    bool? canRead,
    bool? canWrite,
    bool? isAdmin,
  }) => BoardAclData(
    boardId: boardId ?? this.boardId,
    userId: userId ?? this.userId,
    canRead: canRead ?? this.canRead,
    canWrite: canWrite ?? this.canWrite,
    isAdmin: isAdmin ?? this.isAdmin,
  );
  BoardAclData copyWithCompanion(BoardAclCompanion data) {
    return BoardAclData(
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      userId: data.userId.present ? data.userId.value : this.userId,
      canRead: data.canRead.present ? data.canRead.value : this.canRead,
      canWrite: data.canWrite.present ? data.canWrite.value : this.canWrite,
      isAdmin: data.isAdmin.present ? data.isAdmin.value : this.isAdmin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoardAclData(')
          ..write('boardId: $boardId, ')
          ..write('userId: $userId, ')
          ..write('canRead: $canRead, ')
          ..write('canWrite: $canWrite, ')
          ..write('isAdmin: $isAdmin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(boardId, userId, canRead, canWrite, isAdmin);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardAclData &&
          other.boardId == this.boardId &&
          other.userId == this.userId &&
          other.canRead == this.canRead &&
          other.canWrite == this.canWrite &&
          other.isAdmin == this.isAdmin);
}

class BoardAclCompanion extends UpdateCompanion<BoardAclData> {
  final Value<String> boardId;
  final Value<String> userId;
  final Value<bool> canRead;
  final Value<bool> canWrite;
  final Value<bool> isAdmin;
  final Value<int> rowid;
  const BoardAclCompanion({
    this.boardId = const Value.absent(),
    this.userId = const Value.absent(),
    this.canRead = const Value.absent(),
    this.canWrite = const Value.absent(),
    this.isAdmin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardAclCompanion.insert({
    required String boardId,
    required String userId,
    this.canRead = const Value.absent(),
    this.canWrite = const Value.absent(),
    this.isAdmin = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : boardId = Value(boardId),
       userId = Value(userId);
  static Insertable<BoardAclData> custom({
    Expression<String>? boardId,
    Expression<String>? userId,
    Expression<bool>? canRead,
    Expression<bool>? canWrite,
    Expression<bool>? isAdmin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (boardId != null) 'board_id': boardId,
      if (userId != null) 'user_id': userId,
      if (canRead != null) 'can_read': canRead,
      if (canWrite != null) 'can_write': canWrite,
      if (isAdmin != null) 'is_admin': isAdmin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardAclCompanion copyWith({
    Value<String>? boardId,
    Value<String>? userId,
    Value<bool>? canRead,
    Value<bool>? canWrite,
    Value<bool>? isAdmin,
    Value<int>? rowid,
  }) {
    return BoardAclCompanion(
      boardId: boardId ?? this.boardId,
      userId: userId ?? this.userId,
      canRead: canRead ?? this.canRead,
      canWrite: canWrite ?? this.canWrite,
      isAdmin: isAdmin ?? this.isAdmin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (canRead.present) {
      map['can_read'] = Variable<bool>(canRead.value);
    }
    if (canWrite.present) {
      map['can_write'] = Variable<bool>(canWrite.value);
    }
    if (isAdmin.present) {
      map['is_admin'] = Variable<bool>(isAdmin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardAclCompanion(')
          ..write('boardId: $boardId, ')
          ..write('userId: $userId, ')
          ..write('canRead: $canRead, ')
          ..write('canWrite: $canWrite, ')
          ..write('isAdmin: $isAdmin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityLogTable extends ActivityLog
    with TableInfo<$ActivityLogTable, ActivityLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _logIdMeta = const VerificationMeta('logId');
  @override
  late final GeneratedColumn<int> logId = GeneratedColumn<int>(
    'log_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _activityIdMeta = const VerificationMeta(
    'activityId',
  );
  @override
  late final GeneratedColumn<String> activityId = GeneratedColumn<String>(
    'activity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _originNodeIdMeta = const VerificationMeta(
    'originNodeId',
  );
  @override
  late final GeneratedColumn<String> originNodeId = GeneratedColumn<String>(
    'origin_node_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
    'board_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _insertedAtMeta = const VerificationMeta(
    'insertedAt',
  );
  @override
  late final GeneratedColumn<DateTime> insertedAt = GeneratedColumn<DateTime>(
    'inserted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    logId,
    activityId,
    originNodeId,
    type,
    entityType,
    entityId,
    boardId,
    threadId,
    authorId,
    createdAt,
    payload,
    insertedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivityLogData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('log_id')) {
      context.handle(
        _logIdMeta,
        logId.isAcceptableOrUnknown(data['log_id']!, _logIdMeta),
      );
    }
    if (data.containsKey('activity_id')) {
      context.handle(
        _activityIdMeta,
        activityId.isAcceptableOrUnknown(data['activity_id']!, _activityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_activityIdMeta);
    }
    if (data.containsKey('origin_node_id')) {
      context.handle(
        _originNodeIdMeta,
        originNodeId.isAcceptableOrUnknown(
          data['origin_node_id']!,
          _originNodeIdMeta,
        ),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('inserted_at')) {
      context.handle(
        _insertedAtMeta,
        insertedAt.isAcceptableOrUnknown(data['inserted_at']!, _insertedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {logId};
  @override
  ActivityLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityLogData(
      logId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}log_id'],
      )!,
      activityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_id'],
      )!,
      originNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_node_id'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}board_id'],
      ),
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      ),
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      insertedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}inserted_at'],
      )!,
    );
  }

  @override
  $ActivityLogTable createAlias(String alias) {
    return $ActivityLogTable(attachedDatabase, alias);
  }
}

class ActivityLogData extends DataClass implements Insertable<ActivityLogData> {
  final int logId;
  final String activityId;
  final String? originNodeId;
  final String type;
  final String entityType;
  final String entityId;
  final String? boardId;
  final String? threadId;
  final String authorId;
  final DateTime createdAt;
  final String payload;
  final DateTime insertedAt;
  const ActivityLogData({
    required this.logId,
    required this.activityId,
    this.originNodeId,
    required this.type,
    required this.entityType,
    required this.entityId,
    this.boardId,
    this.threadId,
    required this.authorId,
    required this.createdAt,
    required this.payload,
    required this.insertedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['log_id'] = Variable<int>(logId);
    map['activity_id'] = Variable<String>(activityId);
    if (!nullToAbsent || originNodeId != null) {
      map['origin_node_id'] = Variable<String>(originNodeId);
    }
    map['type'] = Variable<String>(type);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    if (!nullToAbsent || boardId != null) {
      map['board_id'] = Variable<String>(boardId);
    }
    if (!nullToAbsent || threadId != null) {
      map['thread_id'] = Variable<String>(threadId);
    }
    map['author_id'] = Variable<String>(authorId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['payload'] = Variable<String>(payload);
    map['inserted_at'] = Variable<DateTime>(insertedAt);
    return map;
  }

  ActivityLogCompanion toCompanion(bool nullToAbsent) {
    return ActivityLogCompanion(
      logId: Value(logId),
      activityId: Value(activityId),
      originNodeId: originNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(originNodeId),
      type: Value(type),
      entityType: Value(entityType),
      entityId: Value(entityId),
      boardId: boardId == null && nullToAbsent
          ? const Value.absent()
          : Value(boardId),
      threadId: threadId == null && nullToAbsent
          ? const Value.absent()
          : Value(threadId),
      authorId: Value(authorId),
      createdAt: Value(createdAt),
      payload: Value(payload),
      insertedAt: Value(insertedAt),
    );
  }

  factory ActivityLogData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityLogData(
      logId: serializer.fromJson<int>(json['logId']),
      activityId: serializer.fromJson<String>(json['activityId']),
      originNodeId: serializer.fromJson<String?>(json['originNodeId']),
      type: serializer.fromJson<String>(json['type']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      boardId: serializer.fromJson<String?>(json['boardId']),
      threadId: serializer.fromJson<String?>(json['threadId']),
      authorId: serializer.fromJson<String>(json['authorId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      payload: serializer.fromJson<String>(json['payload']),
      insertedAt: serializer.fromJson<DateTime>(json['insertedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'logId': serializer.toJson<int>(logId),
      'activityId': serializer.toJson<String>(activityId),
      'originNodeId': serializer.toJson<String?>(originNodeId),
      'type': serializer.toJson<String>(type),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'boardId': serializer.toJson<String?>(boardId),
      'threadId': serializer.toJson<String?>(threadId),
      'authorId': serializer.toJson<String>(authorId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'payload': serializer.toJson<String>(payload),
      'insertedAt': serializer.toJson<DateTime>(insertedAt),
    };
  }

  ActivityLogData copyWith({
    int? logId,
    String? activityId,
    Value<String?> originNodeId = const Value.absent(),
    String? type,
    String? entityType,
    String? entityId,
    Value<String?> boardId = const Value.absent(),
    Value<String?> threadId = const Value.absent(),
    String? authorId,
    DateTime? createdAt,
    String? payload,
    DateTime? insertedAt,
  }) => ActivityLogData(
    logId: logId ?? this.logId,
    activityId: activityId ?? this.activityId,
    originNodeId: originNodeId.present ? originNodeId.value : this.originNodeId,
    type: type ?? this.type,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    boardId: boardId.present ? boardId.value : this.boardId,
    threadId: threadId.present ? threadId.value : this.threadId,
    authorId: authorId ?? this.authorId,
    createdAt: createdAt ?? this.createdAt,
    payload: payload ?? this.payload,
    insertedAt: insertedAt ?? this.insertedAt,
  );
  ActivityLogData copyWithCompanion(ActivityLogCompanion data) {
    return ActivityLogData(
      logId: data.logId.present ? data.logId.value : this.logId,
      activityId: data.activityId.present
          ? data.activityId.value
          : this.activityId,
      originNodeId: data.originNodeId.present
          ? data.originNodeId.value
          : this.originNodeId,
      type: data.type.present ? data.type.value : this.type,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      payload: data.payload.present ? data.payload.value : this.payload,
      insertedAt: data.insertedAt.present
          ? data.insertedAt.value
          : this.insertedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLogData(')
          ..write('logId: $logId, ')
          ..write('activityId: $activityId, ')
          ..write('originNodeId: $originNodeId, ')
          ..write('type: $type, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('boardId: $boardId, ')
          ..write('threadId: $threadId, ')
          ..write('authorId: $authorId, ')
          ..write('createdAt: $createdAt, ')
          ..write('payload: $payload, ')
          ..write('insertedAt: $insertedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    logId,
    activityId,
    originNodeId,
    type,
    entityType,
    entityId,
    boardId,
    threadId,
    authorId,
    createdAt,
    payload,
    insertedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityLogData &&
          other.logId == this.logId &&
          other.activityId == this.activityId &&
          other.originNodeId == this.originNodeId &&
          other.type == this.type &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.boardId == this.boardId &&
          other.threadId == this.threadId &&
          other.authorId == this.authorId &&
          other.createdAt == this.createdAt &&
          other.payload == this.payload &&
          other.insertedAt == this.insertedAt);
}

class ActivityLogCompanion extends UpdateCompanion<ActivityLogData> {
  final Value<int> logId;
  final Value<String> activityId;
  final Value<String?> originNodeId;
  final Value<String> type;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String?> boardId;
  final Value<String?> threadId;
  final Value<String> authorId;
  final Value<DateTime> createdAt;
  final Value<String> payload;
  final Value<DateTime> insertedAt;
  const ActivityLogCompanion({
    this.logId = const Value.absent(),
    this.activityId = const Value.absent(),
    this.originNodeId = const Value.absent(),
    this.type = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.boardId = const Value.absent(),
    this.threadId = const Value.absent(),
    this.authorId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.insertedAt = const Value.absent(),
  });
  ActivityLogCompanion.insert({
    this.logId = const Value.absent(),
    required String activityId,
    this.originNodeId = const Value.absent(),
    required String type,
    required String entityType,
    required String entityId,
    this.boardId = const Value.absent(),
    this.threadId = const Value.absent(),
    required String authorId,
    required DateTime createdAt,
    required String payload,
    this.insertedAt = const Value.absent(),
  }) : activityId = Value(activityId),
       type = Value(type),
       entityType = Value(entityType),
       entityId = Value(entityId),
       authorId = Value(authorId),
       createdAt = Value(createdAt),
       payload = Value(payload);
  static Insertable<ActivityLogData> custom({
    Expression<int>? logId,
    Expression<String>? activityId,
    Expression<String>? originNodeId,
    Expression<String>? type,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? boardId,
    Expression<String>? threadId,
    Expression<String>? authorId,
    Expression<DateTime>? createdAt,
    Expression<String>? payload,
    Expression<DateTime>? insertedAt,
  }) {
    return RawValuesInsertable({
      if (logId != null) 'log_id': logId,
      if (activityId != null) 'activity_id': activityId,
      if (originNodeId != null) 'origin_node_id': originNodeId,
      if (type != null) 'type': type,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (boardId != null) 'board_id': boardId,
      if (threadId != null) 'thread_id': threadId,
      if (authorId != null) 'author_id': authorId,
      if (createdAt != null) 'created_at': createdAt,
      if (payload != null) 'payload': payload,
      if (insertedAt != null) 'inserted_at': insertedAt,
    });
  }

  ActivityLogCompanion copyWith({
    Value<int>? logId,
    Value<String>? activityId,
    Value<String?>? originNodeId,
    Value<String>? type,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String?>? boardId,
    Value<String?>? threadId,
    Value<String>? authorId,
    Value<DateTime>? createdAt,
    Value<String>? payload,
    Value<DateTime>? insertedAt,
  }) {
    return ActivityLogCompanion(
      logId: logId ?? this.logId,
      activityId: activityId ?? this.activityId,
      originNodeId: originNodeId ?? this.originNodeId,
      type: type ?? this.type,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      boardId: boardId ?? this.boardId,
      threadId: threadId ?? this.threadId,
      authorId: authorId ?? this.authorId,
      createdAt: createdAt ?? this.createdAt,
      payload: payload ?? this.payload,
      insertedAt: insertedAt ?? this.insertedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (logId.present) {
      map['log_id'] = Variable<int>(logId.value);
    }
    if (activityId.present) {
      map['activity_id'] = Variable<String>(activityId.value);
    }
    if (originNodeId.present) {
      map['origin_node_id'] = Variable<String>(originNodeId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (insertedAt.present) {
      map['inserted_at'] = Variable<DateTime>(insertedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityLogCompanion(')
          ..write('logId: $logId, ')
          ..write('activityId: $activityId, ')
          ..write('originNodeId: $originNodeId, ')
          ..write('type: $type, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('boardId: $boardId, ')
          ..write('threadId: $threadId, ')
          ..write('authorId: $authorId, ')
          ..write('createdAt: $createdAt, ')
          ..write('payload: $payload, ')
          ..write('insertedAt: $insertedAt')
          ..write(')'))
        .toString();
  }
}

class $RemoteNodesTable extends RemoteNodes
    with TableInfo<$RemoteNodesTable, RemoteNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accessTokenMeta = const VerificationMeta(
    'accessToken',
  );
  @override
  late final GeneratedColumn<String> accessToken = GeneratedColumn<String>(
    'access_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncCursorMeta = const VerificationMeta(
    'syncCursor',
  );
  @override
  late final GeneratedColumn<int> syncCursor = GeneratedColumn<int>(
    'sync_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    nodeId,
    name,
    url,
    accessToken,
    syncCursor,
    lastSyncAt,
    createdAt,
    updatedAt,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteNode> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('access_token')) {
      context.handle(
        _accessTokenMeta,
        accessToken.isAcceptableOrUnknown(
          data['access_token']!,
          _accessTokenMeta,
        ),
      );
    }
    if (data.containsKey('sync_cursor')) {
      context.handle(
        _syncCursorMeta,
        syncCursor.isAcceptableOrUnknown(data['sync_cursor']!, _syncCursorMeta),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {nodeId};
  @override
  RemoteNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteNode(
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      accessToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}access_token'],
      ),
      syncCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_cursor'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $RemoteNodesTable createAlias(String alias) {
    return $RemoteNodesTable(attachedDatabase, alias);
  }
}

class RemoteNode extends DataClass implements Insertable<RemoteNode> {
  final String nodeId;
  final String name;
  final String url;
  final String? accessToken;
  final int syncCursor;
  final DateTime? lastSyncAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  const RemoteNode({
    required this.nodeId,
    required this.name,
    required this.url,
    this.accessToken,
    required this.syncCursor,
    this.lastSyncAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['node_id'] = Variable<String>(nodeId);
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || accessToken != null) {
      map['access_token'] = Variable<String>(accessToken);
    }
    map['sync_cursor'] = Variable<int>(syncCursor);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  RemoteNodesCompanion toCompanion(bool nullToAbsent) {
    return RemoteNodesCompanion(
      nodeId: Value(nodeId),
      name: Value(name),
      url: Value(url),
      accessToken: accessToken == null && nullToAbsent
          ? const Value.absent()
          : Value(accessToken),
      syncCursor: Value(syncCursor),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isActive: Value(isActive),
    );
  }

  factory RemoteNode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteNode(
      nodeId: serializer.fromJson<String>(json['nodeId']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      accessToken: serializer.fromJson<String?>(json['accessToken']),
      syncCursor: serializer.fromJson<int>(json['syncCursor']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'nodeId': serializer.toJson<String>(nodeId),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'accessToken': serializer.toJson<String?>(accessToken),
      'syncCursor': serializer.toJson<int>(syncCursor),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  RemoteNode copyWith({
    String? nodeId,
    String? name,
    String? url,
    Value<String?> accessToken = const Value.absent(),
    int? syncCursor,
    Value<DateTime?> lastSyncAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) => RemoteNode(
    nodeId: nodeId ?? this.nodeId,
    name: name ?? this.name,
    url: url ?? this.url,
    accessToken: accessToken.present ? accessToken.value : this.accessToken,
    syncCursor: syncCursor ?? this.syncCursor,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isActive: isActive ?? this.isActive,
  );
  RemoteNode copyWithCompanion(RemoteNodesCompanion data) {
    return RemoteNode(
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      accessToken: data.accessToken.present
          ? data.accessToken.value
          : this.accessToken,
      syncCursor: data.syncCursor.present
          ? data.syncCursor.value
          : this.syncCursor,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteNode(')
          ..write('nodeId: $nodeId, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('accessToken: $accessToken, ')
          ..write('syncCursor: $syncCursor, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    nodeId,
    name,
    url,
    accessToken,
    syncCursor,
    lastSyncAt,
    createdAt,
    updatedAt,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteNode &&
          other.nodeId == this.nodeId &&
          other.name == this.name &&
          other.url == this.url &&
          other.accessToken == this.accessToken &&
          other.syncCursor == this.syncCursor &&
          other.lastSyncAt == this.lastSyncAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isActive == this.isActive);
}

class RemoteNodesCompanion extends UpdateCompanion<RemoteNode> {
  final Value<String> nodeId;
  final Value<String> name;
  final Value<String> url;
  final Value<String?> accessToken;
  final Value<int> syncCursor;
  final Value<DateTime?> lastSyncAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isActive;
  final Value<int> rowid;
  const RemoteNodesCompanion({
    this.nodeId = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.accessToken = const Value.absent(),
    this.syncCursor = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteNodesCompanion.insert({
    required String nodeId,
    required String name,
    required String url,
    this.accessToken = const Value.absent(),
    this.syncCursor = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : nodeId = Value(nodeId),
       name = Value(name),
       url = Value(url);
  static Insertable<RemoteNode> custom({
    Expression<String>? nodeId,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? accessToken,
    Expression<int>? syncCursor,
    Expression<DateTime>? lastSyncAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (nodeId != null) 'node_id': nodeId,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (accessToken != null) 'access_token': accessToken,
      if (syncCursor != null) 'sync_cursor': syncCursor,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteNodesCompanion copyWith({
    Value<String>? nodeId,
    Value<String>? name,
    Value<String>? url,
    Value<String?>? accessToken,
    Value<int>? syncCursor,
    Value<DateTime?>? lastSyncAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return RemoteNodesCompanion(
      nodeId: nodeId ?? this.nodeId,
      name: name ?? this.name,
      url: url ?? this.url,
      accessToken: accessToken ?? this.accessToken,
      syncCursor: syncCursor ?? this.syncCursor,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (accessToken.present) {
      map['access_token'] = Variable<String>(accessToken.value);
    }
    if (syncCursor.present) {
      map['sync_cursor'] = Variable<int>(syncCursor.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteNodesCompanion(')
          ..write('nodeId: $nodeId, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('accessToken: $accessToken, ')
          ..write('syncCursor: $syncCursor, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BoardSyncConfigsTable extends BoardSyncConfigs
    with TableInfo<$BoardSyncConfigsTable, BoardSyncConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardSyncConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _configIdMeta = const VerificationMeta(
    'configId',
  );
  @override
  late final GeneratedColumn<String> configId = GeneratedColumn<String>(
    'config_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteNodeIdMeta = const VerificationMeta(
    'remoteNodeId',
  );
  @override
  late final GeneratedColumn<String> remoteNodeId = GeneratedColumn<String>(
    'remote_node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncEnabledMeta = const VerificationMeta(
    'syncEnabled',
  );
  @override
  late final GeneratedColumn<bool> syncEnabled = GeneratedColumn<bool>(
    'sync_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    configId,
    remoteNodeId,
    boardId,
    syncEnabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'board_sync_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<BoardSyncConfig> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('config_id')) {
      context.handle(
        _configIdMeta,
        configId.isAcceptableOrUnknown(data['config_id']!, _configIdMeta),
      );
    } else if (isInserting) {
      context.missing(_configIdMeta);
    }
    if (data.containsKey('remote_node_id')) {
      context.handle(
        _remoteNodeIdMeta,
        remoteNodeId.isAcceptableOrUnknown(
          data['remote_node_id']!,
          _remoteNodeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteNodeIdMeta);
    }
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('sync_enabled')) {
      context.handle(
        _syncEnabledMeta,
        syncEnabled.isAcceptableOrUnknown(
          data['sync_enabled']!,
          _syncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {configId};
  @override
  BoardSyncConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoardSyncConfig(
      configId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_id'],
      )!,
      remoteNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_node_id'],
      )!,
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}board_id'],
      )!,
      syncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BoardSyncConfigsTable createAlias(String alias) {
    return $BoardSyncConfigsTable(attachedDatabase, alias);
  }
}

class BoardSyncConfig extends DataClass implements Insertable<BoardSyncConfig> {
  final String configId;
  final String remoteNodeId;
  final String boardId;
  final bool syncEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const BoardSyncConfig({
    required this.configId,
    required this.remoteNodeId,
    required this.boardId,
    required this.syncEnabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['config_id'] = Variable<String>(configId);
    map['remote_node_id'] = Variable<String>(remoteNodeId);
    map['board_id'] = Variable<String>(boardId);
    map['sync_enabled'] = Variable<bool>(syncEnabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BoardSyncConfigsCompanion toCompanion(bool nullToAbsent) {
    return BoardSyncConfigsCompanion(
      configId: Value(configId),
      remoteNodeId: Value(remoteNodeId),
      boardId: Value(boardId),
      syncEnabled: Value(syncEnabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BoardSyncConfig.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoardSyncConfig(
      configId: serializer.fromJson<String>(json['configId']),
      remoteNodeId: serializer.fromJson<String>(json['remoteNodeId']),
      boardId: serializer.fromJson<String>(json['boardId']),
      syncEnabled: serializer.fromJson<bool>(json['syncEnabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'configId': serializer.toJson<String>(configId),
      'remoteNodeId': serializer.toJson<String>(remoteNodeId),
      'boardId': serializer.toJson<String>(boardId),
      'syncEnabled': serializer.toJson<bool>(syncEnabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BoardSyncConfig copyWith({
    String? configId,
    String? remoteNodeId,
    String? boardId,
    bool? syncEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BoardSyncConfig(
    configId: configId ?? this.configId,
    remoteNodeId: remoteNodeId ?? this.remoteNodeId,
    boardId: boardId ?? this.boardId,
    syncEnabled: syncEnabled ?? this.syncEnabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BoardSyncConfig copyWithCompanion(BoardSyncConfigsCompanion data) {
    return BoardSyncConfig(
      configId: data.configId.present ? data.configId.value : this.configId,
      remoteNodeId: data.remoteNodeId.present
          ? data.remoteNodeId.value
          : this.remoteNodeId,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      syncEnabled: data.syncEnabled.present
          ? data.syncEnabled.value
          : this.syncEnabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoardSyncConfig(')
          ..write('configId: $configId, ')
          ..write('remoteNodeId: $remoteNodeId, ')
          ..write('boardId: $boardId, ')
          ..write('syncEnabled: $syncEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    configId,
    remoteNodeId,
    boardId,
    syncEnabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardSyncConfig &&
          other.configId == this.configId &&
          other.remoteNodeId == this.remoteNodeId &&
          other.boardId == this.boardId &&
          other.syncEnabled == this.syncEnabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BoardSyncConfigsCompanion extends UpdateCompanion<BoardSyncConfig> {
  final Value<String> configId;
  final Value<String> remoteNodeId;
  final Value<String> boardId;
  final Value<bool> syncEnabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BoardSyncConfigsCompanion({
    this.configId = const Value.absent(),
    this.remoteNodeId = const Value.absent(),
    this.boardId = const Value.absent(),
    this.syncEnabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardSyncConfigsCompanion.insert({
    required String configId,
    required String remoteNodeId,
    required String boardId,
    this.syncEnabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : configId = Value(configId),
       remoteNodeId = Value(remoteNodeId),
       boardId = Value(boardId);
  static Insertable<BoardSyncConfig> custom({
    Expression<String>? configId,
    Expression<String>? remoteNodeId,
    Expression<String>? boardId,
    Expression<bool>? syncEnabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (configId != null) 'config_id': configId,
      if (remoteNodeId != null) 'remote_node_id': remoteNodeId,
      if (boardId != null) 'board_id': boardId,
      if (syncEnabled != null) 'sync_enabled': syncEnabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardSyncConfigsCompanion copyWith({
    Value<String>? configId,
    Value<String>? remoteNodeId,
    Value<String>? boardId,
    Value<bool>? syncEnabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BoardSyncConfigsCompanion(
      configId: configId ?? this.configId,
      remoteNodeId: remoteNodeId ?? this.remoteNodeId,
      boardId: boardId ?? this.boardId,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (configId.present) {
      map['config_id'] = Variable<String>(configId.value);
    }
    if (remoteNodeId.present) {
      map['remote_node_id'] = Variable<String>(remoteNodeId.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (syncEnabled.present) {
      map['sync_enabled'] = Variable<bool>(syncEnabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardSyncConfigsCompanion(')
          ..write('configId: $configId, ')
          ..write('remoteNodeId: $remoteNodeId, ')
          ..write('boardId: $boardId, ')
          ..write('syncEnabled: $syncEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BoardsTable boards = $BoardsTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ThreadsTable threads = $ThreadsTable(this);
  late final $PostsTable posts = $PostsTable(this);
  late final $ReactionsTable reactions = $ReactionsTable(this);
  late final $BoardAclTable boardAcl = $BoardAclTable(this);
  late final $ActivityLogTable activityLog = $ActivityLogTable(this);
  late final $RemoteNodesTable remoteNodes = $RemoteNodesTable(this);
  late final $BoardSyncConfigsTable boardSyncConfigs = $BoardSyncConfigsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    boards,
    users,
    threads,
    posts,
    reactions,
    boardAcl,
    activityLog,
    remoteNodes,
    boardSyncConfigs,
  ];
}

typedef $$BoardsTableCreateCompanionBuilder =
    BoardsCompanion Function({
      required String boardId,
      required String slug,
      required String title,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<int> rowid,
    });
typedef $$BoardsTableUpdateCompanionBuilder =
    BoardsCompanion Function({
      Value<String> boardId,
      Value<String> slug,
      Value<String> title,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<int> rowid,
    });

final class $$BoardsTableReferences
    extends BaseReferences<_$AppDatabase, $BoardsTable, Board> {
  $$BoardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ThreadsTable, List<Thread>> _threadsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.threads,
    aliasName: $_aliasNameGenerator(db.boards.boardId, db.threads.boardId),
  );

  $$ThreadsTableProcessedTableManager get threadsRefs {
    final manager = $$ThreadsTableTableManager($_db, $_db.threads).filter(
      (f) => f.boardId.boardId.sqlEquals($_itemColumn<String>('board_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_threadsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PostsTable, List<Post>> _postsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.posts,
    aliasName: $_aliasNameGenerator(db.boards.boardId, db.posts.boardId),
  );

  $$PostsTableProcessedTableManager get postsRefs {
    final manager = $$PostsTableTableManager($_db, $_db.posts).filter(
      (f) => f.boardId.boardId.sqlEquals($_itemColumn<String>('board_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_postsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BoardAclTable, List<BoardAclData>>
  _boardAclRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.boardAcl,
    aliasName: $_aliasNameGenerator(db.boards.boardId, db.boardAcl.boardId),
  );

  $$BoardAclTableProcessedTableManager get boardAclRefs {
    final manager = $$BoardAclTableTableManager($_db, $_db.boardAcl).filter(
      (f) => f.boardId.boardId.sqlEquals($_itemColumn<String>('board_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_boardAclRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BoardsTableFilterComposer
    extends Composer<_$AppDatabase, $BoardsTable> {
  $$BoardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get boardId => $composableBuilder(
    column: $table.boardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> threadsRefs(
    Expression<bool> Function($$ThreadsTableFilterComposer f) f,
  ) {
    final $$ThreadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableFilterComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> postsRefs(
    Expression<bool> Function($$PostsTableFilterComposer f) f,
  ) {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> boardAclRefs(
    Expression<bool> Function($$BoardAclTableFilterComposer f) f,
  ) {
    final $$BoardAclTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boardAcl,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardAclTableFilterComposer(
            $db: $db,
            $table: $db.boardAcl,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BoardsTableOrderingComposer
    extends Composer<_$AppDatabase, $BoardsTable> {
  $$BoardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get boardId => $composableBuilder(
    column: $table.boardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BoardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BoardsTable> {
  $$BoardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  Expression<T> threadsRefs<T extends Object>(
    Expression<T> Function($$ThreadsTableAnnotationComposer a) f,
  ) {
    final $$ThreadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableAnnotationComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> postsRefs<T extends Object>(
    Expression<T> Function($$PostsTableAnnotationComposer a) f,
  ) {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> boardAclRefs<T extends Object>(
    Expression<T> Function($$BoardAclTableAnnotationComposer a) f,
  ) {
    final $$BoardAclTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boardAcl,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardAclTableAnnotationComposer(
            $db: $db,
            $table: $db.boardAcl,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BoardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BoardsTable,
          Board,
          $$BoardsTableFilterComposer,
          $$BoardsTableOrderingComposer,
          $$BoardsTableAnnotationComposer,
          $$BoardsTableCreateCompanionBuilder,
          $$BoardsTableUpdateCompanionBuilder,
          (Board, $$BoardsTableReferences),
          Board,
          PrefetchHooks Function({
            bool threadsRefs,
            bool postsRefs,
            bool boardAclRefs,
          })
        > {
  $$BoardsTableTableManager(_$AppDatabase db, $BoardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> boardId = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardsCompanion(
                boardId: boardId,
                slug: slug,
                title: title,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String boardId,
                required String slug,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardsCompanion.insert(
                boardId: boardId,
                slug: slug,
                title: title,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BoardsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({threadsRefs = false, postsRefs = false, boardAclRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (threadsRefs) db.threads,
                    if (postsRefs) db.posts,
                    if (boardAclRefs) db.boardAcl,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (threadsRefs)
                        await $_getPrefetchedData<Board, $BoardsTable, Thread>(
                          currentTable: table,
                          referencedTable: $$BoardsTableReferences
                              ._threadsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BoardsTableReferences(
                                db,
                                table,
                                p0,
                              ).threadsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.boardId == item.boardId,
                              ),
                          typedResults: items,
                        ),
                      if (postsRefs)
                        await $_getPrefetchedData<Board, $BoardsTable, Post>(
                          currentTable: table,
                          referencedTable: $$BoardsTableReferences
                              ._postsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BoardsTableReferences(db, table, p0).postsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.boardId == item.boardId,
                              ),
                          typedResults: items,
                        ),
                      if (boardAclRefs)
                        await $_getPrefetchedData<
                          Board,
                          $BoardsTable,
                          BoardAclData
                        >(
                          currentTable: table,
                          referencedTable: $$BoardsTableReferences
                              ._boardAclRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BoardsTableReferences(
                                db,
                                table,
                                p0,
                              ).boardAclRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.boardId == item.boardId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BoardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BoardsTable,
      Board,
      $$BoardsTableFilterComposer,
      $$BoardsTableOrderingComposer,
      $$BoardsTableAnnotationComposer,
      $$BoardsTableCreateCompanionBuilder,
      $$BoardsTableUpdateCompanionBuilder,
      (Board, $$BoardsTableReferences),
      Board,
      PrefetchHooks Function({
        bool threadsRefs,
        bool postsRefs,
        bool boardAclRefs,
      })
    >;
typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      required String userId,
      required String username,
      required String passwordHash,
      Value<String?> displayName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> userId,
      Value<String> username,
      Value<String> passwordHash,
      Value<String?> displayName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$UsersTableReferences
    extends BaseReferences<_$AppDatabase, $UsersTable, User> {
  $$UsersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ThreadsTable, List<Thread>> _threadsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.threads,
    aliasName: $_aliasNameGenerator(db.users.userId, db.threads.authorId),
  );

  $$ThreadsTableProcessedTableManager get threadsRefs {
    final manager = $$ThreadsTableTableManager($_db, $_db.threads).filter(
      (f) => f.authorId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_threadsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PostsTable, List<Post>> _postsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.posts,
    aliasName: $_aliasNameGenerator(db.users.userId, db.posts.authorId),
  );

  $$PostsTableProcessedTableManager get postsRefs {
    final manager = $$PostsTableTableManager($_db, $_db.posts).filter(
      (f) => f.authorId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_postsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReactionsTable, List<Reaction>>
  _reactionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reactions,
    aliasName: $_aliasNameGenerator(db.users.userId, db.reactions.userId),
  );

  $$ReactionsTableProcessedTableManager get reactionsRefs {
    final manager = $$ReactionsTableTableManager($_db, $_db.reactions).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_reactionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BoardAclTable, List<BoardAclData>>
  _boardAclRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.boardAcl,
    aliasName: $_aliasNameGenerator(db.users.userId, db.boardAcl.userId),
  );

  $$BoardAclTableProcessedTableManager get boardAclRefs {
    final manager = $$BoardAclTableTableManager($_db, $_db.boardAcl).filter(
      (f) => f.userId.userId.sqlEquals($_itemColumn<String>('user_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_boardAclRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> threadsRefs(
    Expression<bool> Function($$ThreadsTableFilterComposer f) f,
  ) {
    final $$ThreadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.authorId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableFilterComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> postsRefs(
    Expression<bool> Function($$PostsTableFilterComposer f) f,
  ) {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.authorId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reactionsRefs(
    Expression<bool> Function($$ReactionsTableFilterComposer f) f,
  ) {
    final $$ReactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.reactions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReactionsTableFilterComposer(
            $db: $db,
            $table: $db.reactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> boardAclRefs(
    Expression<bool> Function($$BoardAclTableFilterComposer f) f,
  ) {
    final $$BoardAclTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.boardAcl,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardAclTableFilterComposer(
            $db: $db,
            $table: $db.boardAcl,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> threadsRefs<T extends Object>(
    Expression<T> Function($$ThreadsTableAnnotationComposer a) f,
  ) {
    final $$ThreadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.authorId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableAnnotationComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> postsRefs<T extends Object>(
    Expression<T> Function($$PostsTableAnnotationComposer a) f,
  ) {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.authorId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reactionsRefs<T extends Object>(
    Expression<T> Function($$ReactionsTableAnnotationComposer a) f,
  ) {
    final $$ReactionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.reactions,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReactionsTableAnnotationComposer(
            $db: $db,
            $table: $db.reactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> boardAclRefs<T extends Object>(
    Expression<T> Function($$BoardAclTableAnnotationComposer a) f,
  ) {
    final $$BoardAclTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.boardAcl,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardAclTableAnnotationComposer(
            $db: $db,
            $table: $db.boardAcl,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, $$UsersTableReferences),
          User,
          PrefetchHooks Function({
            bool threadsRefs,
            bool postsRefs,
            bool reactionsRefs,
            bool boardAclRefs,
          })
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> passwordHash = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                userId: userId,
                username: username,
                passwordHash: passwordHash,
                displayName: displayName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String username,
                required String passwordHash,
                Value<String?> displayName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                userId: userId,
                username: username,
                passwordHash: passwordHash,
                displayName: displayName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UsersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                threadsRefs = false,
                postsRefs = false,
                reactionsRefs = false,
                boardAclRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (threadsRefs) db.threads,
                    if (postsRefs) db.posts,
                    if (reactionsRefs) db.reactions,
                    if (boardAclRefs) db.boardAcl,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (threadsRefs)
                        await $_getPrefetchedData<User, $UsersTable, Thread>(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._threadsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(db, table, p0).threadsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.authorId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (postsRefs)
                        await $_getPrefetchedData<User, $UsersTable, Post>(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._postsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(db, table, p0).postsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.authorId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (reactionsRefs)
                        await $_getPrefetchedData<User, $UsersTable, Reaction>(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._reactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).reactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                      if (boardAclRefs)
                        await $_getPrefetchedData<
                          User,
                          $UsersTable,
                          BoardAclData
                        >(
                          currentTable: table,
                          referencedTable: $$UsersTableReferences
                              ._boardAclRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UsersTableReferences(
                                db,
                                table,
                                p0,
                              ).boardAclRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.userId == item.userId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, $$UsersTableReferences),
      User,
      PrefetchHooks Function({
        bool threadsRefs,
        bool postsRefs,
        bool reactionsRefs,
        bool boardAclRefs,
      })
    >;
typedef $$ThreadsTableCreateCompanionBuilder =
    ThreadsCompanion Function({
      required String threadId,
      required String boardId,
      required String title,
      required String authorId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<bool> isDeleted,
      Value<int> rowid,
    });
typedef $$ThreadsTableUpdateCompanionBuilder =
    ThreadsCompanion Function({
      Value<String> threadId,
      Value<String> boardId,
      Value<String> title,
      Value<String> authorId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isDeleted,
      Value<int> rowid,
    });

final class $$ThreadsTableReferences
    extends BaseReferences<_$AppDatabase, $ThreadsTable, Thread> {
  $$ThreadsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BoardsTable _boardIdTable(_$AppDatabase db) => db.boards.createAlias(
    $_aliasNameGenerator(db.threads.boardId, db.boards.boardId),
  );

  $$BoardsTableProcessedTableManager get boardId {
    final $_column = $_itemColumn<String>('board_id')!;

    final manager = $$BoardsTableTableManager(
      $_db,
      $_db.boards,
    ).filter((f) => f.boardId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_boardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _authorIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.threads.authorId, db.users.userId),
  );

  $$UsersTableProcessedTableManager get authorId {
    final $_column = $_itemColumn<String>('author_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_authorIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PostsTable, List<Post>> _postsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.posts,
    aliasName: $_aliasNameGenerator(db.threads.threadId, db.posts.threadId),
  );

  $$PostsTableProcessedTableManager get postsRefs {
    final manager = $$PostsTableTableManager($_db, $_db.posts).filter(
      (f) => f.threadId.threadId.sqlEquals($_itemColumn<String>('thread_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_postsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ThreadsTableFilterComposer
    extends Composer<_$AppDatabase, $ThreadsTable> {
  $$ThreadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  $$BoardsTableFilterComposer get boardId {
    final $$BoardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableFilterComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get authorId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> postsRefs(
    Expression<bool> Function($$PostsTableFilterComposer f) f,
  ) {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ThreadsTableOrderingComposer
    extends Composer<_$AppDatabase, $ThreadsTable> {
  $$ThreadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  $$BoardsTableOrderingComposer get boardId {
    final $$BoardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableOrderingComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get authorId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ThreadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThreadsTable> {
  $$ThreadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  $$BoardsTableAnnotationComposer get boardId {
    final $$BoardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableAnnotationComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get authorId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> postsRefs<T extends Object>(
    Expression<T> Function($$PostsTableAnnotationComposer a) f,
  ) {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ThreadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ThreadsTable,
          Thread,
          $$ThreadsTableFilterComposer,
          $$ThreadsTableOrderingComposer,
          $$ThreadsTableAnnotationComposer,
          $$ThreadsTableCreateCompanionBuilder,
          $$ThreadsTableUpdateCompanionBuilder,
          (Thread, $$ThreadsTableReferences),
          Thread,
          PrefetchHooks Function({bool boardId, bool authorId, bool postsRefs})
        > {
  $$ThreadsTableTableManager(_$AppDatabase db, $ThreadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThreadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThreadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThreadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> threadId = const Value.absent(),
                Value<String> boardId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThreadsCompanion(
                threadId: threadId,
                boardId: boardId,
                title: title,
                authorId: authorId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String threadId,
                required String boardId,
                required String title,
                required String authorId,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThreadsCompanion.insert(
                threadId: threadId,
                boardId: boardId,
                title: title,
                authorId: authorId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ThreadsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({boardId = false, authorId = false, postsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (postsRefs) db.posts],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (boardId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.boardId,
                                    referencedTable: $$ThreadsTableReferences
                                        ._boardIdTable(db),
                                    referencedColumn: $$ThreadsTableReferences
                                        ._boardIdTable(db)
                                        .boardId,
                                  )
                                  as T;
                        }
                        if (authorId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.authorId,
                                    referencedTable: $$ThreadsTableReferences
                                        ._authorIdTable(db),
                                    referencedColumn: $$ThreadsTableReferences
                                        ._authorIdTable(db)
                                        .userId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (postsRefs)
                        await $_getPrefetchedData<Thread, $ThreadsTable, Post>(
                          currentTable: table,
                          referencedTable: $$ThreadsTableReferences
                              ._postsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ThreadsTableReferences(db, table, p0).postsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.threadId == item.threadId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ThreadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ThreadsTable,
      Thread,
      $$ThreadsTableFilterComposer,
      $$ThreadsTableOrderingComposer,
      $$ThreadsTableAnnotationComposer,
      $$ThreadsTableCreateCompanionBuilder,
      $$ThreadsTableUpdateCompanionBuilder,
      (Thread, $$ThreadsTableReferences),
      Thread,
      PrefetchHooks Function({bool boardId, bool authorId, bool postsRefs})
    >;
typedef $$PostsTableCreateCompanionBuilder =
    PostsCompanion Function({
      required String postId,
      required String threadId,
      required String boardId,
      required String authorId,
      required String content,
      Value<String?> parentPostId,
      required DateTime createdAt,
      required DateTime updatedAt,
      required DateTime lastEditAt,
      Value<bool> isDeleted,
      Value<int> rowid,
    });
typedef $$PostsTableUpdateCompanionBuilder =
    PostsCompanion Function({
      Value<String> postId,
      Value<String> threadId,
      Value<String> boardId,
      Value<String> authorId,
      Value<String> content,
      Value<String?> parentPostId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime> lastEditAt,
      Value<bool> isDeleted,
      Value<int> rowid,
    });

final class $$PostsTableReferences
    extends BaseReferences<_$AppDatabase, $PostsTable, Post> {
  $$PostsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ThreadsTable _threadIdTable(_$AppDatabase db) =>
      db.threads.createAlias(
        $_aliasNameGenerator(db.posts.threadId, db.threads.threadId),
      );

  $$ThreadsTableProcessedTableManager get threadId {
    final $_column = $_itemColumn<String>('thread_id')!;

    final manager = $$ThreadsTableTableManager(
      $_db,
      $_db.threads,
    ).filter((f) => f.threadId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_threadIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BoardsTable _boardIdTable(_$AppDatabase db) => db.boards.createAlias(
    $_aliasNameGenerator(db.posts.boardId, db.boards.boardId),
  );

  $$BoardsTableProcessedTableManager get boardId {
    final $_column = $_itemColumn<String>('board_id')!;

    final manager = $$BoardsTableTableManager(
      $_db,
      $_db.boards,
    ).filter((f) => f.boardId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_boardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _authorIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.posts.authorId, db.users.userId),
  );

  $$UsersTableProcessedTableManager get authorId {
    final $_column = $_itemColumn<String>('author_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_authorIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PostsTable _parentPostIdTable(_$AppDatabase db) =>
      db.posts.createAlias(
        $_aliasNameGenerator(db.posts.parentPostId, db.posts.postId),
      );

  $$PostsTableProcessedTableManager? get parentPostId {
    final $_column = $_itemColumn<String>('parent_post_id');
    if ($_column == null) return null;
    final manager = $$PostsTableTableManager(
      $_db,
      $_db.posts,
    ).filter((f) => f.postId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentPostIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PostsTableFilterComposer extends Composer<_$AppDatabase, $PostsTable> {
  $$PostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get postId => $composableBuilder(
    column: $table.postId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastEditAt => $composableBuilder(
    column: $table.lastEditAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  $$ThreadsTableFilterComposer get threadId {
    final $$ThreadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableFilterComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BoardsTableFilterComposer get boardId {
    final $$BoardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableFilterComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get authorId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PostsTableFilterComposer get parentPostId {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentPostId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PostsTableOrderingComposer
    extends Composer<_$AppDatabase, $PostsTable> {
  $$PostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get postId => $composableBuilder(
    column: $table.postId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastEditAt => $composableBuilder(
    column: $table.lastEditAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  $$ThreadsTableOrderingComposer get threadId {
    final $$ThreadsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableOrderingComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BoardsTableOrderingComposer get boardId {
    final $$BoardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableOrderingComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get authorId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PostsTableOrderingComposer get parentPostId {
    final $$PostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentPostId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableOrderingComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PostsTable> {
  $$PostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get postId =>
      $composableBuilder(column: $table.postId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastEditAt => $composableBuilder(
    column: $table.lastEditAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  $$ThreadsTableAnnotationComposer get threadId {
    final $$ThreadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.threadId,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.threadId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ThreadsTableAnnotationComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BoardsTableAnnotationComposer get boardId {
    final $$BoardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableAnnotationComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get authorId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PostsTableAnnotationComposer get parentPostId {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentPostId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PostsTable,
          Post,
          $$PostsTableFilterComposer,
          $$PostsTableOrderingComposer,
          $$PostsTableAnnotationComposer,
          $$PostsTableCreateCompanionBuilder,
          $$PostsTableUpdateCompanionBuilder,
          (Post, $$PostsTableReferences),
          Post,
          PrefetchHooks Function({
            bool threadId,
            bool boardId,
            bool authorId,
            bool parentPostId,
          })
        > {
  $$PostsTableTableManager(_$AppDatabase db, $PostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> postId = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> boardId = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> parentPostId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime> lastEditAt = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PostsCompanion(
                postId: postId,
                threadId: threadId,
                boardId: boardId,
                authorId: authorId,
                content: content,
                parentPostId: parentPostId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastEditAt: lastEditAt,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String postId,
                required String threadId,
                required String boardId,
                required String authorId,
                required String content,
                Value<String?> parentPostId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                required DateTime lastEditAt,
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PostsCompanion.insert(
                postId: postId,
                threadId: threadId,
                boardId: boardId,
                authorId: authorId,
                content: content,
                parentPostId: parentPostId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastEditAt: lastEditAt,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PostsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                threadId = false,
                boardId = false,
                authorId = false,
                parentPostId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (threadId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.threadId,
                                    referencedTable: $$PostsTableReferences
                                        ._threadIdTable(db),
                                    referencedColumn: $$PostsTableReferences
                                        ._threadIdTable(db)
                                        .threadId,
                                  )
                                  as T;
                        }
                        if (boardId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.boardId,
                                    referencedTable: $$PostsTableReferences
                                        ._boardIdTable(db),
                                    referencedColumn: $$PostsTableReferences
                                        ._boardIdTable(db)
                                        .boardId,
                                  )
                                  as T;
                        }
                        if (authorId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.authorId,
                                    referencedTable: $$PostsTableReferences
                                        ._authorIdTable(db),
                                    referencedColumn: $$PostsTableReferences
                                        ._authorIdTable(db)
                                        .userId,
                                  )
                                  as T;
                        }
                        if (parentPostId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentPostId,
                                    referencedTable: $$PostsTableReferences
                                        ._parentPostIdTable(db),
                                    referencedColumn: $$PostsTableReferences
                                        ._parentPostIdTable(db)
                                        .postId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$PostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PostsTable,
      Post,
      $$PostsTableFilterComposer,
      $$PostsTableOrderingComposer,
      $$PostsTableAnnotationComposer,
      $$PostsTableCreateCompanionBuilder,
      $$PostsTableUpdateCompanionBuilder,
      (Post, $$PostsTableReferences),
      Post,
      PrefetchHooks Function({
        bool threadId,
        bool boardId,
        bool authorId,
        bool parentPostId,
      })
    >;
typedef $$ReactionsTableCreateCompanionBuilder =
    ReactionsCompanion Function({
      required String id,
      required String userId,
      required String targetType,
      required String targetId,
      required String reactionType,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ReactionsTableUpdateCompanionBuilder =
    ReactionsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> targetType,
      Value<String> targetId,
      Value<String> reactionType,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ReactionsTableReferences
    extends BaseReferences<_$AppDatabase, $ReactionsTable, Reaction> {
  $$ReactionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UsersTable _userIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.reactions.userId, db.users.userId),
  );

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReactionsTableFilterComposer
    extends Composer<_$AppDatabase, $ReactionsTable> {
  $$ReactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reactionType => $composableBuilder(
    column: $table.reactionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReactionsTable> {
  $$ReactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reactionType => $composableBuilder(
    column: $table.reactionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReactionsTable> {
  $$ReactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get reactionType => $composableBuilder(
    column: $table.reactionType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReactionsTable,
          Reaction,
          $$ReactionsTableFilterComposer,
          $$ReactionsTableOrderingComposer,
          $$ReactionsTableAnnotationComposer,
          $$ReactionsTableCreateCompanionBuilder,
          $$ReactionsTableUpdateCompanionBuilder,
          (Reaction, $$ReactionsTableReferences),
          Reaction,
          PrefetchHooks Function({bool userId})
        > {
  $$ReactionsTableTableManager(_$AppDatabase db, $ReactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> reactionType = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReactionsCompanion(
                id: id,
                userId: userId,
                targetType: targetType,
                targetId: targetId,
                reactionType: reactionType,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String targetType,
                required String targetId,
                required String reactionType,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ReactionsCompanion.insert(
                id: id,
                userId: userId,
                targetType: targetType,
                targetId: targetId,
                reactionType: reactionType,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$ReactionsTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$ReactionsTableReferences
                                    ._userIdTable(db)
                                    .userId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReactionsTable,
      Reaction,
      $$ReactionsTableFilterComposer,
      $$ReactionsTableOrderingComposer,
      $$ReactionsTableAnnotationComposer,
      $$ReactionsTableCreateCompanionBuilder,
      $$ReactionsTableUpdateCompanionBuilder,
      (Reaction, $$ReactionsTableReferences),
      Reaction,
      PrefetchHooks Function({bool userId})
    >;
typedef $$BoardAclTableCreateCompanionBuilder =
    BoardAclCompanion Function({
      required String boardId,
      required String userId,
      Value<bool> canRead,
      Value<bool> canWrite,
      Value<bool> isAdmin,
      Value<int> rowid,
    });
typedef $$BoardAclTableUpdateCompanionBuilder =
    BoardAclCompanion Function({
      Value<String> boardId,
      Value<String> userId,
      Value<bool> canRead,
      Value<bool> canWrite,
      Value<bool> isAdmin,
      Value<int> rowid,
    });

final class $$BoardAclTableReferences
    extends BaseReferences<_$AppDatabase, $BoardAclTable, BoardAclData> {
  $$BoardAclTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BoardsTable _boardIdTable(_$AppDatabase db) => db.boards.createAlias(
    $_aliasNameGenerator(db.boardAcl.boardId, db.boards.boardId),
  );

  $$BoardsTableProcessedTableManager get boardId {
    final $_column = $_itemColumn<String>('board_id')!;

    final manager = $$BoardsTableTableManager(
      $_db,
      $_db.boards,
    ).filter((f) => f.boardId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_boardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UsersTable _userIdTable(_$AppDatabase db) => db.users.createAlias(
    $_aliasNameGenerator(db.boardAcl.userId, db.users.userId),
  );

  $$UsersTableProcessedTableManager get userId {
    final $_column = $_itemColumn<String>('user_id')!;

    final manager = $$UsersTableTableManager(
      $_db,
      $_db.users,
    ).filter((f) => f.userId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_userIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BoardAclTableFilterComposer
    extends Composer<_$AppDatabase, $BoardAclTable> {
  $$BoardAclTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get canRead => $composableBuilder(
    column: $table.canRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get canWrite => $composableBuilder(
    column: $table.canWrite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAdmin => $composableBuilder(
    column: $table.isAdmin,
    builder: (column) => ColumnFilters(column),
  );

  $$BoardsTableFilterComposer get boardId {
    final $$BoardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableFilterComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableFilterComposer get userId {
    final $$UsersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableFilterComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BoardAclTableOrderingComposer
    extends Composer<_$AppDatabase, $BoardAclTable> {
  $$BoardAclTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get canRead => $composableBuilder(
    column: $table.canRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get canWrite => $composableBuilder(
    column: $table.canWrite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAdmin => $composableBuilder(
    column: $table.isAdmin,
    builder: (column) => ColumnOrderings(column),
  );

  $$BoardsTableOrderingComposer get boardId {
    final $$BoardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableOrderingComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableOrderingComposer get userId {
    final $$UsersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableOrderingComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BoardAclTableAnnotationComposer
    extends Composer<_$AppDatabase, $BoardAclTable> {
  $$BoardAclTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get canRead =>
      $composableBuilder(column: $table.canRead, builder: (column) => column);

  GeneratedColumn<bool> get canWrite =>
      $composableBuilder(column: $table.canWrite, builder: (column) => column);

  GeneratedColumn<bool> get isAdmin =>
      $composableBuilder(column: $table.isAdmin, builder: (column) => column);

  $$BoardsTableAnnotationComposer get boardId {
    final $$BoardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableAnnotationComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UsersTableAnnotationComposer get userId {
    final $$UsersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.userId,
      referencedTable: $db.users,
      getReferencedColumn: (t) => t.userId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UsersTableAnnotationComposer(
            $db: $db,
            $table: $db.users,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BoardAclTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BoardAclTable,
          BoardAclData,
          $$BoardAclTableFilterComposer,
          $$BoardAclTableOrderingComposer,
          $$BoardAclTableAnnotationComposer,
          $$BoardAclTableCreateCompanionBuilder,
          $$BoardAclTableUpdateCompanionBuilder,
          (BoardAclData, $$BoardAclTableReferences),
          BoardAclData,
          PrefetchHooks Function({bool boardId, bool userId})
        > {
  $$BoardAclTableTableManager(_$AppDatabase db, $BoardAclTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardAclTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardAclTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardAclTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> boardId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<bool> canRead = const Value.absent(),
                Value<bool> canWrite = const Value.absent(),
                Value<bool> isAdmin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardAclCompanion(
                boardId: boardId,
                userId: userId,
                canRead: canRead,
                canWrite: canWrite,
                isAdmin: isAdmin,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String boardId,
                required String userId,
                Value<bool> canRead = const Value.absent(),
                Value<bool> canWrite = const Value.absent(),
                Value<bool> isAdmin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardAclCompanion.insert(
                boardId: boardId,
                userId: userId,
                canRead: canRead,
                canWrite: canWrite,
                isAdmin: isAdmin,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BoardAclTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({boardId = false, userId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (boardId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.boardId,
                                referencedTable: $$BoardAclTableReferences
                                    ._boardIdTable(db),
                                referencedColumn: $$BoardAclTableReferences
                                    ._boardIdTable(db)
                                    .boardId,
                              )
                              as T;
                    }
                    if (userId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.userId,
                                referencedTable: $$BoardAclTableReferences
                                    ._userIdTable(db),
                                referencedColumn: $$BoardAclTableReferences
                                    ._userIdTable(db)
                                    .userId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BoardAclTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BoardAclTable,
      BoardAclData,
      $$BoardAclTableFilterComposer,
      $$BoardAclTableOrderingComposer,
      $$BoardAclTableAnnotationComposer,
      $$BoardAclTableCreateCompanionBuilder,
      $$BoardAclTableUpdateCompanionBuilder,
      (BoardAclData, $$BoardAclTableReferences),
      BoardAclData,
      PrefetchHooks Function({bool boardId, bool userId})
    >;
typedef $$ActivityLogTableCreateCompanionBuilder =
    ActivityLogCompanion Function({
      Value<int> logId,
      required String activityId,
      Value<String?> originNodeId,
      required String type,
      required String entityType,
      required String entityId,
      Value<String?> boardId,
      Value<String?> threadId,
      required String authorId,
      required DateTime createdAt,
      required String payload,
      Value<DateTime> insertedAt,
    });
typedef $$ActivityLogTableUpdateCompanionBuilder =
    ActivityLogCompanion Function({
      Value<int> logId,
      Value<String> activityId,
      Value<String?> originNodeId,
      Value<String> type,
      Value<String> entityType,
      Value<String> entityId,
      Value<String?> boardId,
      Value<String?> threadId,
      Value<String> authorId,
      Value<DateTime> createdAt,
      Value<String> payload,
      Value<DateTime> insertedAt,
    });

class $$ActivityLogTableFilterComposer
    extends Composer<_$AppDatabase, $ActivityLogTable> {
  $$ActivityLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get logId => $composableBuilder(
    column: $table.logId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityId => $composableBuilder(
    column: $table.activityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originNodeId => $composableBuilder(
    column: $table.originNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get boardId => $composableBuilder(
    column: $table.boardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get insertedAt => $composableBuilder(
    column: $table.insertedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActivityLogTableOrderingComposer
    extends Composer<_$AppDatabase, $ActivityLogTable> {
  $$ActivityLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get logId => $composableBuilder(
    column: $table.logId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityId => $composableBuilder(
    column: $table.activityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originNodeId => $composableBuilder(
    column: $table.originNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get boardId => $composableBuilder(
    column: $table.boardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get insertedAt => $composableBuilder(
    column: $table.insertedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActivityLogTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActivityLogTable> {
  $$ActivityLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get logId =>
      $composableBuilder(column: $table.logId, builder: (column) => column);

  GeneratedColumn<String> get activityId => $composableBuilder(
    column: $table.activityId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originNodeId => $composableBuilder(
    column: $table.originNodeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get insertedAt => $composableBuilder(
    column: $table.insertedAt,
    builder: (column) => column,
  );
}

class $$ActivityLogTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActivityLogTable,
          ActivityLogData,
          $$ActivityLogTableFilterComposer,
          $$ActivityLogTableOrderingComposer,
          $$ActivityLogTableAnnotationComposer,
          $$ActivityLogTableCreateCompanionBuilder,
          $$ActivityLogTableUpdateCompanionBuilder,
          (
            ActivityLogData,
            BaseReferences<_$AppDatabase, $ActivityLogTable, ActivityLogData>,
          ),
          ActivityLogData,
          PrefetchHooks Function()
        > {
  $$ActivityLogTableTableManager(_$AppDatabase db, $ActivityLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivityLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivityLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivityLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> logId = const Value.absent(),
                Value<String> activityId = const Value.absent(),
                Value<String?> originNodeId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String?> boardId = const Value.absent(),
                Value<String?> threadId = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> insertedAt = const Value.absent(),
              }) => ActivityLogCompanion(
                logId: logId,
                activityId: activityId,
                originNodeId: originNodeId,
                type: type,
                entityType: entityType,
                entityId: entityId,
                boardId: boardId,
                threadId: threadId,
                authorId: authorId,
                createdAt: createdAt,
                payload: payload,
                insertedAt: insertedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> logId = const Value.absent(),
                required String activityId,
                Value<String?> originNodeId = const Value.absent(),
                required String type,
                required String entityType,
                required String entityId,
                Value<String?> boardId = const Value.absent(),
                Value<String?> threadId = const Value.absent(),
                required String authorId,
                required DateTime createdAt,
                required String payload,
                Value<DateTime> insertedAt = const Value.absent(),
              }) => ActivityLogCompanion.insert(
                logId: logId,
                activityId: activityId,
                originNodeId: originNodeId,
                type: type,
                entityType: entityType,
                entityId: entityId,
                boardId: boardId,
                threadId: threadId,
                authorId: authorId,
                createdAt: createdAt,
                payload: payload,
                insertedAt: insertedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivityLogTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActivityLogTable,
      ActivityLogData,
      $$ActivityLogTableFilterComposer,
      $$ActivityLogTableOrderingComposer,
      $$ActivityLogTableAnnotationComposer,
      $$ActivityLogTableCreateCompanionBuilder,
      $$ActivityLogTableUpdateCompanionBuilder,
      (
        ActivityLogData,
        BaseReferences<_$AppDatabase, $ActivityLogTable, ActivityLogData>,
      ),
      ActivityLogData,
      PrefetchHooks Function()
    >;
typedef $$RemoteNodesTableCreateCompanionBuilder =
    RemoteNodesCompanion Function({
      required String nodeId,
      required String name,
      required String url,
      Value<String?> accessToken,
      Value<int> syncCursor,
      Value<DateTime?> lastSyncAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$RemoteNodesTableUpdateCompanionBuilder =
    RemoteNodesCompanion Function({
      Value<String> nodeId,
      Value<String> name,
      Value<String> url,
      Value<String?> accessToken,
      Value<int> syncCursor,
      Value<DateTime?> lastSyncAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isActive,
      Value<int> rowid,
    });

class $$RemoteNodesTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteNodesTable> {
  $$RemoteNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accessToken => $composableBuilder(
    column: $table.accessToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncCursor => $composableBuilder(
    column: $table.syncCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteNodesTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteNodesTable> {
  $$RemoteNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessToken => $composableBuilder(
    column: $table.accessToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncCursor => $composableBuilder(
    column: $table.syncCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteNodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteNodesTable> {
  $$RemoteNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get nodeId =>
      $composableBuilder(column: $table.nodeId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get accessToken => $composableBuilder(
    column: $table.accessToken,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncCursor => $composableBuilder(
    column: $table.syncCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$RemoteNodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteNodesTable,
          RemoteNode,
          $$RemoteNodesTableFilterComposer,
          $$RemoteNodesTableOrderingComposer,
          $$RemoteNodesTableAnnotationComposer,
          $$RemoteNodesTableCreateCompanionBuilder,
          $$RemoteNodesTableUpdateCompanionBuilder,
          (
            RemoteNode,
            BaseReferences<_$AppDatabase, $RemoteNodesTable, RemoteNode>,
          ),
          RemoteNode,
          PrefetchHooks Function()
        > {
  $$RemoteNodesTableTableManager(_$AppDatabase db, $RemoteNodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> nodeId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> accessToken = const Value.absent(),
                Value<int> syncCursor = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteNodesCompanion(
                nodeId: nodeId,
                name: name,
                url: url,
                accessToken: accessToken,
                syncCursor: syncCursor,
                lastSyncAt: lastSyncAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String nodeId,
                required String name,
                required String url,
                Value<String?> accessToken = const Value.absent(),
                Value<int> syncCursor = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteNodesCompanion.insert(
                nodeId: nodeId,
                name: name,
                url: url,
                accessToken: accessToken,
                syncCursor: syncCursor,
                lastSyncAt: lastSyncAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteNodesTable,
      RemoteNode,
      $$RemoteNodesTableFilterComposer,
      $$RemoteNodesTableOrderingComposer,
      $$RemoteNodesTableAnnotationComposer,
      $$RemoteNodesTableCreateCompanionBuilder,
      $$RemoteNodesTableUpdateCompanionBuilder,
      (
        RemoteNode,
        BaseReferences<_$AppDatabase, $RemoteNodesTable, RemoteNode>,
      ),
      RemoteNode,
      PrefetchHooks Function()
    >;
typedef $$BoardSyncConfigsTableCreateCompanionBuilder =
    BoardSyncConfigsCompanion Function({
      required String configId,
      required String remoteNodeId,
      required String boardId,
      Value<bool> syncEnabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$BoardSyncConfigsTableUpdateCompanionBuilder =
    BoardSyncConfigsCompanion Function({
      Value<String> configId,
      Value<String> remoteNodeId,
      Value<String> boardId,
      Value<bool> syncEnabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$BoardSyncConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $BoardSyncConfigsTable> {
  $$BoardSyncConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get configId => $composableBuilder(
    column: $table.configId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteNodeId => $composableBuilder(
    column: $table.remoteNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get boardId => $composableBuilder(
    column: $table.boardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get syncEnabled => $composableBuilder(
    column: $table.syncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BoardSyncConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $BoardSyncConfigsTable> {
  $$BoardSyncConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get configId => $composableBuilder(
    column: $table.configId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteNodeId => $composableBuilder(
    column: $table.remoteNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get boardId => $composableBuilder(
    column: $table.boardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get syncEnabled => $composableBuilder(
    column: $table.syncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BoardSyncConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BoardSyncConfigsTable> {
  $$BoardSyncConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get configId =>
      $composableBuilder(column: $table.configId, builder: (column) => column);

  GeneratedColumn<String> get remoteNodeId => $composableBuilder(
    column: $table.remoteNodeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<bool> get syncEnabled => $composableBuilder(
    column: $table.syncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BoardSyncConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BoardSyncConfigsTable,
          BoardSyncConfig,
          $$BoardSyncConfigsTableFilterComposer,
          $$BoardSyncConfigsTableOrderingComposer,
          $$BoardSyncConfigsTableAnnotationComposer,
          $$BoardSyncConfigsTableCreateCompanionBuilder,
          $$BoardSyncConfigsTableUpdateCompanionBuilder,
          (
            BoardSyncConfig,
            BaseReferences<
              _$AppDatabase,
              $BoardSyncConfigsTable,
              BoardSyncConfig
            >,
          ),
          BoardSyncConfig,
          PrefetchHooks Function()
        > {
  $$BoardSyncConfigsTableTableManager(
    _$AppDatabase db,
    $BoardSyncConfigsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardSyncConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardSyncConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardSyncConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> configId = const Value.absent(),
                Value<String> remoteNodeId = const Value.absent(),
                Value<String> boardId = const Value.absent(),
                Value<bool> syncEnabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardSyncConfigsCompanion(
                configId: configId,
                remoteNodeId: remoteNodeId,
                boardId: boardId,
                syncEnabled: syncEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String configId,
                required String remoteNodeId,
                required String boardId,
                Value<bool> syncEnabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BoardSyncConfigsCompanion.insert(
                configId: configId,
                remoteNodeId: remoteNodeId,
                boardId: boardId,
                syncEnabled: syncEnabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BoardSyncConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BoardSyncConfigsTable,
      BoardSyncConfig,
      $$BoardSyncConfigsTableFilterComposer,
      $$BoardSyncConfigsTableOrderingComposer,
      $$BoardSyncConfigsTableAnnotationComposer,
      $$BoardSyncConfigsTableCreateCompanionBuilder,
      $$BoardSyncConfigsTableUpdateCompanionBuilder,
      (
        BoardSyncConfig,
        BaseReferences<_$AppDatabase, $BoardSyncConfigsTable, BoardSyncConfig>,
      ),
      BoardSyncConfig,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BoardsTableTableManager get boards =>
      $$BoardsTableTableManager(_db, _db.boards);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$ThreadsTableTableManager get threads =>
      $$ThreadsTableTableManager(_db, _db.threads);
  $$PostsTableTableManager get posts =>
      $$PostsTableTableManager(_db, _db.posts);
  $$ReactionsTableTableManager get reactions =>
      $$ReactionsTableTableManager(_db, _db.reactions);
  $$BoardAclTableTableManager get boardAcl =>
      $$BoardAclTableTableManager(_db, _db.boardAcl);
  $$ActivityLogTableTableManager get activityLog =>
      $$ActivityLogTableTableManager(_db, _db.activityLog);
  $$RemoteNodesTableTableManager get remoteNodes =>
      $$RemoteNodesTableTableManager(_db, _db.remoteNodes);
  $$BoardSyncConfigsTableTableManager get boardSyncConfigs =>
      $$BoardSyncConfigsTableTableManager(_db, _db.boardSyncConfigs);
}
