#include "toast_history.h"

#include <windows.h>
#include <shobjidl.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>

namespace {
constexpr auto kAppId = L"Budlark.Garden";
constexpr auto kActivator = L"{dc9b4d34-b0de-4df7-aead-690d8a5304a2}";

struct RegistryKey {
  HKEY value = nullptr;
  ~RegistryKey() {
    if (value) RegCloseKey(value);
  }
};

void RegisterAppIdentity() {
  // Match flutter_local_notifications_windows' identity/activator metadata,
  // without changing any Windows notification permission.
  RegistryKey key;
  winrt::check_win32(RegCreateKeyExW(
      HKEY_CURRENT_USER, L"Software\\Classes\\AppUserModelId\\Budlark.Garden",
      0, nullptr, 0, KEY_SET_VALUE, nullptr, &key.value, nullptr));
  const auto write = [&key](const wchar_t* name, const std::wstring& value) {
    winrt::check_win32(RegSetValueExW(
        key.value, name, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))));
  };
  std::wstring executable(32768, L'\0');
  const auto length = GetModuleFileNameW(
      nullptr, executable.data(), static_cast<DWORD>(executable.size()));
  if (length == 0) winrt::throw_last_error();
  if (length >= executable.size()) {
    winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER));
  }
  executable.resize(length);
  const auto directory = executable.substr(0, executable.find_last_of(L"\\/"));
  write(L"DisplayName", L"Budlark");
  write(L"IconUri",
        directory + L"\\data\\flutter_assets\\windows\\runner\\resources\\app_icon.ico");
  write(L"CustomActivator", kActivator);
  winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(kAppId));
}
}  // namespace

ToastHistory::ToastHistory(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "budlark/toast_history",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "getHistory" && call.method_name() != "cancel" &&
            call.method_name() != "getSetting" && call.method_name() != "show" &&
            call.method_name() != "registerApp") {
          result->NotImplemented();
          return;
        }
        int32_t id = 0;
        std::string xml;
        if (call.method_name() == "cancel" || call.method_name() == "show") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          const auto expected = call.method_name() == "show" ? 2u : 1u;
          if (!arguments || arguments->size() != expected) {
            result->Error("invalid_notification", "A notification ID is required.");
            return;
          }
          const auto entry = arguments->find(flutter::EncodableValue("id"));
          const auto* value = entry == arguments->end()
                                  ? nullptr : std::get_if<int32_t>(&entry->second);
          if (!value || *value < 1) {
            result->Error("invalid_notification", "A positive notification ID is required.");
            return;
          }
          id = *value;
          if (call.method_name() == "show") {
            const auto content = arguments->find(flutter::EncodableValue("xml"));
            const auto* text = content == arguments->end()
                                   ? nullptr : std::get_if<std::string>(&content->second);
            if (!text || text->empty() || text->size() > 16384) {
              result->Error("invalid_notification", "Safe notification XML is required.");
              return;
            }
            xml = *text;
          }
        }
        try {
          if (!runtime_initialized_) {
            winrt::init_apartment(winrt::apartment_type::single_threaded);
            runtime_initialized_ = true;
          }
          constexpr auto app = kAppId;
          winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(app));
          if (call.method_name() == "registerApp") {
            RegisterAppIdentity();
            result->Success();
            return;
          }
          if (call.method_name() == "getSetting") {
            const auto notifier =
                winrt::Windows::UI::Notifications::ToastNotificationManager::CreateToastNotifier(app);
            result->Success(flutter::EncodableValue(
                static_cast<int32_t>(notifier.Setting())));
            return;
          }
          // Explicit AUMID overloads work without MSIX package identity.
          constexpr auto group = L"Budlark";
          if (call.method_name() == "cancel") {
            const auto history =
                winrt::Windows::UI::Notifications::ToastNotificationManager::History();
            history.Remove(winrt::to_hstring(id), group, app);
            result->Success();
          } else if (call.method_name() == "show") {
            using namespace winrt::Windows::UI::Notifications;
            const auto notifier = ToastNotificationManager::CreateToastNotifier(app);
            if (notifier.Setting() != NotificationSetting::Enabled) {
              result->Error("notifications_disabled", "Windows notifications are disabled.");
              return;
            }
            winrt::Windows::Data::Xml::Dom::XmlLoadSettings settings;
            settings.ProhibitDtd(true);
            settings.MaxElementDepth(20);
            winrt::Windows::Data::Xml::Dom::XmlDocument document;
            document.LoadXml(winrt::to_hstring(xml), settings);
            ToastNotification notification(document);
            notification.Tag(winrt::to_hstring(id));
            notification.Group(group);
            notifier.Show(notification);
            result->Success();
          } else {
            const auto history =
                winrt::Windows::UI::Notifications::ToastNotificationManager::History();
            flutter::EncodableList tags;
            for (const auto& notification : history.GetHistory(app)) {
              tags.emplace_back(winrt::to_string(notification.Tag()));
            }
            result->Success(flutter::EncodableValue(tags));
          }
        } catch (const winrt::hresult_error& error) {
          const auto registration = call.method_name() == "registerApp";
          result->Error(
              registration ? "notification_registration_failed" : "history_unavailable",
              registration
                  ? "Windows could not register Budlark for notifications. "
                    "Reminders remain inactive. Repair or reinstall Budlark, then retry."
                  : "Windows could not complete the notification operation. "
                    "Review Windows Settings > System > Notifications, then retry.",
              flutter::EncodableValue(static_cast<int32_t>(error.code())));
        }
      });
}

ToastHistory::~ToastHistory() {
  if (runtime_initialized_) winrt::uninit_apartment();
}
