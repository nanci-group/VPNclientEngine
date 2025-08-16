#ifndef FLUTTER_PLUGIN_VPNCLIENT_ENGINE_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_VPNCLIENT_ENGINE_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace vpnclient_engine_flutter {

class VpnclientEngineFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  VpnclientEngineFlutterPlugin();

  virtual ~VpnclientEngineFlutterPlugin();

  // Disallow copy and assign.
  VpnclientEngineFlutterPlugin(const VpnclientEngineFlutterPlugin&) = delete;
  VpnclientEngineFlutterPlugin& operator=(const VpnclientEngineFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
      
 private:
  // SingBox related methods
  bool startSingBox(std::string configPath);
};

}  // namespace vpnclient_engine_flutter

#endif  // FLUTTER_PLUGIN_VPNCLIENT_ENGINE_FLUTTER_PLUGIN_H_
