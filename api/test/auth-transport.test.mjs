import test from 'node:test';
import assert from 'node:assert/strict';
import azureFunctions from '@azure/functions';
import { requestBearer } from '../src/auth-transport.mjs';
const { HttpRequest } = azureFunctions;

const request = headers => new HttpRequest({ url: 'https://example.invalid/api/sync', method: 'GET', headers });
test('only the explicit Bloomstep transport supplies the broker bearer token', () => {
  assert.equal(requestBearer(request({
    'X-Bloomstep-Authorization': 'Bearer actual-broker-token',
    Authorization: 'Bearer overwritten-platform-token',
    'x-ms-client-principal': 'untrusted-platform-identity',
  })), 'actual-broker-token');
  assert.equal(requestBearer(request({ 'x-bloomstep-authorization': 'Bearer actual-broker-token' })), 'actual-broker-token');
});
test('platform Authorization/principal headers never substitute for the explicit token', () => {
  for (const headers of [
    {}, { Authorization: 'Bearer platform-token' }, { 'x-ms-client-principal': 'platform' },
    { 'X-Bloomstep-Authorization': '' }, { 'X-Bloomstep-Authorization': 'Basic token' },
    { 'X-Bloomstep-Authorization': 'Bearer ' }, { 'X-Bloomstep-Authorization': 'bearer token' },
    { 'X-Bloomstep-Authorization': 'Bearer one, Bearer two' },
    { 'X-Bloomstep-Authorization': 'Bearer two tokens' },
  ]) assert.throws(() => requestBearer(request(headers)), error => error.status === 401);
});
