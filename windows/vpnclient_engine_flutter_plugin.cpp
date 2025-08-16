#include "vpnclient_engine_flutter_plugin.h"

#include <iostream>
#include <fstream>
// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

// Include sing-box related headers (replace with actual headers if different)
#include <string>


#pragma comment(lib, "ws2_32.lib")

namespace vpnclient_engine_flutter {

// static
void VpnclientEngineFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "vpnclient_engine_flutter",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<VpnclientEngineFlutterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

VpnclientEngineFlutterPlugin::VpnclientEngineFlutterPlugin() {}


bool VpnclientEngineFlutterPlugin::startSingBox(std::string configPath) {
  std::cout << "Start SingBox with config: " << configPath << std::endl;

  // Check if the configuration file exists
  std::ifstream configFile(configPath);
  if (!configFile.good()) {
    std::cerr << "Error: Configuration file not found at " << configPath << std::endl;
    return false;
  }
  configFile.close();
  
  // First, check if SingBox is already running and terminate it
  system("taskkill /F /IM sing-box.exe 2>NUL");
  
  // Try to find sing-box in the application directory first
  std::string exePath = "sing-box.exe";
  std::string applicationDir = "";
  
  // Get the application directory
  char buffer[MAX_PATH];
  GetModuleFileNameA(NULL, buffer, MAX_PATH);
  std::string::size_type pos = std::string(buffer).find_last_of("\\/");
  if (pos != std::string::npos) {
    applicationDir = std::string(buffer).substr(0, pos);
    
    // Check if sing-box exists in the application directory
    std::string localExePath = applicationDir + "\\sing-box.exe";
    std::ifstream exeFile(localExePath);
    if (exeFile.good()) {
      exePath = localExePath;
      exeFile.close();
    }
  }
  
  // Build the command to run sing-box with the configuration file
  std::string command = "\"" + exePath + "\" run -c \"" + configPath + "\"";
  std::cout << "Executing command: " << command << std::endl;

  // Use CREATE_NO_WINDOW to hide the console window
  STARTUPINFOA startupInfo;
  PROCESS_INFORMATION processInfo;

  ZeroMemory(&startupInfo, sizeof(startupInfo));
  startupInfo.cb = sizeof(startupInfo);
  ZeroMemory(&processInfo, sizeof(processInfo));

  if (CreateProcessA(NULL, (LPSTR)command.c_str(), NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &startupInfo, &processInfo)) {
      // Keep process handle for later termination but close the thread handle
      CloseHandle(processInfo.hThread);
      std::cout << "sing-box launched successfully." << std::endl;
      return true;
  } else {
      DWORD error = GetLastError();
      std::cerr << "Failed to start sing-box. Error code: " << error << std::endl;
      
      // If the error is file not found, try to find sing-box in PATH
      if (error == ERROR_FILE_NOT_FOUND) {
          std::cerr << "sing-box.exe not found in application directory. " 
                    << "Make sure sing-box.exe is in your PATH or in the same directory as your application." << std::endl;
      }
      
      return false;
  }
}

VpnclientEngineFlutterPlugin::~VpnclientEngineFlutterPlugin() {}

void VpnclientEngineFlutterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("startSingBox") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
        auto configPathIt = arguments->find(flutter::EncodableValue("configPath"));
        if (configPathIt != arguments->end()) {
            std::string configPath = std::get<std::string>(configPathIt->second);
            bool success = startSingBox(configPath);
            result->Success(flutter::EncodableValue(success));
            return;
        }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid arguments for startSingBox");
  } else if (method_call.method_name().compare("stopSingBox") == 0) {
    // Terminate sing-box process
    system("taskkill /F /IM sing-box.exe");
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

}  // namespace vpnclient_engine_flutter
