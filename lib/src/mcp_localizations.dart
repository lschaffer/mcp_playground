import 'package:flutter/material.dart';

class McpPlaygroundLocalizations {
  final Locale locale;

  McpPlaygroundLocalizations(this.locale);

  static const _localizedValues = {
    'en': {
      'playground': 'Playground',
      'playgroundSettings': 'Playground Settings',
      'agentPlayground': 'AI Agent Playground',
      'pleaseConfigureLlm': 'Please configure the LLM settings first.',
      'systemPrompt': 'System Prompt',
      'systemPromptPlaceholder': 'System prompt...',
      'generatePromptTooltip': 'Generate system prompt using AI',
      'sendMessagePlaceholder': 'Send a message...',
      'agentInspector': 'Agent Inspector',
      'inspectionPanel': 'Inspection Panel',
      'status': 'Status',
      'messages': 'Messages',
      'console': 'Console',
      'tools': 'Tools',
      'close': 'Close',
      'loadSetup': 'Load Setup',
      'saveSetup': 'Save Setup',
      'configName': 'Enter configuration name',
      'cancel': 'Cancel',
      'save': 'Save',
      'reset': 'Reset',
      'applyDefaults': 'Apply defaults from settings',
      'advancedSettings': 'Advanced Custom Settings',
      'initializingServers': 'Initializing Local MCP Servers',
      'preparingRuntime': 'Preparing local server runtime',
      'settingUpServers': 'Setting up local MCP servers...',
      'pleaseWaitInstall':
          'Please wait while local MCP servers are being installed.',
      'done': 'Done',
      'menu': 'Menu',
      'resetTooltip': 'Reset Conversation & Setup',
      'clearTooltip': 'Clear Inputs & Tools',
      'loadTooltip': 'Load Saved Setup Configurations',
      'saveTooltip': 'Save Current Setup Configuration',
      'catalogTooltip': 'Registered Tools Catalog',
      'moreActions': 'More Actions',
      'clear': 'Clear',
      'load': 'Load',
      'htmlDocumentPreview': 'HTML Document Preview',
      'tapMagnifierTooltip': 'Tap magnifier to view full screen',
      'htmlPreview': 'HTML Preview',
      'renderedView': 'Rendered View',
      'htmlSource': 'HTML Source',
      'copyHtmlSource': 'Copy HTML source',
      'htmlSourceCopied': 'HTML source copied to clipboard.',
      'connectingToServer': 'Connecting to server...',
      'startingProcessQueryingTools': 'Starting process and querying available tools list.',
      'connecting': 'Connecting...',
      'offline': 'Offline',
      'serverDisabled': 'Server is disabled',
      'pleaseEnableServerToDiscover': 'Please enable this server using the switch in the server item to start the server and discover its tools.',
      'serverOfflineOrStarting': 'Server is offline or starting',
      'makeSureServerIsRunningToDiscover': 'Make sure this server is installed and running properly to discover its tools.',
      'noToolsRegistered': 'No tools registered by this server.',
      'description': 'Description',
      'inputSchema': 'Input Schema',
      'copyJsonSchema': 'Copy JSON Schema',
      'schemaCopied': 'Schema copied to clipboard',
      'discoveringAvailableTools': 'Discovering available tools...',
      'remoteMcpServers': 'Remote MCP Servers',
      'onDeviceModels': 'On-device models',
      'refresh': 'Refresh',
      'loadModelFailed': 'Load model failed',
      'modelLoadedInApp': 'Model loaded',
      'unloadModel': 'Unload model',
      'loadingModelIntoApp': 'Loading model into app...',
      'discoverPopular': 'Discover popular',
      'addGgufUrl': 'Add GGUF URL',
      'addGgufDisk': 'Add GGUF from Disk',
      'removeAll': 'Remove all',
      'selectDownloadedModelHint': 'Select a downloaded model above to activate it.',
      'downloadModelHint': 'Download a model to use on-device inference.',
    },
    'de': {
      'playground': 'Spielplatz',
      'playgroundSettings': 'Spielplatz-Einstellungen',
      'agentPlayground': 'KI-Agenten-Spielplatz',
      'pleaseConfigureLlm':
          'Bitte konfigurieren Sie zuerst die LLM-Einstellungen.',
      'systemPrompt': 'System-Prompt',
      'systemPromptPlaceholder': 'System-Prompt...',
      'generatePromptTooltip': 'System-Prompt mit KI generieren',
      'sendMessagePlaceholder': 'Nachricht senden...',
      'agentInspector': 'Agenten-Inspektor',
      'inspectionPanel': 'Inspektionspanel',
      'status': 'Status',
      'messages': 'Nachrichten',
      'console': 'Konsole',
      'tools': 'Werkzeuge',
      'close': 'Schließen',
      'loadSetup': 'Setup laden',
      'saveSetup': 'Setup speichern',
      'configName': 'Konfigurationsnamen eingeben',
      'cancel': 'Abbrechen',
      'save': 'Speichern',
      'reset': 'Zurücksetzen',
      'applyDefaults': 'Standardeinstellungen übernehmen',
      'advancedSettings': 'Erweiterte benutzerdefinierte Einstellungen',
      'initializingServers': 'Lokale MCP-Server werden initialisiert',
      'preparingRuntime': 'Lokale Server-Laufzeit wird vorbereitet',
      'settingUpServers': 'Lokale MCP-Server werden eingerichtet...',
      'pleaseWaitInstall':
          'Bitte warten Sie, während die lokalen MCP-Server installiert werden.',
      'done': 'Fertig',
      'menu': 'Menü',
      'resetTooltip': 'Konversation und Setup zurücksetzen',
      'clearTooltip': 'Eingaben und Werkzeuge löschen',
      'loadTooltip': 'Gespeicherte Setup-Konfigurationen laden',
      'saveTooltip': 'Aktuelle Setup-Konfiguration speichern',
      'catalogTooltip': 'Katalog der registrierten Werkzeuge',
      'moreActions': 'Weitere Aktionen',
      'clear': 'Löschen',
      'load': 'Laden',
      'htmlDocumentPreview': 'HTML-Dokument-Vorschau',
      'tapMagnifierTooltip': 'Lupe tippen, um im Vollbildmodus anzuzeigen',
      'htmlPreview': 'HTML-Vorschau',
      'renderedView': 'Gerenderte Ansicht',
      'htmlSource': 'HTML-Quellcode',
      'copyHtmlSource': 'HTML-Quellcode kopieren',
      'htmlSourceCopied': 'HTML-Quellcode in die Zwischenablage kopiert.',
      'connectingToServer': 'Verbindung zum Server wird hergestellt...',
      'startingProcessQueryingTools': 'Prozess wird gestartet und Liste der verfügbaren Werkzeuge abgefragt.',
      'connecting': 'Verbindung wird hergestellt...',
      'offline': 'Offline',
      'serverDisabled': 'Server ist deaktiviert',
      'pleaseEnableServerToDiscover': 'Bitte aktivieren Sie diesen Server, um seine Werkzeuge zu entdecken.',
      'serverOfflineOrStarting': 'Server ist offline oder startet',
      'makeSureServerIsRunningToDiscover': 'Stellen Sie sicher, dass dieser Server ordnungsgemäß läuft, um seine Werkzeuge zu entdecken.',
      'noToolsRegistered': 'Keine Werkzeuge von diesem Server registriert.',
      'description': 'Beschreibung',
      'inputSchema': 'Eingabeschema',
      'copyJsonSchema': 'JSON-Schema kopieren',
      'schemaCopied': 'Schema in die Zwischenablage kopiert',
      'discoveringAvailableTools': 'Verfügbare Werkzeuge werden ermittelt...',
      'remoteMcpServers': 'Remote-MCP-Server',
      'onDeviceModels': 'Lokale Modelle auf dem Gerät',
      'refresh': 'Aktualisieren',
      'loadModelFailed': 'Modell laden fehlgeschlagen',
      'modelLoadedInApp': 'Modell geladen',
      'unloadModel': 'Modell entladen',
      'loadingModelIntoApp': 'Modell wird geladen...',
      'discoverPopular': 'Beliebte entdecken',
      'addGgufUrl': 'GGUF-URL hinzufügen',
      'addGgufDisk': 'GGUF von Festplatte',
      'removeAll': 'Alle entfernen',
      'selectDownloadedModelHint': 'Wählen Sie ein heruntergeladenes Modell aus, um es zu aktivieren.',
      'downloadModelHint': 'Laden Sie ein Modell herunter, um die lokale Inferenz zu nutzen.',
    },
  };

  static const LocalizationsDelegate<McpPlaygroundLocalizations> delegate =
      _McpPlaygroundLocalizationsDelegate();

  static McpPlaygroundLocalizations of(BuildContext context) {
    return Localizations.of<McpPlaygroundLocalizations>(
          context,
          McpPlaygroundLocalizations,
        ) ??
        McpPlaygroundLocalizations(const Locale('en'));
  }

  String get(String key) {
    final languageCode = locale.languageCode;
    return _localizedValues[languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class _McpPlaygroundLocalizationsDelegate
    extends LocalizationsDelegate<McpPlaygroundLocalizations> {
  const _McpPlaygroundLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'de'].contains(locale.languageCode);

  @override
  Future<McpPlaygroundLocalizations> load(Locale locale) {
    return Future.value(McpPlaygroundLocalizations(locale));
  }

  @override
  bool shouldReload(_McpPlaygroundLocalizationsDelegate old) => false;
}
