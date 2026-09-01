#!/usr/bin/env bash
# Provision the "Forge" test account against an auth server.
#
# Forge is the identity automated tests and agents sign in as. It is an
# ordinary account created through the ordinary sign-up endpoint — there
# is no seeding path inside the server itself, deliberately: a binary
# that can mint a known-password account is a backdoor in every
# deployment of it, which is why Task's own `admin seed` is compiled out
# of release builds (PR #295).
#
# DEFAULTS TO LOCALHOST, and that is the recommended home for it. The
# production issuer is the identity root for Task, Session, Signal,
# Keyflow and Ignition; one leaked test password there is an account on
# all five. Point this at production only if you have decided that
# trade-off deliberately.
#
# Usage:
#   FORGE_PASSWORD='...' ./scripts/seed-test-user.sh
#   FORGE_PASSWORD='...' AUTH_URL=https://auth.fasttrackstudio.app ./scripts/seed-test-user.sh
#
# The password is read from the environment and never written to disk,
# never passed as an argument (argv is world-readable in /proc), and
# never echoed. Keep it in sops or your password manager, not here.
set -euo pipefail

AUTH_URL="${AUTH_URL:-http://127.0.0.1:8099}"
FORGE_EMAIL="${FORGE_EMAIL:-forge@fasttrackstudio.app}"
FORGE_NAME="${FORGE_NAME:-Forge}"

if [[ -z "${FORGE_PASSWORD:-}" ]]; then
  cat >&2 <<'USAGE'
FORGE_PASSWORD is not set.

Generate one and keep it somewhere durable:

    openssl rand -base64 24

then re-run with it in the environment:

    FORGE_PASSWORD='<the value>' ./scripts/seed-test-user.sh
USAGE
  exit 2
fi

# The server enforces this too; failing here gives a readable message
# instead of a 200-shaped rejection.
if (( ${#FORGE_PASSWORD} < 8 )); then
  echo "FORGE_PASSWORD must be at least 8 characters." >&2
  exit 2
fi

# POST json to an endpoint, printing the body whatever the status.
# Built with jq so a password containing quotes or backslashes cannot
# break out of the JSON.
post() {
  local endpoint="$1" body="$2"
  curl -sS --fail-with-body \
    -X POST "${AUTH_URL}${endpoint}" \
    -H 'content-type: application/json' \
    --data "$body" 2>/dev/null || true
}

credentials="$(
  jq -n --arg email "$FORGE_EMAIL" --arg password "$FORGE_PASSWORD" \
    '{email: $email, password: $password}'
)"

# Sign in FIRST, and that is what makes this idempotent.
#
# The obvious version — sign up, treat "already exists" as success —
# does not work: a duplicate address comes back as a generic
# `invalid_input`, indistinguishable from a malformed request, because
# the server declines to confirm which addresses have accounts. Signing
# in tests the thing a caller actually cares about anyway: not "does a
# row exist" but "do these credentials work".
echo "Checking for ${FORGE_EMAIL} at ${AUTH_URL}" >&2
response="$(post /auth/sign-in/email "$credentials")"

if [[ -z "$response" ]]; then
  echo "No response from ${AUTH_URL} — is the server running?" >&2
  exit 1
fi

user_id="$(jq -r '.user.id // empty' <<<"$response")"

if [[ -n "$user_id" ]]; then
  echo "${FORGE_EMAIL} already exists and the password is correct." >&2
else
  echo "Not found — creating." >&2
  new_account="$(
    jq -n \
      --arg email "$FORGE_EMAIL" \
      --arg password "$FORGE_PASSWORD" \
      --arg name "$FORGE_NAME" \
      '{email: $email, password: $password, name: $name}'
  )"
  response="$(post /auth/sign-up/email "$new_account")"
  user_id="$(jq -r '.user.id // empty' <<<"$response")"
fi

if [[ -z "$user_id" ]]; then
  # Most likely: the account exists with a DIFFERENT password, so
  # sign-in failed and sign-up refused the duplicate. Say so, because
  # the raw server error does not.
  cat >&2 <<'DIAG'
Could not sign in or create the account.

The usual cause is that it already exists with a different password —
sign-in was rejected and sign-up refused the duplicate. Either supply
the password it was created with, or delete the account and re-run.

Server said:
DIAG
  echo "$response" >&2
  exit 1
fi

echo >&2
echo "Principal id:" >&2
# The id alone on stdout, everything else on stderr, so a harness can do
#   principal=$(./scripts/seed-test-user.sh)
# without parsing prose.
echo "$user_id"
echo >&2
cat >&2 <<NEXT
Give it a membership row in each Task org it should reach — resolving a
token proves who, never where, so without this it authenticates fine and
still lands as anonymous:

    task-server admin adopt-principal \\
      --email ${FORGE_EMAIL} --principal ${user_id}

adopt-principal only adopts orgs that ALREADY hold an account with that
address; it never invents membership. For an org that should have Forge
but does not:

    task-server admin create-user --org <slug> --email ${FORGE_EMAIL}
NEXT
