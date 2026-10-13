class DataDateLabels {
  const DataDateLabels._();

  static String format(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return '';
    final parsed = DateTime.tryParse(text)?.toLocal();
    if (parsed == null) return text.replaceAll('-', '/');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}/${two(parsed.month)}/${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  static List<String> labels({
    Object? createdAt,
    Object? updatedAt,
  }) {
    final created = format(createdAt);
    final updated = format(updatedAt);
    return [
      if (created.isNotEmpty) '登録日: $created',
      if (updated.isNotEmpty && updated != created) '最終更新日: $updated',
    ];
  }
}
