import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// Define interfaces for platform-specific implementations
abstract class VpnImplementation {
  Future<bool> initialize();
  Future<bool> requestPermission();
  Future<bool> startVpn({
    required String serverConfig,
    String? remark,
    dynamic blockedApps,
    dynamic bypassSubnets,
    bool proxyOnly = false,
  });
  Future<bool> stopVpn();
  Future<dynamic> parseConfigFromURL(String url);
}

// Simple logger for production code
void _log(String message) {
  // In production, this could be replaced with a proper logging framework
  // For now, we'll keep print for development but mark it as intentional
  // ignore: avoid_print
  print('VPNClientEngine: $message');
}

// This file provides platform-specific implementations
class PlatformImplementation {
  static VpnImplementation? getImplementation({
    Function(dynamic)? onStatusChanged
  }) {
    if (Platform.isAndroid) {
      _log('Using stub Android implementation');
      return StubVpnImplementation(onStatusChanged: onStatusChanged);
    } else if (Platform.isIOS || Platform.isMacOS) {
      _log('Using stub iOS/macOS implementation');
      return StubVpnImplementation(onStatusChanged: onStatusChanged);
    } else if (Platform.isWindows) {
      _log('Using Windows SingBox implementation');
      return WindowsVpnImplementation(onStatusChanged: onStatusChanged);
    } else {
      // For unsupported platforms
      _log('No VPN implementation available for this platform');
      return null;
    }
  }
}

// Stub implementation for platforms
class StubVpnImplementation implements VpnImplementation {
  final Function(dynamic)? onStatusChanged;

  StubVpnImplementation({this.onStatusChanged});
  
  @override
  Future<bool> initialize() async {
    _log('StubVpnImplementation: initialize() called');
    return true;
  }
  
  @override
  Future<bool> requestPermission() async {
    _log('StubVpnImplementation: requestPermission() called');
    return true;
  }
  
  @override
  Future<bool> startVpn({
    required String serverConfig,
    String? remark,
    dynamic blockedApps,
    dynamic bypassSubnets,
    bool proxyOnly = false,
  }) async {
    _log('StubVpnImplementation: startVpn() called with config: $serverConfig');
    if (onStatusChanged != null) {
      onStatusChanged!('CONNECTED');
    }
    return true;
  }
  
  @override
  Future<bool> stopVpn() async {
    _log('StubVpnImplementation: stopVpn() called');
    if (onStatusChanged != null) {
      onStatusChanged!('DISCONNECTED');
    }
    return true;
  }
  
  @override
  Future<Map<String, dynamic>> parseConfigFromURL(String url) async {
    _log('StubVpnImplementation: parseConfigFromURL() called with URL: $url');
    return {
      'remark': 'Stub Config',
      'config': '{}',
    };
  }
}

// Implementation for Windows platform using SingBox
class WindowsVpnImplementation implements VpnImplementation {
  final Function(dynamic)? onStatusChanged;

  WindowsVpnImplementation({this.onStatusChanged});
  
  @override
  Future<bool> initialize() async {
    _log('WindowsVpnImplementation: initialize() called');
    return true;
  }
  
  @override
  Future<bool> requestPermission() async {
    _log('WindowsVpnImplementation: requestPermission() called');
    return true;
  }
  
  @override
  Future<bool> startVpn({
    required String serverConfig,
    String? remark,
    dynamic blockedApps,
    dynamic bypassSubnets,
    bool proxyOnly = false,
  }) async {
    _log('WindowsVpnImplementation: startVpn() called with config: $serverConfig');
    // Implementation will use the platform channel
    // The actual SingBox starting is handled in the core.dart file
    if (onStatusChanged != null) {
      onStatusChanged!('CONNECTING');
    }
    return true;
  }
  
  @override
  Future<bool> stopVpn() async {
    _log('WindowsVpnImplementation: stopVpn() called');
    // Implementation will use the platform channel
    // The actual SingBox stopping is handled in the core.dart file
    if (onStatusChanged != null) {
      onStatusChanged!('DISCONNECTED');
    }
    return true;
  }
  
  @override
  Future<Map<String, dynamic>> parseConfigFromURL(String url) async {
    _log('WindowsVpnImplementation: parseConfigFromURL() called with URL: $url');
    return {
      'remark': 'Windows Config',
      'config': '{}',
    };
  }
}
