#include "toast_history.h"

#include <windows.h>
#include <shobjidl.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>

ToastHistory::ToastHistory(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "bloomstep/toast_history",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "getHistory" && call.method_name() != "cancel" &&
            call.method_name() != "getSetting" && call.method_name() != "show") {
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
          constexpr auto app = L"Bloomstep.Garden";
          winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(app));
          const auto history =
              winrt::Windows::UI::Notifications::ToastNotificationManager::History();
          // Explicit AUMID overloads work without MSIX package identity.
          constexpr auto group = L"Bloomstep";
          if (call.method_name() == "cancel") {
            history.Remove(winrt::to_hstring(id), group, app);
            result->Success();
          } else if (call.method_name() == "getSetting") {
            const auto notifier =
                winrt::Windows::UI::Notifications::ToastNotificationManager::CreateToastNotifier(app);
            result->Success(flutter::EncodableValue(
                static_cast<int32_t>(notifier.Setting())));
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
            flutter::EncodableList tags;
            for (const auto& notification : history.GetHistory(app)) {
              tags.emplace_back(winrt::to_string(notification.Tag()));
            }
            result->Success(flutter::EncodableValue(tags));
          }
        } catch (const winrt::hresult_error& error) {
          result->Error(
              "history_unavailable", "The Windows notification operation failed.",
              flutter::EncodableValue(static_cast<int32_t>(error.code())));
        }
      });
}

ToastHistory::~ToastHistory() {
  if (runtime_initialized_) winrt::uninit_apartment();
}
