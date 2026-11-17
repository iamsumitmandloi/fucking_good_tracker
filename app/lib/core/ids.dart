import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Prefix for rows written by development checks. Ignored in every stat.
const devIdPrefix = 'dev-';

/// `--dart-define=DEV_IDS=true` builds an app whose every new id is a `dev-`
/// id, for live checks against the real sheet (stats ignore those rows).
const devIdBuild = bool.fromEnvironment('DEV_IDS');

String newEventId() => devIdBuild ? '$devIdPrefix${_uuid.v4()}' : _uuid.v4();

bool isDevId(String id) => id.startsWith(devIdPrefix);
