import 'package:url_launcher/url_launcher.dart';

abstract class ExternalUrlLauncher {
  Future<bool> open(Uri url);
}

class UrlLauncherExternalUrlLauncher implements ExternalUrlLauncher {
  const UrlLauncherExternalUrlLauncher();

  @override
  Future<bool> open(Uri url) {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
