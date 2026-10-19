import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('native reminder registration adds identity metadata, never notification permissions', () => {
  const native = read('windows/runner/toast_history.cpp');
  assert.match(native, /RegCreateKeyExW/);
  assert.match(native, /Classes\\\\AppUserModelId\\\\Budlark\.Garden/);
  for (const field of ['DisplayName', 'IconUri', 'CustomActivator']) {
    assert.ok(native.includes(`L"${field}"`), field);
  }
  assert.doesNotMatch(native, /PushNotifications|Policies|ToastEnabled|Enabled",/);
  assert.match(native, /notification_registration_failed/);
});

test('registration and Windows availability precede plugin callback initialization', () => {
  const dart = read('lib/services/desktop_reminders.dart');
  const start = dart.indexOf('class WindowsReminderGateway');
  const init = dart.slice(start, dart.indexOf('Future<void> show(', start));
  assert.ok(init.indexOf('WindowsToastHistory.registerApp()') >= 0);
  assert.ok(init.indexOf('WindowsToastHistory.registerApp()') < init.indexOf('WindowsToastHistory.requireEnabled()'));
  assert.ok(init.indexOf('WindowsToastHistory.requireEnabled()') < init.indexOf('notifications.initialize('));
});

test('notification settings lookup does not require toast history support', () => {
  const native = read('windows/runner/toast_history.cpp');
  assert.ok(native.indexOf('call.method_name() == "getSetting"') < native.indexOf('::History()'));
});

test('installed shortcut and both native adapters use one AUMID and activator', () => {
  const native = read('windows/runner/toast_history.cpp');
  const dart = read('lib/services/desktop_reminders.dart');
  const installer = read('packaging/budlark.iss');
  const appId = 'Budlark.Garden';
  const activator = 'dc9b4d34-b0de-4df7-aead-690d8a5304a2';
  assert.ok(native.includes(`L"${appId}"`));
  assert.ok(native.includes(`L"{${activator}}"`));
  assert.ok(dart.includes(`appUserModelId: '${appId}'`));
  assert.ok(dart.includes(`guid: '${activator}'`));
  assert.ok(installer.includes(`AppUserModelID: "${appId}"`));
  assert.ok(installer.includes(`AppUserModelToastActivatorCLSID: "${activator}"`));
});

test('reminder failures retain a visible cause and open only Windows notification settings', () => {
  const dart = read('lib/services/desktop_reminders.dart');
  assert.match(dart, /String\? unavailableReason/);
  assert.match(dart, /unavailableReason = null/);
  assert.match(dart, /Future<void> openNotificationSettings/);
  assert.match(read('lib/services/windows_toast_history.dart'), /ms-settings:notifications/);
  assert.match(read('lib/services/windows_toast_history.dart'), /LaunchMode\.externalApplication/);
});
