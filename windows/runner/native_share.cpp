#include "native_share.h"

#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <winrt/Windows.Foundation.h>

using winrt::Windows::ApplicationModel::DataTransfer::DataRequestedEventArgs;
using winrt::Windows::ApplicationModel::DataTransfer::DataTransferManager;
using winrt::Windows::Foundation::Uri;

NativeShare::NativeShare(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "bloomstep/native_share",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "share") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!arguments || arguments->size() != 3) {
          result->Error("invalid_share", "A complete safe invitation is required.");
          return;
        }
        auto text = [arguments](const char* key) -> const std::string* {
          auto value = arguments->find(flutter::EncodableValue(key));
          return value == arguments->end() ? nullptr
                                          : std::get_if<std::string>(&value->second);
        };
        const auto* url = text("url");
        const auto* title = text("title");
        const auto* description = text("description");
        if (!url || !title || !description || url->rfind("https://", 0) != 0 ||
            url->size() > 2048 || url->find_first_of("\r\n") != std::string::npos ||
            title->empty() || title->size() > 120 || description->size() > 300) {
          result->Error("invalid_share", "The invitation is outside safe sharing limits.");
          return;
        }
        if (!IsWindowVisible(window_) || GetForegroundWindow() != window_) {
          result->Error(
              "share_foreground_required",
              "Bring Bloomstep to the foreground and choose Windows share again.");
          return;
        }
        try {
          if (!runtime_initialized_) {
            winrt::init_apartment(winrt::apartment_type::single_threaded);
            runtime_initialized_ = true;
          }
          auto interop = winrt::get_activation_factory<DataTransferManager,
                                                       IDataTransferManagerInterop>();
          if (!manager_) {
            winrt::check_hresult(interop->GetForWindow(
                window_, winrt::guid_of<DataTransferManager>(),
                winrt::put_abi(manager_)));
            requested_ = manager_.DataRequested(
                [this](const DataTransferManager&, const DataRequestedEventArgs& args) {
                  auto request = args.Request();
                  try {
                    auto package = request.Data();
                    package.Properties().Title(winrt::to_hstring(title_));
                    package.Properties().Description(winrt::to_hstring(description_));
                    package.SetWebLink(Uri(winrt::to_hstring(url_)));
                  } catch (const winrt::hresult_error&) {
                    request.FailWithDisplayText(
                        L"Bloomstep could not prepare the invitation. Open the app and try again.");
                  }
                });
          }
          url_ = *url;
          title_ = *title;
          description_ = *description;
          winrt::check_hresult(interop->ShowShareUIForWindow(window_));
          result->Success();
        } catch (const winrt::hresult_error& error) {
          result->Error("share_unavailable",
                        "Windows could not open its sharing surface.",
                        flutter::EncodableValue(static_cast<int32_t>(error.code())));
        }
      });
}

NativeShare::~NativeShare() {
  if (manager_) {
    try {
      manager_.DataRequested(requested_);
    } catch (const winrt::hresult_error&) {
      OutputDebugStringW(L"Bloomstep: share event cleanup failed during shutdown.\n");
    }
    manager_ = nullptr;
  }
  if (runtime_initialized_) winrt::uninit_apartment();
}
