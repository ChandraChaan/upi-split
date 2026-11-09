/// Used by tests and other non-browser builds, where these do nothing.
class PickedTextFile {
  const PickedTextFile(this.name, this.text);
  final String name;
  final String text;
}

void downloadTextFile(String filename, String content, {String mime = 'text/csv'}) {}

Future<PickedTextFile?> pickTextFile({String accept = '.csv'}) async => null;

void printHtml(String html) {}
