"""Lambda handler — proxy openCypher queries to Neptune with SigV4 signing."""

import json
import os
import ssl
import urllib.parse
import urllib.request

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

NEPTUNE_ENDPOINT = os.environ["NEPTUNE_ENDPOINT"]
NEPTUNE_PORT = os.environ.get("NEPTUNE_PORT", "8182")
REGION = os.environ.get("AWS_REGION", "us-east-1")

_URL = f"https://{NEPTUNE_ENDPOINT}:{NEPTUNE_PORT}/openCypher"
_SSL_CTX = ssl.create_default_context()


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except (json.JSONDecodeError, TypeError):
        return _response(400, {"error": "Invalid JSON body"})

    query = body.get("query", "").strip()
    if not query:
        return _response(400, {"error": "Missing 'query' field"})

    parameters = body.get("parameters") or {}

    form_body = urllib.parse.urlencode({
        "query": query,
        "parameters": json.dumps(parameters),
    })
    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    creds = boto3.Session().get_credentials().get_frozen_credentials()
    aws_req = AWSRequest(method="POST", url=_URL, data=form_body, headers=headers)
    SigV4Auth(creds, "neptune-db", REGION).add_auth(aws_req)

    req = urllib.request.Request(
        _URL,
        data=form_body.encode(),
        headers=dict(aws_req.headers),
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=25, context=_SSL_CTX) as resp:
            result = json.loads(resp.read().decode())
        return _response(200, result)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()[:500] if exc.fp else str(exc)
        return _response(exc.code, {"error": f"Neptune HTTP {exc.code}: {detail}"})
    except urllib.error.URLError as exc:
        return _response(502, {"error": f"Cannot reach Neptune: {exc.reason}"})


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
