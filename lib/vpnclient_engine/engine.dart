import 'dart:async';
import 'package:dart_ping/dart_ping.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vpnclient_engine_flutter/vpnclient_engine_flutter.dart';
import 'package:vpnclient_engine_flutter/vpnclient_engine/core.dart';

// Re-export core types for convenience
export 'package:vpnclient_engine_flutter/vpnclient_engine/core.dart';

// Simple logger for production code
void _log(String message) {
  // In production, this could be replaced with a proper logging framework
  // For now, we'll keep print for development but mark it as intentional
  // ignore: avoid_print
  print('VPNClientEngine: $message');
}

class VPNclientEngine {
  static String _lastAddedKey = "";

  static void addVlessKeyDirect(String vlessKey) {
    // Clear previous servers and add only the new vless key
    _servers.clear();
    _servers.add([vlessKey]);
    _lastAddedKey = vlessKey;
    
    // Initialize V2Ray core and pass the key to it
    _vpnCore = V2RayCore();
    (_vpnCore as V2RayCore).addVlessKeyDirect(vlessKey);
    
    _log('Direct vless key added: $vlessKey');
  }
  static final List<List<String>> _servers = [];

  static final _connectionStatusSubject = BehaviorSubject<ConnectionStatus>();
  static Stream<ConnectionStatus> get onConnectionStatusChanged =>
      _connectionStatusSubject.stream;

  static final _errorSubject = BehaviorSubject<ErrorDetails>();
  static Stream<ErrorDetails> get onError => _errorSubject.stream;

  static final _serverSwitchedSubject = BehaviorSubject<String>();
  static Stream<String> get onServerSwitched => _serverSwitchedSubject.stream;

  static final _pingResultSubject = BehaviorSubject<PingResult>();
  static Stream<PingResult> get onPingResult => _pingResultSubject.stream;

  static final _subscriptionLoadedSubject =
      BehaviorSubject<SubscriptionDetails>();
  static Stream<SubscriptionDetails> get onSubscriptionLoaded =>
      _subscriptionLoadedSubject.stream;

  static final _dataUsageUpdatedSubject = BehaviorSubject<SessionStatistics>();
  static Stream<SessionStatistics> get onDataUsageUpdated =>
      _dataUsageUpdatedSubject.stream;

  static final _routingRulesAppliedSubject =
      BehaviorSubject<List<RoutingRule>>();
  static Stream<List<RoutingRule>> get onRoutingRulesApplied =>
      _routingRulesAppliedSubject.stream;

  static final _killSwitchTriggeredSubject = BehaviorSubject<void>();
  static Stream<void> get onKillSwitchTriggered =>
      _killSwitchTriggeredSubject.stream;

  static VpnCore _vpnCore = V2RayCore();

  static void _emitError(ErrorCode code, String message) {
    _errorSubject.add(ErrorDetails(errorCode: code, errorMessage: message));
  }

  static void initialize() {
    _log('VPNclient Engine initialized');
    // Default core is V2Ray
    _vpnCore = V2RayCore();
  }

  static Future<void> connect({
    int? subscriptionIndex,
    int? serverIndex,
    ProxyConfig? proxyConfig,
  }) async {
    // For direct connection without specifying indices
    if (subscriptionIndex == null || serverIndex == null) {
      // We simply use the first server (which should be our vless key)
      _connectionStatusSubject.add(ConnectionStatus.connecting);
      try {
        await _vpnCore.connect(
          subscriptionIndex: 0,
          serverIndex: 0,
        );
        _connectionStatusSubject.add(ConnectionStatus.connected);
      } catch (e) {
        _log('Connection error: $e');
        _connectionStatusSubject.add(ConnectionStatus.error);
        _emitError(ErrorCode.unknownError, 'Connection error: $e');
      }
      return;
    }
    
    // This is the standard connection with specified indices
    _connectionStatusSubject.add(ConnectionStatus.connecting);
    try {
      await _vpnCore.connect(
        subscriptionIndex: subscriptionIndex,
        serverIndex: serverIndex,
      );
      _connectionStatusSubject.add(ConnectionStatus.connected);
    } catch (e) {
      _log('Connection error: $e');
      _connectionStatusSubject.add(ConnectionStatus.error);
      _emitError(ErrorCode.unknownError, 'Connection error: $e');
    }
  }

  static Future<void> disconnect() async {
    await _vpnCore.disconnect();
  }

  static void setRoutingRules({required List<RoutingRule> rules}) {
    for (var rule in rules) {
      if (rule.appName != null) {
        _log('Routing rule for app ${rule.appName}: ${rule.action}');
      } else if (rule.domain != null) {
        _log('Routing rule for domain ${rule.domain}: ${rule.action}');
      }
    }
  }

  static void pingServer({
    required int subscriptionIndex,
    required int index,
  }) async {
    if (subscriptionIndex < 0 ||
        subscriptionIndex >= _servers.length) {
      _log('Invalid subscription index');
      return;
    }
    if (index < 0 || index >= _servers[subscriptionIndex].length) {
      _log('Invalid server index');
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
        ); // Indicate error with -1
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
    }
  }

  static String getConnectionStatus() {
    //  enum ConnectionStatus { connecting, connected, disconnected, error }
    return 'disconnected';
  }

  static List<Server> getServerList() {
    List<Server> servers = [];
    
    _log('getServerList: processing ${_servers.length} servers');
    
    // Convert servers to Server objects
    for (int subIndex = 0; subIndex < _servers.length; subIndex++) {
      _log('getServerList: server group $subIndex has ${_servers[subIndex].length} servers');
      
      for (int serverIndex = 0; serverIndex < _servers[subIndex].length; serverIndex++) {
        final serverUrl = _servers[subIndex][serverIndex];
        _log('getServerList: processing server $serverIndex: $serverUrl');
        
        // Extract server information from URL
        String address = serverUrl;
        String? location;
        
        // Try to extract location from URL if possible
        if (serverUrl.contains('@')) {
          final parts = serverUrl.split('@');
          if (parts.length > 1) {
            final hostPart = parts[1].split(':')[0];
            address = hostPart;
            _log('getServerList: extracted host: $address');
            
            // Simple location detection based on common patterns
            if (hostPart.contains('.us') || hostPart.contains('usa')) {
              location = 'USA';
            } else if (hostPart.contains('.uk') || hostPart.contains('gb')) {
              location = 'UK';
            } else if (hostPart.contains('.ca')) {
              location = 'Canada';
            } else if (hostPart.contains('.de')) {
              location = 'Germany';
            } else if (hostPart.contains('.nl')) {
              location = 'Netherlands';
            } else if (hostPart.contains('.jp')) {
              location = 'Japan';
            } else if (hostPart.contains('.sg')) {
              location = 'Singapore';
            } else {
              location = 'Unknown';
            }
          }
        } else {
          // If no @ symbol, try to extract domain from the URL
          if (serverUrl.contains('://')) {
            final uri = Uri.parse(serverUrl);
            address = uri.host;
            _log('getServerList: extracted host from URI: $address');
          }
        }
        
        final server = Server(
          address: address,
          latency: null, // Will be updated by ping
          location: location,
          isPreferred: false,
        );
        
        servers.add(server);
        _log('getServerList: added server: ${server.address} (${server.location})');
      }
    }
    
    _log('getServerList: returning ${servers.length} servers from subscriptions');
    return servers;
  }

  // Метод loadSubscriptions удален

  static SessionStatistics getSessionStatistics() {
    //TODO:
    return SessionStatistics(
      sessionDuration: Duration(minutes: 30),
      dataInBytes: 1024 * 1024 * 100, // 100MB
      dataOutBytes: 1024 * 1024 * 50, // 50MB
    );
  }

  static void setAutoConnect({required bool enable}) {
    _log('setAutoConnect: $enable');
  }

  static void setKillSwitch({required bool enable}) {
    _log('setKillSwitch: $enable');
  }
}
