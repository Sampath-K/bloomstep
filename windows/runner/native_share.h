#ifndef RUNNER_NATIVE_SHARE_H_
#define RUNNER_NATIVE_SHARE_H_

#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>

#include <memory>
#include <string>

class NativeShare {
 public:
  NativeShare(flutter::BinaryMessenger* messenger, HWND window);
  ~NativeShare();

 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::ApplicationModel::DataTransfer::DataTransferManager manager_{nullptr};
  winrt::event_token requested_{};
  bool runtime_initialized_ = false;
  std::string url_;
  std::string title_;
  std::string description_;
};

#endif
