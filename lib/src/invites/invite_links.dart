import 'package:app_links/app_links.dart';

abstract interface class InviteLinkSource {
  Future<Uri?> getInitialLink();
  Stream<Uri> get links;
}

class AppLinksInviteLinkSource implements InviteLinkSource {
  AppLinksInviteLinkSource() : _appLinks = AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;
}

class NoopInviteLinkSource implements InviteLinkSource {
  const NoopInviteLinkSource();

  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  Stream<Uri> get links => const Stream.empty();
}

/// The letters and digits an invite code is made of. 0/O, 1/I and L are left
/// out so a code read aloud or copied off a screen cannot be mistyped.
const inviteCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const inviteCodeLength = 6;

/// One crew's way in: its code (or, for links shared before codes existed, a
/// 64-character token) and, when the link carried it, who sent it.
class InviteRef {
  const InviteRef(this.code, {this.from});

  /// A 6-character code in upper case, or a legacy 64-hex token.
  final String code;

  /// The member who shared the link, so the invite can lead with them. Absent
  /// for a typed code.
  final String? from;

  @override
  bool operator ==(Object other) =>
      other is InviteRef && other.code == code && other.from == from;

  @override
  int get hashCode => Object.hash(code, from);
}

final _legacyToken = RegExp(r'^[a-f0-9]{64}$');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// [text] as an invite code: case and spaces ignored, null unless it is six
/// characters of [inviteCodeAlphabet].
String? normalizeInviteCode(String text) {
  final code = text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (code.length != inviteCodeLength) return null;
  for (final char in code.split('')) {
    if (!inviteCodeAlphabet.contains(char)) return null;
  }
  return code;
}

/// The invite in a link: `?code=` (and `&from=`) on the invite page or the
/// app scheme, or a legacy `?invite=` token. Null for anything else.
InviteRef? inviteFromUri(Uri? uri) {
  if (uri == null) return null;
  final params = uri.queryParameters;
  final from = params['from']?.trim().toLowerCase();
  final inviter = from != null && _uuid.hasMatch(from) ? from : null;
  final code = normalizeInviteCode(params['code'] ?? '');
  if (code != null) return InviteRef(code, from: inviter);
  final legacy = params['invite']?.trim().toLowerCase();
  if (legacy != null && _legacyToken.hasMatch(legacy)) {
    return InviteRef(legacy, from: inviter);
  }
  return null;
}

/// Whatever was typed or pasted: a code, a full invite link, or one missing
/// its scheme. Null for anything that is none of those.
InviteRef? inviteFromText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final code = normalizeInviteCode(trimmed);
  if (code != null) return InviteRef(code);
  final fromUri = inviteFromUri(Uri.tryParse(trimmed));
  if (fromUri != null) return fromUri;
  if (!trimmed.contains('://')) {
    return inviteFromUri(Uri.tryParse('https://$trimmed'));
  }
  return null;
}

/// The page an invite link opens: the app when it is installed, the website's
/// install-and-enter-the-code page when it is not.
Uri inviteUrl(String code, {String? from}) => Uri.parse(
  const String.fromEnvironment(
    'APP_SITE_URL',
    defaultValue: 'https://weekpact.codepeaktrail.dev',
  ),
).resolve('/invite/').replace(queryParameters: {'code': code, 'from': ?from});
