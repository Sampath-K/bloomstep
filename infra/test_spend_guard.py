import unittest
import base64
import contextlib
import io
import json
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs
from spend_guard import evaluate, actual_cost, run


class SpendGuardTests(unittest.TestCase):
    def fixture(self):
        return {
            "subscription": {"subscriptionPolicies": {"quotaId": "FreeTrial_2014-09-01", "spendingLimit": "On"}},
            "swa": {"sku": {"name": "Free"}},
            "cosmos": {"properties": {"enableFreeTier": True, "locations": [{}], "capabilities": []}},
            "throughputs": [{"properties": {"resource": {"throughput": 400}}}],
            "customerDirectoryName": "bloomstepcustomers261004",
            "customerDirectory": {"name": "bloomstepcustomers261004", "sku": {"name": "Base", "tier": "A0"}},
            "inventory": ["Microsoft.Web/staticSites", "Microsoft.DocumentDB/databaseAccounts", "Microsoft.AzureActiveDirectory/ciamDirectories"],
        }

    def test_unknown_cost_never_zero_or_fake_success(self):
        result = evaluate(self.fixture(), None)
        self.assertIsNone(result["cost"])
        self.assertIsNone(result["pauseReason"])
        self.assertEqual(result["status"], "warning_cost_unknown")
        self.assertIn("not a hard cap", result["warning"])

    def test_positive_and_zero_cost_distinct(self):
        self.assertEqual(evaluate(self.fixture(), 0.01)["pauseReason"], "positive_cost")
        self.assertEqual(evaluate(self.fixture(), 0)["status"], "verified_zero_cost_current_query")

    def test_free_sku_or_trial_limit_drift_pauses(self):
        for field, value in [("swa", {"sku": {"name": "Standard"}}),
                             ("cosmos", {"properties": {"enableFreeTier": False}}),
                             ("throughputs", [{"properties": {"resource": {"throughput": 1000}}}]),
                             ("inventory", ["Microsoft.Compute/virtualMachines"])]:
            data = self.fixture()
            data[field] = value
            self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = self.fixture()
        data["subscription"]["subscriptionPolicies"]["spendingLimit"] = "Off"
        self.assertEqual(evaluate(data, None)["pauseReason"], "spending_limit_off")
        data = self.fixture()
        data["subscription"]["subscriptionPolicies"]["quotaId"] = "unknown"
        self.assertEqual(evaluate(data, None)["pauseReason"], "configuration_unknown")

    def test_cost_management_empty_gtm_or_malformed_is_unknown(self):
        for value in [{}, {"properties": {"columns": [], "rows": []}},
                      {"properties": {"columns": [{"name": "PreTaxCost"}], "rows": []}}]:
            self.assertIsNone(actual_cost(value))

        value = {"properties": {"columns": [{"name": "PreTaxCost"}, {"name": "Currency"}], "rows": [[0.1, "USD"]]}}
        self.assertEqual(actual_cost(value), 0.1)
        value["properties"]["rows"] = [[-1, "USD"]]
        self.assertIsNone(actual_cost(value))

    def test_actual_three_resource_inventory_allows_only_pinned_base_a0_customer_directory(self):
        self.assertEqual(evaluate(self.fixture(), None)["status"], "warning_cost_unknown")
        for directory in [
            {"name": "othercustomer", "sku": {"name": "Base", "tier": "A0"}},
            {"name": "bloomstepcustomers261004", "sku": {"name": "Premium", "tier": "P1"}},
            {"name": "bloomstepcustomers261004", "sku": {"name": "Base", "tier": "A1"}},
            {},
        ]:
            data = self.fixture()
            data["customerDirectory"] = directory
            self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = self.fixture()
        data["inventory"].append("Microsoft.AzureActiveDirectory/ciamDirectories")
        self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")

    def test_additional_static_sites_allowed_only_when_each_verified_free_and_bounded(self):
        def with_extras(*skus):
            data = self.fixture()
            data["inventory"] += ["Microsoft.Web/staticSites"] * len(skus)
            data["additionalStaticSites"] = [{"name": f"extra{i}", "sku": sku} for i, sku in enumerate(skus)]
            return data
        self.assertIsNone(evaluate(with_extras({"name": "Free"}), None)["pauseReason"])
        self.assertEqual(evaluate(with_extras({"name": "Free"}), 0)["status"], "verified_zero_cost_current_query")
        self.assertIsNone(evaluate(with_extras(*[{"name": "Free"}] * 3), None)["pauseReason"])
        for skus in [[{"name": "Standard"}], [{"name": "Dedicated"}], [{}], [None], [{"name": "free"}],
                     [{"name": "Free"}, {"name": "Standard"}], [{"name": "Free"}] * 4]:
            self.assertEqual(evaluate(with_extras(*skus), None)["pauseReason"], "paid_sku", skus)
        data = with_extras({"name": "Free"})
        data["additionalStaticSites"].append({"name": "unlisted", "sku": {"name": "Free"}})
        self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = with_extras({"name": "Free"})
        data["additionalStaticSites"] = []
        self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = with_extras({"name": "Free"})
        data["additionalStaticSites"] = "Free"
        self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = with_extras({"name": "Free"})
        data["inventory"].append("Microsoft.Web/sites")
        self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = with_extras({"name": "Free"})
        data["swa"] = {"sku": {"name": "Standard"}}
        self.assertEqual(evaluate(data, None)["pauseReason"], "paid_sku")
        data = with_extras({"name": "Free"})
        data["subscription"]["subscriptionPolicies"]["spendingLimit"] = "Off"
        self.assertEqual(evaluate(data, None)["pauseReason"], "spending_limit_off")
        self.assertEqual(evaluate(with_extras({"name": "Free"}), 0.01)["pauseReason"], "positive_cost")

    def transport(self, cost=None, sku="Free", invalid_subject=False, extra_swas=()):
            requests = []
            tenant = "22222222-2222-4222-8222-222222222222"
            subscription = "11111111-1111-4111-8111-111111111111"
            client = "44444444-4444-4444-8444-444444444444"
            env = {
                "GUARD_TENANT_ID": tenant, "GUARD_CLIENT_ID": client, "GUARD_SUBSCRIPTION_ID": subscription,
                "GUARD_RESOURCE_GROUP": "mock", "GUARD_SWA_NAME": "mock", "GUARD_COSMOS_NAME": "mockcosmos",
                "GUARD_CUSTOMER_DIRECTORY_NAME": "bloomstepcustomers261004",
                "API_ORIGIN": "https://mock.azurestaticapps.net", "GITHUB_REPOSITORY": "Sampath-K/bloomstep",
                "GITHUB_REPOSITORY_ID": "1404357574", "GITHUB_REPOSITORY_OWNER_ID": "72682617",
                "ACTIONS_ID_TOKEN_REQUEST_URL": "https://github.invalid/assertion?x=1",
                "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "offline-request-token", "GITHUB_RUN_ID": "123",
            }
            subject = "repo:Sampath-K@72682617/bloomstep@1404357574:environment:bloomstep-operations"
            claims = {"iss": "https://token.actions.githubusercontent.com", "aud": "api://AzureADTokenExchange",
                      "sub": "wrong-subject" if invalid_subject else subject}
            assertion = "fixture." + base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=") + ".fixture"

            class Response(io.BytesIO):
                def __init__(self, data):
                    super().__init__(json.dumps(data).encode())
                    self.status = 200

            class Opener:
                def open(inner, req, timeout):
                    requests.append(req)
                    url = req.full_url
                    if "github.invalid" in url:
                        return Response({"value": assertion})
                    if "/oauth2/" in url:
                        scope = parse_qs(req.data.decode())["scope"][0]
                        return Response({"access_token": "offline-arm-token" if "management.azure" in scope else "offline-api-token"})
                    if "operational-pause" in url:
                        self.assertIsNone(req.get_header("Authorization"))
                        self.assertEqual(req.get_header("X-bloomstep-authorization"), "Bearer offline-api-token")
                        self.assertIn(json.loads(req.data)["reason"], ("paid_sku", "positive_cost", "configuration_unknown"))
                        return Response({"paused": True})
                    self.assertNotIn("listKeys", url)
                    self.assertNotIn("/config/", url)
                    if "Microsoft.CostManagement/query" in url:
                        if cost is None:
                            raise HTTPError(url, 404, "GtmDimension empty", {}, None)
                        return Response({"properties": {"columns": [{"name": "PreTaxCost"}], "rows": [[cost]]}})
                    if "/resources?" in url:
                        rows = [{"type": kind, "name": "mock" if kind.endswith("staticSites") else "other"}
                                for kind in self.fixture()["inventory"]]
                        return Response({"value": rows + [{"type": "Microsoft.Web/staticSites", "name": name}
                                                          for name, _ in extra_swas]})
                    if "/staticSites/" in url:
                        site = url.split("/staticSites/")[1].split("?")[0]
                        if site == "mock":
                            return Response({"sku": {"name": sku}})
                        extra = dict(extra_swas)[site]
                        if isinstance(extra, Exception):
                            raise extra
                        return Response({"name": site, "sku": {"name": extra}})
                    if "/ciamDirectories/" in url:
                        return Response(self.fixture()["customerDirectory"])
                    if "/throughputSettings/" in url:
                        if "/containers/" not in url:
                            raise HTTPError(url, 404, "No shared throughput", {}, None)
                        return Response({"properties": {"resource": {"throughput": 400}}})
                    if "/sqlDatabases?" in url:
                        return Response({"value": [{"name": "bloomstep"}]})
                    if "/containers?" in url:
                        return Response({"value": [{"name": "data"}]})
                    if "/databaseAccounts/" in url:
                        return Response(self.fixture()["cosmos"])
                    return Response({**self.fixture()["subscription"], "tenantId": tenant, "subscriptionId": subscription})

            output = io.StringIO()
            with patch.dict("os.environ", env, clear=True), patch("spend_guard.build_opener", return_value=Opener()), contextlib.redirect_stdout(output):
                if invalid_subject:
                    with self.assertRaises(ValueError):
                        run()
                else:
                    run()
            return requests, output.getvalue()

    def test_runtime_new_subscription_404_warns_and_does_not_pause_or_invent_zero(self):
            requests, output = self.transport()
            self.assertIn('"cost": null', output)
            self.assertIn("unknown, NOT zero", output)
            self.assertFalse(any("operational-pause" in req.full_url for req in requests))

    def test_runtime_positive_cost_and_paid_sku_request_only_one_way_pause(self):
            for cost, sku in [(0.01, "Free"), (None, "Standard")]:
                requests, output = self.transport(cost, sku)
                self.assertEqual(sum("operational-pause" in req.full_url for req in requests), 1)
                self.assertIn("pause confirmed", output)
                self.assertFalse(any("/api/team/" in req.full_url or "/api/sync" in req.full_url for req in requests))

    def test_runtime_rejects_legacy_or_untrusted_subject_before_token_exchange(self):
            requests, _ = self.transport(invalid_subject=True)
            self.assertEqual(len(requests), 1)

    def test_runtime_reads_each_additional_static_site_sku_read_only(self):
            requests, output = self.transport(extra_swas=[("bloomstep-analytics-staging", "Free")])
            self.assertIn('"pauseReason": null', output)
            self.assertFalse(any("operational-pause" in req.full_url for req in requests))
            self.assertEqual(sum("/staticSites/bloomstep-analytics-staging?" in req.full_url for req in requests), 1)
            self.assertTrue(all(req.data is None for req in requests if "/staticSites/" in req.full_url))
            for extras, reason in [([("paid-site", "Standard")], "paid_sku"),
                                   ([("unreadable", HTTPError("u", 403, "Forbidden", {}, None))], "configuration_unknown"),
                                   ([(f"free{i}", "Free") for i in range(4)], "configuration_unknown")]:
                requests, output = self.transport(extra_swas=extras)
                self.assertIn(f'"pauseReason": "{reason}"', output)
                self.assertEqual(sum("operational-pause" in req.full_url for req in requests), 1)


if __name__ == "__main__":
    unittest.main()
