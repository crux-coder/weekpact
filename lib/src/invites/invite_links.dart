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

String? inviteTokenFromUri(Uri? uri) {
  final token = uri?.queryParameters['invite']?.trim();
  return token == null || token.isEmpty ? null : token;
}
