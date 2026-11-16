"""Inspect three public claims; never persist or print either bearer token."""
import base64
import json
import os
import sys
import urllib.parse
import urllib.request


def main():
    audience = "api://AzureADTokenExchange"
    parts = urllib.parse.urlsplit(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"])
    if parts.scheme != "https":
        raise ValueError("HTTPS required")
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    query = [(key, value) for key, value in query if key != "audience"]
    url = urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(query + [("audience", audience)])))
    request = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)["value"]
    encoded = token.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    if claims.get("iss") != "https://token.actions.githubusercontent.com" or claims.get("aud") != audience:
        raise ValueError("Unexpected issuer or audience")
    if not isinstance(claims.get("sub"), str) or not claims["sub"]:
        raise ValueError("Missing subject")
    # This inspection is not JWT signature validation or proof of Azure trust.
    print(json.dumps({key: claims[key] for key in ("iss", "aud", "sub")}, ensure_ascii=True))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("OIDC claim inspection failed. Check the environment and workflow permissions privately.", file=sys.stderr)
        sys.exit(1)
