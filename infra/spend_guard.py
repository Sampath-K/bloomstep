"""Bounded, read-only Azure inspection; one-way authenticated API pause."""
import base64
import json
import math
import os
import re
import uuid
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit, quote
from urllib.request import Request, build_opener, HTTPRedirectHandler


def actual_cost(data):
    props = data.get("properties", {})
    columns, rows = props.get("columns", []), props.get("rows", [])
    indexes = [i for i, column in enumerate(columns) if column.get("name") in ("PreTaxCost", "Cost")]
    if len(indexes) != 1 or not rows or len(rows) > 100:
        return None
    try:
        values = [float(row[indexes[0]]) for row in rows]
        if any(not math.isfinite(value) or value < 0 for value in values):
            return None
        return sum(values)
    except (ValueError, TypeError, IndexError):
        return None


def evaluate(data, cost):
    policy = data.get("subscription", {}).get("subscriptionPolicies", {})
    reason = None
    if str(policy.get("spendingLimit", "")).lower() == "off":
        reason = "spending_limit_off"
    elif policy.get("quotaId") != "FreeTrial_2014-09-01" or str(policy.get("spendingLimit", "")).lower() != "on":
        reason = "configuration_unknown"
    cosmos = data.get("cosmos", {}).get("properties", {})
    throughputs = data.get("throughputs", [])
    inventory = [kind.lower() for kind in data.get("inventory", [])]
    directory = data.get("customerDirectory", {})
    directory_name = data.get("customerDirectoryName")
    if (data.get("swa", {}).get("sku", {}).get("name") != "Free" or
        cosmos.get("enableFreeTier") is not True or len(cosmos.get("locations", [])) != 1 or
        cosmos.get("enableAnalyticalStorage") is True or cosmos.get("backupPolicy", {}).get("type") == "Continuous" or
        any(cap.get("name") == "EnableServerless" for cap in cosmos.get("capabilities", [])) or
        not throughputs or len(throughputs) != 1 or
        any(item.get("properties", {}).get("resource", {}).get("throughput") != 400 or
            item.get("properties", {}).get("resource", {}).get("autoscaleSettings") for item in throughputs) or
        not directory_name or directory.get("name") != directory_name or
        directory.get("sku", {}).get("name") != "Base" or directory.get("sku", {}).get("tier") != "A0" or
        sorted(inventory) != sorted(["microsoft.web/staticsites", "microsoft.documentdb/databaseaccounts",
                                     "microsoft.azureactivedirectory/ciamdirectories"])):
        reason = reason or "paid_sku"
    if cost is not None and cost > 0:
        reason = reason or "positive_cost"
    return {"status": "pause_required" if reason else
            "warning_cost_unknown" if cost is None else "verified_zero_cost_current_query",
            "pauseReason": reason, "cost": cost,
            "warning": "Cost is unknown, NOT zero; verified trial spending-limit/free SKUs are not a hard cap."
            if cost is None else "Cost is query-period evidence, not a future $0 guarantee."}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def run():
    opener = build_opener(NoRedirect)

    def call(url, token=None, data=None):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        with opener.open(Request(url, headers=headers, data=None if data is None else json.dumps(data).encode()), timeout=40) as response:
            raw = response.read(524289)
            if len(raw) > 524288:
                raise ValueError("Bounded response exceeded")
            return json.loads(raw)

    def mask(value):
        if not isinstance(value, str) or not value or "\n" in value or "\r" in value:
            raise ValueError("Invalid credential response")
        print("::add-mask::" + value, flush=True)
        return value

    guid = r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}"
    tenant, client, subscription = (os.environ.get(key, "") for key in
                                   ("GUARD_TENANT_ID", "GUARD_CLIENT_ID", "GUARD_SUBSCRIPTION_ID"))
    if not all(re.fullmatch(guid, value) for value in (tenant, client, subscription)):
        raise ValueError("Public guard identity configuration required")
    origin = os.environ["API_ORIGIN"].rstrip("/")
    parsed = urlsplit(origin)
    if parsed.scheme != "https" or not parsed.hostname or not parsed.hostname.endswith(".azurestaticapps.net") or parsed.path or parsed.query or parsed.fragment or parsed.username or parsed.password or parsed.port:
        raise ValueError("Pinned managed SWA origin required")
    repo, repo_id, owner_id = os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_REPOSITORY_ID"], os.environ["GITHUB_REPOSITORY_OWNER_ID"]
    owner, name = repo.split("/")
    subject = f"repo:{owner}@{owner_id}/{name}@{repo_id}:environment:bloomstep-operations"
    assertion_url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    assertion = mask(call(assertion_url + ("&" if "?" in assertion_url else "?") + urlencode({"audience": "api://AzureADTokenExchange"}),
                          os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"])["value"])
    encoded = assertion.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    if claims.get("sub") != subject or claims.get("iss") != "https://token.actions.githubusercontent.com" or claims.get("aud") != "api://AzureADTokenExchange":
        raise ValueError("Immutable repository/environment FIC assertion mismatch")

    def token(scope):
        form = urlencode({"client_id": client, "scope": scope, "grant_type": "client_credentials",
                          "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
                          "client_assertion": assertion}).encode()
        with opener.open(Request(f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
                                 data=form, headers={"Content-Type": "application/x-www-form-urlencoded"}), timeout=40) as response:
            raw = response.read(65537)
            if len(raw) > 65536:
                raise ValueError("Token response exceeds transport cap")
            return mask(json.loads(raw)["access_token"])

    arm_token = token("https://management.azure.com/.default")
    group = quote(os.environ["GUARD_RESOURCE_GROUP"], safe="")
    root = f"https://management.azure.com/subscriptions/{subscription}"
    rg = root + "/resourceGroups/" + group

    def arm(path, version, data=None):
        return call(path + "?api-version=" + version, arm_token, data)

    data = {}
    try:
        data["subscription"] = arm(root, "2022-12-01")
        if data["subscription"].get("tenantId") != tenant or data["subscription"].get("subscriptionId") != subscription:
            raise ValueError("Subscription binding mismatch")
        resources = arm(rg + "/resources", "2021-04-01")
        if resources.get("nextLink") or len(resources.get("value", [])) > 20:
            raise ValueError("Resource inventory cap")
        data["inventory"] = [row["type"] for row in resources["value"]]
        data["swa"] = arm(rg + "/providers/Microsoft.Web/staticSites/" + quote(os.environ["GUARD_SWA_NAME"], safe=""), "2023-12-01")
        data["customerDirectoryName"] = os.environ["GUARD_CUSTOMER_DIRECTORY_NAME"]
        data["customerDirectory"] = arm(rg + "/providers/Microsoft.AzureActiveDirectory/ciamDirectories/" +
                                        quote(data["customerDirectoryName"], safe=""), "2023-05-17-preview")
        account = rg + "/providers/Microsoft.DocumentDB/databaseAccounts/" + quote(os.environ["GUARD_COSMOS_NAME"], safe="")
        data["cosmos"] = arm(account, "2024-05-15")
        databases = arm(account + "/sqlDatabases", "2024-05-15")
        if databases.get("nextLink") or len(databases.get("value", [])) > 10:
            raise ValueError("Database inventory cap")
        data["throughputs"] = []
        for database in databases["value"]:
            db_path = account + "/sqlDatabases/" + quote(database["name"], safe="")
            for path in [db_path + "/throughputSettings/default"]:
                try:
                    data["throughputs"].append(arm(path, "2024-05-15"))
                except HTTPError as error:
                    if error.code != 404:
                        raise
            containers = arm(db_path + "/containers", "2024-05-15")
            if containers.get("nextLink") or len(containers.get("value", [])) > 20:
                raise ValueError("Container inventory cap")
            for container in containers["value"]:
                try:
                    data["throughputs"].append(arm(db_path + "/containers/" + quote(container["name"], safe="") + "/throughputSettings/default", "2024-05-15"))
                except HTTPError as error:
                    if error.code != 404:
                        raise
        config_known = True
    except (HTTPError, OSError, ValueError, KeyError):
        config_known = False
    try:
        cost = actual_cost(arm(rg + "/providers/Microsoft.CostManagement/query", "2023-03-01", {
            "type": "ActualCost", "timeframe": "MonthToDate",
            "dataset": {"granularity": "None", "aggregation": {"totalCost": {"name": "PreTaxCost", "function": "Sum"}}}}))
    except (HTTPError, OSError, ValueError):
        cost = None
    result = evaluate(data, cost) if config_known else {
        "status": "pause_required", "pauseReason": "configuration_unknown", "cost": cost,
        "warning": "Read-only configuration checks unavailable; not a verified free-tier pass."}
    print(json.dumps(result, sort_keys=True))
    if result["pauseReason"]:
        guard_token = token("api://" + client + "/.default")
        request_id = str(uuid.uuid5(uuid.NAMESPACE_URL, os.environ["GITHUB_RUN_ID"] + ":" + result["pauseReason"]))
        body = json.dumps({"requestId": request_id, "reason": result["pauseReason"]}).encode()
        with opener.open(Request(origin + "/api/internal/operational-pause", data=body,
                                 headers={"Content-Type": "application/json", "X-Bloomstep-Authorization": "Bearer " + guard_token}), timeout=40) as response:
            receipt = json.load(response)
            if receipt.get("paused") is not True:
                raise ValueError("Pause receipt not confirmed")
        print("Current application pause receipt: " + json.dumps({
            key: receipt.get(key) for key in ("requestId", "reason", "pausedAt")
        }, sort_keys=True))
        print("::warning::One-way application pause confirmed; human customer Admin review required.")
    elif cost is None:
        print("::warning::CostManagement is unavailable/empty (including new-subscription GtmDimension 404). Cost is unknown, NOT zero.")


if __name__ == "__main__":
    try:
        run()
    except Exception:
        print("::error::Spend guard failed; credentials/private responses omitted. Owner must review immediately.")
        raise SystemExit(1)
