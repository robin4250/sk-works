/// Blank optional order fields are omitted so older servers can still save prose.
/// Replacing a template with omitted optional fields also clears prior defaults.
Map<String, String> tradeDocumentTemplatePayload(Map<String, String> fields) => {
  for (final entry in fields.entries)
    if (!{'work_name', 'work_address'}.contains(entry.key) ||
        entry.value.trim().isNotEmpty)
      entry.key: entry.value.trim(),
};
