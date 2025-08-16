import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_ping/dart_ping.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:rxdart/rxdart.dart';

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

class V2RayCore implements VpnCore {
  final FlutterV2ray _flutterV2ray = FlutterV2ray(
    onStatusChanged: (status) {
      // do something
    },
  );
  final List<List<String>> _servers = [];
  final List<String> _subscriptions = [];

  final _connectionStatusSubject = BehaviorSubject<ConnectionStatus>();
  Stream<ConnectionStatus> get onConnectionStatusChanged =>
      _connectionStatusSubject.stream;

  final _errorSubject = BehaviorSubject<ErrorDetails>();
  Stream<ErrorDetails> get onError => _errorSubject.stream;

  final _serverSwitchedSubject = BehaviorSubject<String>();
  Stream<String> get onServerSwitched => _serverSwitchedSubject.stream;

  final _pingResultSubject = BehaviorSubject<PingResult>();
  Stream<PingResult> get onPingResult => _pingResultSubject.stream;

  final _subscriptionLoadedSubject = BehaviorSubject<SubscriptionDetails>();
  Stream<SubscriptionDetails> get onSubscriptionLoaded =>
      _subscriptionLoadedSubject.stream;

  final _dataUsageUpdatedSubject = BehaviorSubject<SessionStatistics>();
  Stream<SessionStatistics> get onDataUsageUpdated =>
      _dataUsageUpdatedSubject.stream;

  final _routingRulesAppliedSubject = BehaviorSubject<List<RoutingRule>>();
  Stream<List<RoutingRule>> get onRoutingRulesApplied =>
      _routingRulesAppliedSubject.stream;

  final _killSwitchTriggeredSubject = BehaviorSubject<void>();
  Stream<void> get onKillSwitchTriggered => _killSwitchTriggeredSubject.stream;

  void _emitError(ErrorCode code, String message) {
    _errorSubject.add(ErrorDetails(errorCode: code, errorMessage: message));
  }

  void initialize() {
    _log('V2RayCore initialized');
  }

  void clearServers() {
    _servers.clear();
    _log('All servers cleared');
  }

  void addVlessKeyDirect(String vlessKey) {
    // Add a new server list with a single vless key
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

  @override
  Future<void> connect({
    required int subscriptionIndex,
    required int serverIndex,
  }) async {
    try {
      if (subscriptionIndex < 0 ||
          subscriptionIndex >= _servers.length) {
        _log('Invalid subscription index');
        return;
      }
      if (serverIndex < 0 ||
          serverIndex >= _servers[subscriptionIndex].length) {
        _log('Invalid server index');
        return;
      }

      await _flutterV2ray.initializeV2Ray();

      final serverAddress =
          _servers[subscriptionIndex][serverIndex];
      V2RayURL parser = FlutterV2ray.parseFromURL(serverAddress);

      _connectionStatusSubject.add(ConnectionStatus.connecting);
      if (await _flutterV2ray.requestPermission()) {
        _flutterV2ray.startV2Ray(
          remark: parser.remark,
          config: parser.getFullConfiguration(),
          blockedApps: null,
          bypassSubnets: null,
          proxyOnly: false,
        );
      }
      _serverSwitchedSubject.add(serverAddress);
      _connectionStatusSubject.add(ConnectionStatus.connected);
      _log('Successfully connected');
    } catch (e) {
      _emitError(ErrorCode.unknownError, 'Error connecting: $e');
      _connectionStatusSubject.add(ConnectionStatus.error);
    }
  }

  @override
  Future<void> disconnect() async {
    _flutterV2ray.stopV2Ray();
    _connectionStatusSubject.add(ConnectionStatus.disconnected);
    _log('Disconnected successfully');
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
    if (subscriptionIndex < 0 ||
        subscriptionIndex >= _servers.length) {
      _log('Invalid subscription index');
      _emitError(ErrorCode.unknownError, 'Invalid subscription index');
      return;
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
    _log('loadSubscriptions: ${subscriptionLinks.join(", ")}');
    
    List<String> servers = subscriptionLinks.where((key) => key.trim().isNotEmpty).toList();
    
    if (servers.isNotEmpty) {
      while (_servers.length <= 0) {
        _servers.add([]);
      }
      _servers[0] = servers;
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
