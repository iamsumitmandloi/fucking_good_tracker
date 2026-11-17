import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Prefix for rows written by development checks. Ignored in every stat.
const devIdPrefix = 'dev-';

String newEventId() => _uuid.v4();

bool isDevId(String id) => id.startsWith(devIdPrefix);
