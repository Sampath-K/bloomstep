#ifndef RUNNER_TOAST_HISTORY_H_
#define RUNNER_TOAST_HISTORY_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

class ToastHistory {
 public:
  explicit ToastHistory(flutter::BinaryMessenger* messenger);
  ~ToastHistory();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool runtime_initialized_ = false;
};

#endif
