// Android-specific implementation
import 'dart:async';

// Import the actual FlutterV2ray package only on Android
import 'package:flutter_v2ray/flutter_v2ray.dart';

import '../platform_imports.dart';

class AndroidVpnImplementation implements VpnImplementation {
  final Function(dynamic)? onStatusChanged;
  late FlutterV2ray _v2rayImplementation;

  AndroidVpnImplementation({this.onStatusChanged}) {
    _v2rayImplementation = FlutterV2ray(
      onStatusChanged: onStatusChanged,
    );
  }

  @override
  Future<bool> initialize() async {
    try {
      return await _v2rayImplementation.initializeV2Ray();
    } catch (e) {
      print('Error initializing Android VPN: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _v2rayImplementation.requestPermission();
    } catch (e) {
      print('Error requesting permissions: $e');
      return false;
    }
  }

  @override
  Future<bool> startVpn({
    required String serverConfig,
    String? remark,
    dynamic blockedApps,
    dynamic bypassSubnets,
    bool proxyOnly = false,
  }) async {
    try {
      final parsed = await parseConfigFromURL(serverConfig);
      _v2rayImplementation.startV2Ray(
        remark: parsed['remark'] as String? ?? 'Default',
        config: parsed['config'] as String? ?? '{}',
        blockedApps: blockedApps,
        bypassSubnets: bypassSubnets,
        proxyOnly: proxyOnly,
      );
      return true;
    } catch (e) {
      print('Error starting Android VPN: $e');
      return false;
    }
  }

  @override
  Future<bool> stopVpn() async {
    try {
      _v2rayImplementation.stopV2Ray();
      return true;
    } catch (e) {
      print('Error stopping Android VPN: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> parseConfigFromURL(String url) async {
    try {
      final parser = FlutterV2ray.parseFromURL(url);
      return {
        'remark': parser.remark,
        'config': parser.getFullConfiguration(),
      };
    } catch (e) {
      print('Error parsing config: $e');
      return {
        'remark': 'Default',
        'config': '{}',
      };
    }
  }
}
