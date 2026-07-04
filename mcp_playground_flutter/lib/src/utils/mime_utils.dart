/// Simple MIME-type lookup by file extension.
String mimeFromExtension(String name) {
  final ext = name.split('.').last.toLowerCase();
  const map = <String, String>{
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'application/xml',
    'yaml': 'text/yaml',
    'yml': 'text/yaml',
    'html': 'text/html',
    'htm': 'text/html',
    'js': 'application/javascript',
    'dart': 'text/x-dart',
    'py': 'text/x-python',
    'sh': 'application/x-sh',
    'bat': 'application/x-bat',
    'ps1': 'application/x-powershell',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'webp': 'image/webp',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    'log': 'text/plain',
  };
  return map[ext] ?? 'application/octet-stream';
}

/// Helper to determine if a MIME type or file extension indicates a text file.
bool isTextFile(String mimeType, String filename) {
  final mime = mimeType.toLowerCase();
  if (mime.startsWith('text/')) return true;

  final name = filename.toLowerCase();
  return name.endsWith('.txt') ||
      name.endsWith('.md') ||
      name.endsWith('.csv') ||
      name.endsWith('.json') ||
      name.endsWith('.yaml') ||
      name.endsWith('.yml') ||
      name.endsWith('.xml') ||
      name.endsWith('.html') ||
      name.endsWith('.js') ||
      name.endsWith('.py') ||
      name.endsWith('.dart') ||
      name.endsWith('.sh') ||
      name.endsWith('.bat') ||
      name.endsWith('.ps1') ||
      name.endsWith('.log');
}
