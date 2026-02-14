// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void setWebMeta({
  required String title,
  required String description,
}) {
  html.document.title = title;
  final head = html.document.head;
  if (head == null) return;
  html.MetaElement? descriptionTag =
      head.querySelector('meta[name="description"]') as html.MetaElement?;
  descriptionTag ??= html.MetaElement()
    ..name = 'description'
    ..setAttribute('name', 'description');
  descriptionTag.content = description;
  if (descriptionTag.parent == null) {
    head.append(descriptionTag);
  }
}

void setWebPath(String path) {
  final nextPath = path.trim().isEmpty ? '/' : path.trim();
  final normalized = nextPath.startsWith('/') ? nextPath : '/$nextPath';
  try {
    html.window.history.replaceState(null, '', normalized);
  } catch (_) {}
}
