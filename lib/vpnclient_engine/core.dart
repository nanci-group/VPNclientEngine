import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dart_ping/dart_ping.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/services.dart';

// Platform-specific imports
import 'platform_imports.dart';

// Simple logger for production code
void _log(String message) {
  // In production, this could be replaced with a proper logging framework
  // For now, we'll keep print for development but mark it as intentional
  // ignore: avoid_print
  print('VPNClientEngine: $message');
}

enum ConnectionStatus { connecting, connected, disconnected, error }

enum ErrorCode {
  invalidCredentials,
  serverUnavailable,
  subscriptionExpired,
  unknownError,
}

enum ProxyType { socks5, http }

enum Action { block, allow, routeThroughVPN, direct, proxy }

class Server {
  final String address;
  final int? latency;
  final String? location;
  final bool? isPreferred;

  Server({
    required this.address,
    this.latency,
    this.location,
    this.isPreferred,
  });
}

class SubscriptionDetails {
  final DateTime? expiryDate;
  final int? dataLimit;
  final int? usedData;

  SubscriptionDetails({this.expiryDate, this.dataLimit, this.usedData});
}

class SessionStatistics {
  final Duration? sessionDuration;
  final int dataInBytes;
  final int dataOutBytes;

  SessionStatistics({
    this.sessionDuration,
    required this.dataInBytes,
    required this.dataOutBytes,
  });
}

class ErrorDetails {
  final ErrorCode errorCode;
  final String errorMessage;

  ErrorDetails({required this.errorCode, required this.errorMessage});
}

class ProxyConfig {
  final ProxyType type;
  final String address;
  final int port;
  final String? credentials;

  ProxyConfig({
    required this.type,
    required this.address,
    required this.port,
    this.credentials,
  });
}

class PingResult {
  final int subscriptionIndex;
  final int serverIndex;
  final int latencyInMs;

  PingResult({
    required this.subscriptionIndex,
    required this.serverIndex,
    required this.latencyInMs,
  });
}

class RoutingRule {
  final String? appName;
  final String? domain;
  final String action; // proxy, direct, block

  RoutingRule({this.appName, this.domain, required this.action});
}

class WireGuardCore implements VpnCore {
  @override
  Future<void> connect({
    required int subscriptionIndex,
    required int serverIndex,
  }) async {
    _log('WireGuardCore: connect called');
    // TODO: implement WireGuard connection
  }

  @override
  Future<void> disconnect() async {
    _log('WireGuardCore: disconnect called');
    // TODO: implement WireGuard disconnection
  }

  @override
  String getConnectionStatus() {
    return 'disconnected';
  }

  @override
  void setRoutingRules({required List<RoutingRule> rules}) {
    _log('WireGuardCore: setRoutingRules called');
  }

  @override
  SessionStatistics getSessionStatistics() {
    return SessionStatistics(dataInBytes: 0, dataOutBytes: 0);
  }

  @override
  Future<void> loadSubscriptions({required List<String> subscriptionLinks}) async {
    _log('WireGuardCore: loadSubscriptions called');
  }

  @override
  void pingServer({required int subscriptionIndex, required int index}) {
    _log('WireGuardCore: pingServer called');
  }

  @override
  List<Server> getServerList() {
    return [];
  }

  @override
  void setAutoConnect({required bool enable}) {
    _log('WireGuardCore: setAutoConnect called');
  }

  @override
  void setKillSwitch({required bool enable}) {
    _log('WireGuardCore: setKillSwitch called');
  }
}

abstract class VpnCore {
  // Made indices required but simplified how they're used internally
  Future<void> connect({
    required int subscriptionIndex,
    required int serverIndex,
  });
  Future<void> disconnect();
  String getConnectionStatus();
  void setRoutingRules({required List<RoutingRule> rules});
  SessionStatistics getSessionStatistics();
  Future<void> loadSubscriptions({required List<String> subscriptionLinks});
  void pingServer({required int subscriptionIndex, required int index});
  List<Server> getServerList();
  void setAutoConnect({required bool enable});
  void setKillSwitch({required bool enable});
}

// Stub classes for platform compatibility
class MethodChannel {
  final String name;
  
  const MethodChannel(this.name);
  
  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    return true; // Stub implementation
  }
}

// Stub for BehaviorSubject
class BehaviorSubject<T> {
  final Stream<T> stream = Stream.empty();
  
  void add(T value) {
    // Stub implementation
  }
}

// Stub for Ping
class Ping {
  final String host;
  final int count;
  
  Ping(this.host, {this.count = 3});
  
  final Stream stream = Stream.empty();
}

class V2RayCore implements VpnCore {
  // Platform-specific VPN implementation
  final bool _isWindows = Platform.isWindows;
  VpnImplementation? _vpnImplementation;
  
  // Method channel for platform communication
  static const MethodChannel _methodChannel = MethodChannel('vpnclient_engine_flutter');
  
  // Store servers and configurations
  final List<List<String>> _servers = [];
  final List<String> _subscriptions = [];
  
  // SingBox configuration path for Windows
  String _configPath = '';
  
  // RxDart subjects for stream controllers
  final _connectionStatusSubject = BehaviorSubject<ConnectionStatus>();
  final _errorSubject = BehaviorSubject<ErrorDetails>();
  final _serverSwitchedSubject = BehaviorSubject<String>();
  final _pingResultSubject = BehaviorSubject<PingResult>();
  final _subscriptionLoadedSubject = BehaviorSubject<SubscriptionDetails>();
  final _dataUsageUpdatedSubject = BehaviorSubject<SessionStatistics>();
  final _routingRulesAppliedSubject = BehaviorSubject<List<RoutingRule>>();
  final _killSwitchTriggeredSubject = BehaviorSubject<void>();
  
  // Define streams to expose data
  Stream<ConnectionStatus> get onConnectionStatusChanged => _connectionStatusSubject.stream;
  Stream<ErrorDetails> get onError => _errorSubject.stream;
  Stream<String> get onServerSwitched => _serverSwitchedSubject.stream;
  Stream<PingResult> get onPingResult => _pingResultSubject.stream;
  Stream<SubscriptionDetails> get onSubscriptionLoaded => _subscriptionLoadedSubject.stream;
  Stream<SessionStatistics> get onDataUsageUpdated => _dataUsageUpdatedSubject.stream;
  Stream<List<RoutingRule>> get onRoutingRulesApplied => _routingRulesAppliedSubject.stream;
  Stream<void> get onKillSwitchTriggered => _killSwitchTriggeredSubject.stream;

  void _emitError(ErrorCode code, String message) {
    _errorSubject.add(ErrorDetails(errorCode: code, errorMessage: message));
  }

  void initialize() {
    try {
      // Get the appropriate implementation for the current platform
      _vpnImplementation = PlatformImplementation.getImplementation(
        onStatusChanged: (status) {
          // Handle status changes
          _log('VPN status changed: $status');
        },
      );
      
      if (_vpnImplementation == null) {
        _log('No VPN implementation available for this platform');
      } else if (_isWindows) {
        _log('V2RayCore initialized for Windows using SingBox');
      } else {
        _log('V2RayCore initialized for mobile');
      }
    } catch (e) {
      _log('Error initializing VPN implementation: $e');
    }
  }

  void clearServers() {
    _servers.clear();
    _log('All servers cleared');
  }

  void addVlessKeyDirect(String vlessKey) {
    // Clear existing servers and add the vless key as the only server
    _servers.clear();
    _servers.add([vlessKey]);
    _log('Direct vless key added to V2RayCore: $vlessKey');
  }

  Future<void> updateSubscription({required int subscriptionIndex}) async {
    if (subscriptionIndex < 0 || subscriptionIndex >= _subscriptions.length) {
      _log('Invalid subscription index');
      return;
    }

    final url = _subscriptions[subscriptionIndex];
    _log('Fetching subscription data from: $url');

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        _log('Failed to fetch subscription: HTTP ${response.statusCode}');
        return;
      }

      final content = response.body.trim();

      List<String> servers = [];

      if (content.startsWith('[')) {
        final jsonList = jsonDecode(content) as List<dynamic>;
        for (var server in jsonList) {
          servers.add(server.toString());
        }
        _log('Parsed JSON subscription: ${servers.length} servers loaded');
      } else {
        servers =
            content
                .split('\n')
                .where((line) => line.trim().isNotEmpty)
                .toList();
        _log('Parsed NEWLINE subscription: ${servers.length} servers loaded');
      }

      while (_servers.length <= subscriptionIndex) {
        _servers.add([]);
      }

      _servers[subscriptionIndex] = servers;
      _subscriptionLoadedSubject.add(SubscriptionDetails());

      _log('Subscription #$subscriptionIndex servers updated successfully');
    } catch (e) {
      _log('Error updating subscription: $e');
      _emitError(ErrorCode.unknownError, 'Error updating subscription: $e');
    }
  }

  // Helper method to generate SingBox config for Windows
  String _generateSingBoxConfig(String vlessKey) {
    // Extract necessary information from the VLESS key
    String host = '';
    int port = 443; // Default port
    String uuid = '';
    String sni = '';
    bool tls = true;
    String network = "tcp";
    String security = "tls";
    Map<String, dynamic> wsSettings = {};
    
    _log('Generating SingBox config for key: $vlessKey');
    
    try {
      // Handle vless:// format URLs
      if (vlessKey.startsWith('vless://')) {
        // Extract the UUID part (everything between vless:// and @)
        int atIndex = vlessKey.indexOf('@');
        if (atIndex != -1) {
          uuid = vlessKey.substring(8, atIndex);
          
          // Extract host and port from the part after @
          String serverPart = vlessKey.substring(atIndex + 1);
          int colonIndex = serverPart.indexOf(':');
          
          if (colonIndex != -1) {
            host = serverPart.substring(0, colonIndex);
            
            // Extract port (handle potential query parameters)
            String portPart = serverPart.substring(colonIndex + 1);
            int questionMarkIndex = portPart.indexOf('?');
            
            if (questionMarkIndex != -1) {
              port = int.tryParse(portPart.substring(0, questionMarkIndex)) ?? 443;
              
              // Parse query parameters
              String queryParams = portPart.substring(questionMarkIndex + 1);
              Map<String, String> params = {};
              
              // Split by &
              List<String> paramPairs = queryParams.split('&');
              for (String pair in paramPairs) {
                List<String> keyValue = pair.split('=');
                if (keyValue.length == 2) {
                  params[keyValue[0]] = keyValue[1];
                }
              }
              
              // Extract common parameters
              sni = params['sni'] ?? host;
              security = params['security'] ?? 'tls';
              tls = security == 'tls' || security == 'xtls';
              network = params['type'] ?? 'tcp';
              
              // Handle websocket settings
              if (network == 'ws') {
                wsSettings['path'] = params['path'] ?? '/';
                if (params.containsKey('host')) {
                  wsSettings['headers'] = {'Host': params['host']};
                }
              }
            } else {
              port = int.tryParse(portPart) ?? 443;
            }
          } else {
            host = serverPart;
          }
        }
      } else {
        // Fallback to simple Uri parsing for other formats
        Uri uri = Uri.parse(vlessKey);
        host = uri.host;
        port = uri.port > 0 ? uri.port : 443;
        uuid = uri.userInfo;
        sni = host;
      }
    } catch (e) {
      _log('Error parsing VLESS key: $e');
      // Provide default values in case of parsing error
      host = 'example.com';
      uuid = '00000000-0000-0000-0000-000000000000';
      sni = host;
    }
    
    _log('Parsed VLESS key - Host: $host, Port: $port, UUID: $uuid, SNI: $sni, Network: $network');
    
    // Create the outbound configuration based on protocol details
    Map<String, dynamic> outbound = {
      "type": "vless",
      "tag": "vless-out",
      "server": host,
      "server_port": port,
      "uuid": uuid,
      "flow": "",
    };
    
    // Add TLS configuration if needed
    if (tls) {
      outbound["tls"] = {
        "enabled": true,
        "server_name": sni,
        "insecure": false
      };
    }
    
    // Add transport settings based on network type
    if (network == "ws") {
      outbound["transport"] = {
        "type": "ws",
        "path": wsSettings['path'] ?? "/",
      };
      
      if (wsSettings.containsKey('headers')) {
        outbound["transport"]["headers"] = wsSettings['headers'];
      }
    }
    
    // Create a basic SingBox configuration
    Map<String, dynamic> config = {
      "log": {"level": "info"},
      "inbounds": [{
        "type": "mixed",
        "tag": "mixed-in",
        "listen": "127.0.0.1",
        "listen_port": 1080
      }],
      "outbounds": [outbound]
    };
    
    // Create a temporary config file
    String tempDir = Platform.isWindows ? 
      '${Platform.environment['TEMP']}\\singbox' : 
      '/tmp/singbox';
    
    // Create the directory if it doesn't exist
    Directory(tempDir).createSync(recursive: true);
    
    // Write the config to a file
    String configPath = '$tempDir\\config.json';
    File(configPath).writeAsStringSync(jsonEncode(config));
    
    _log('Generated SingBox config at: $configPath');
    return configPath;
  }

  @override
  Future<void> connect({
    required int subscriptionIndex,
    required int serverIndex,
  }) async {
    try {
      // Ensure _servers has enough entries
      while (_servers.length <= subscriptionIndex) {
        _servers.add([]);
      }
      
      if (serverIndex < 0 ||
          serverIndex >= _servers[subscriptionIndex].length) {
        _log('Invalid server index');
        return;
      }

      final serverAddress = _servers[subscriptionIndex][serverIndex];
      _connectionStatusSubject.add(ConnectionStatus.connecting);
      
      // Check if we have a valid implementation
      if (_vpnImplementation == null) {
        throw Exception('No VPN implementation available for this platform');
      }
      
      if (_isWindows) {
        // Windows implementation using SingBox
        _configPath = _generateSingBoxConfig(serverAddress);
        
        // Use platform channel to start SingBox
        final Map<String, dynamic> params = {
          'configPath': _configPath
        };
        
        bool success = await _methodChannel.invokeMethod('startSingBox', params);
        
        if (success) {
          _serverSwitchedSubject.add(serverAddress);
          _connectionStatusSubject.add(ConnectionStatus.connected);
          _log('Successfully connected using SingBox on Windows');
        } else {
          throw Exception('Failed to start SingBox');
        }
      } else {
        // Mobile implementation using platform-agnostic approach
        await _vpnImplementation!.initialize();
        
        if (await _vpnImplementation!.requestPermission()) {
          final configData = await _vpnImplementation!.parseConfigFromURL(serverAddress);
          
          bool success = await _vpnImplementation!.startVpn(
            serverConfig: serverAddress,
            remark: configData['remark'] as String?,
            blockedApps: null,
            bypassSubnets: null,
            proxyOnly: false,
          );
          
          if (success) {
            _serverSwitchedSubject.add(serverAddress);
            _connectionStatusSubject.add(ConnectionStatus.connected);
            _log('Successfully connected using platform VPN');
          } else {
            throw Exception('Failed to start VPN');
          }
        }
      }
    } catch (e) {
      _emitError(ErrorCode.unknownError, 'Error connecting: $e');
      _connectionStatusSubject.add(ConnectionStatus.error);
    }
  }

  @override
  Future<void> disconnect() async {
    if (_isWindows) {
      // Windows implementation using SingBox
      try {
        await _methodChannel.invokeMethod('stopSingBox');
        _connectionStatusSubject.add(ConnectionStatus.disconnected);
        _log('Disconnected SingBox successfully');
      } catch (e) {
        _log('Error stopping SingBox: $e');
      }
    } else if (_vpnImplementation != null) {
      // Mobile implementation using platform-agnostic approach
      bool success = await _vpnImplementation!.stopVpn();
      if (success) {
        _connectionStatusSubject.add(ConnectionStatus.disconnected);
        _log('Disconnected VPN successfully');
      } else {
        _log('Error stopping VPN');
      }
    }
  }

  @override
  void setRoutingRules({required List<RoutingRule> rules}) {
    for (var rule in rules) {
      if (rule.appName != null) {
        _log('Routing rule for app ${rule.appName}: ${rule.action}');
      } else if (rule.domain != null) {
        _log('Routing rule for domain ${rule.domain}: ${rule.action}');
      }
    }
  }

  @override
  void pingServer({required int subscriptionIndex, required int index}) async {
    // Ensure _servers has enough entries
    while (_servers.length <= subscriptionIndex) {
      _servers.add([]);
    }
    
    if (index < 0 || index >= _servers[subscriptionIndex].length) {
      _log('Invalid server index');
      _emitError(ErrorCode.unknownError, 'Invalid server index');
      return;
    }
    final serverAddress = _servers[subscriptionIndex][index];
    _log('Pinging server: $serverAddress');
    try {
      final ping = Ping(serverAddress, count: 3);
      final pingData = await ping.stream.firstWhere(
        (data) => data.response != null,
      );
      if (pingData.response != null) {
        final latency = pingData.response!.time!.inMilliseconds;
        final result = PingResult(
          subscriptionIndex: subscriptionIndex,
          serverIndex: index,
          latencyInMs: latency,
        );
        _pingResultSubject.add(result);
        _log(
          'Ping result: sub=${result.subscriptionIndex}, server=${result.serverIndex}, latency=${result.latencyInMs} ms',
        );
      } else {
        _log('Ping failed: No response');
        _pingResultSubject.add(
          PingResult(
            subscriptionIndex: subscriptionIndex,
            serverIndex: index,
            latencyInMs: -1,
          ),
        );
        _emitError(ErrorCode.serverUnavailable, 'Ping failed: No response');
      }
    } catch (e) {
      _log('Ping error: $e');
      _pingResultSubject.add(
        PingResult(
          subscriptionIndex: subscriptionIndex,
          serverIndex: index,
          latencyInMs: -1,
        ),
      );
      _emitError(ErrorCode.unknownError, 'Ping error: $e');
    }
  }

  @override
  String getConnectionStatus() {
    return 'disconnected';
  }

  @override
  List<Server> getServerList() {
    List<Server> serverList = [];
    
    for (int i = 0; i < _servers.length; i++) {
      for (int j = 0; j < _servers[i].length; j++) {
        serverList.add(
          Server(
            address: _servers[i][j],
            latency: 0, // No latency data initially
            location: 'Unknown', // Location unknown
            isPreferred: false,
          ),
        );
      }
    }
    
    return serverList.isNotEmpty ? serverList : [
      // Fallback hardcoded list
      Server(
        address: 'No servers available',
        latency: 0,
        location: 'N/A',
        isPreferred: false,
      ),
    ];
  }

  @override
  Future<void> loadSubscriptions({
    required List<String> subscriptionLinks,
  }) async {
    _log('Loading vless keys: ${subscriptionLinks.join(", ")}');
    
    List<String> servers = subscriptionLinks.where((key) => key.trim().isNotEmpty).toList();
    
    if (servers.isNotEmpty) {
      // Clear existing servers and add new ones directly
      _servers.clear();
      _servers.add(servers);
      _subscriptionLoadedSubject.add(SubscriptionDetails());
      _log('Direct VLESS keys loaded: ${servers.length}');
    }
  }

  @override
  SessionStatistics getSessionStatistics() {
    return SessionStatistics(
      sessionDuration: Duration(minutes: 30),
      dataInBytes: 1024 * 1024 * 100,
      dataOutBytes: 1024 * 1024 * 50,
    );
  }

  @override
  void setAutoConnect({required bool enable}) {
    _log('setAutoConnect: $enable');
  }

  @override
  void setKillSwitch({required bool enable}) {
    _log('setKillSwitch: $enable');
  }
}

class OpenVPNCore implements VpnCore {
  @override
  Future<void> connect({
    required int subscriptionIndex,
    required int serverIndex,
  }) async {
    _log('OpenVPNCore: connect called');
    // TODO: implement OpenVPN connection
  }

  @override
  Future<void> disconnect() async {
    _log('OpenVPNCore: disconnect called');
    // TODO: implement OpenVPN disconnection
  }

  @override
  String getConnectionStatus() {
    return 'disconnected';
  }

  @override
  void setRoutingRules({required List<RoutingRule> rules}) {
    _log('OpenVPNCore: setRoutingRules called');
  }

  @override
  SessionStatistics getSessionStatistics() {
    return SessionStatistics(dataInBytes: 0, dataOutBytes: 0);
  }

  @override
  Future<void> loadSubscriptions({required List<String> subscriptionLinks}) async {
    _log('OpenVPNCore: loadSubscriptions called');
  }

  @override
  void pingServer({required int subscriptionIndex, required int index}) {
    _log('OpenVPNCore: pingServer called');
  }

  @override
  List<Server> getServerList() {
    return [];
  }

  @override
  void setAutoConnect({required bool enable}) {
    _log('OpenVPNCore: setAutoConnect called');
  }

  @override
  void setKillSwitch({required bool enable}) {
    _log('OpenVPNCore: setKillSwitch called');
  }
}
