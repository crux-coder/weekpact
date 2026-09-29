import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The IANA zone the person is actually standing in, for the crew they are
/// about to create.
///
/// A crew's week is cut at midnight in the crew's own zone — every week
/// snapshot joins `crews.timezone` against `pg_timezone_names` — so the zone
/// has to be a name Postgres knows, like `Europe/Sarajevo`. Dart cannot give
/// one: `DateTime.now().timeZoneName` is an abbreviation (`CEST`) on mobile
/// and an offset (`GMT+2`) on the web, and neither is in that table. Hence the
/// plugin, which asks the platform for the name it actually holds.
///
/// It was a build-time constant — `APP_TIMEZONE`, defaulting to `UTC` — shown
/// to the person creating the crew in a read-only box beside a globe. That box
/// could only ever say what the build said, so for everyone outside the zone
/// it was compiled with it was a wrong answer they were not allowed to
/// correct, and their crew's day ended at the wrong midnight.
///
/// Never throws, and never waits long. Every caller is on the path of a crew
/// being created, so this is a lookup standing between someone and the thing
/// they asked for: a crew made on UTC is a recoverable wrong answer, and a
/// CREATE CREW button that hangs on a platform channel is not. The SQL
/// coalesces a zone it cannot match to UTC anyway, so the fallback here is the
/// same one the database would have picked.
Future<String> deviceTimezone() async {
  final known = _zone;
  if (known != null) return known;
  try {
    final info = await FlutterTimezone.getLocalTimezone().timeout(_patience);
    final zone = info.identifier.trim();
    // The column is `char_length between 1 and 64`, and a zone the server
    // cannot match is coalesced to UTC there — so anything doubtful is better
    // sent as the fallback than as a name that will be thrown away.
    if (zone.isEmpty || zone.length > 64) return _fallback;
    return _zone = zone;
  } on MissingPluginException {
    // Nothing behind the channel: a widget test, or a platform the plugin was
    // not built into.
    return _fallback;
  } catch (_) {
    // A timeout, a channel error, or a platform that answered with nonsense.
    return _fallback;
  }
}

/// Forgets the cached zone. For tests, which need each case to start with the
/// device unread.
@visibleForTesting
void resetDeviceTimezone() => _zone = null;

/// The zone once the platform has given it. Only a real answer is kept: a
/// fallback is what this returned when it could not find out, not something it
/// learned, and a cold start that timed out should be asked again.
String? _zone;

/// How long a crew's creation will wait on the platform. A method channel
/// answers in well under a millisecond; this is the bound that stops a wedged
/// one from standing between someone and their crew.
const _patience = Duration(milliseconds: 400);

/// What a crew runs on when the device will not say where it is. The same zone
/// `pg_timezone_names` falls back to, so the app and the database agree.
const _fallback = 'UTC';
