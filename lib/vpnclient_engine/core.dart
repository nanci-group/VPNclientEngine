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
  // Keeping this class for compatibility but it will be replaced in the future
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
  final int groupIndex;
  final int serverIndex;
  final int latencyInMs;

  PingResult({
    required int subscriptionIndex, // Keep parameter name for compatibility
    required this.serverIndex,
    required this.latencyInMs,
  }) : groupIndex = subscriptionIndex;
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
  Future<void> loadSubscriptions({required List<String> subscriptionLinks}); // To be renamed to loadServers in future
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

  final _connectionStatusSubject = BehaviorSubject<ConnectionStatus>();
  Stream<ConnectionStatus> get onConnectionStatusChanged =>
      _connectionStatusSubject.stream;

  final _errorSubject = BehaviorSubject<ErrorDetails>();
  Stream<ErrorDetails> get onError => _errorSubject.stream;

  final _serverSwitchedSubject = BehaviorSubject<String>();
  Stream<String> get onServerSwitched => _serverSwitchedSubject.stream;

  final _pingResultSubject = BehaviorSubject<PingResult>();
  Stream<PingResult> get onPingResult => _pingResultSubject.stream;

  final _serversLoadedSubject = BehaviorSubject<SubscriptionDetails>();
  Stream<SubscriptionDetails> get onSubscriptionLoaded =>
      _serversLoadedSubject.stream;

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

  // Removed updateSubscription method that relied on subscriptions

  @override
  Future<void> connect({
    required int subscriptionIndex,
    required int serverIndex,
  }) async {
    try {
      if (subscriptionIndex < 0 ||
          subscriptionIndex >= _servers.length) {
        _log('Invalid server group index: $subscriptionIndex');
        return;
      }
      if (serverIndex < 0 ||
          serverIndex >= _servers[subscriptionIndex].length) {
        _log('Invalid server index: $serverIndex');
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
      _log('Invalid server group index: $subscriptionIndex');
      _emitError(ErrorCode.unknownError, 'Invalid server group index');
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
          'Ping result: group=${result.groupIndex}, server=${result.serverIndex}, latency=${result.latencyInMs} ms',
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
    _log('Loading VLESS keys: ${subscriptionLinks.join(", ")}');
    
    List<String> servers = subscriptionLinks.where((key) => key.trim().isNotEmpty).toList();
    
    if (servers.isNotEmpty) {
      while (_servers.length <= 0) {
        _servers.add([]);
      }
      _servers[0] = servers;
      _serversLoadedSubject.add(SubscriptionDetails());
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
