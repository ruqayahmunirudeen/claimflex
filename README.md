# claimdrop-plus-extended

Lightweight Clarity contract to manage an STX airdrop / claim drop with per-user allocations, claim tracking, optional deadline, pausing, min-claim threshold, and owner reclaim/withdraw flows.

## Features
- Assign claimable STX to single users or batch assign.
- Per-user claim tracking to prevent double claims.
- Optional claim deadline (owner sets block height).
- Owner reclaim of individual or all expired/unused allocations.
- Pause / unpause claiming.
- Minimum claimable amount guard.
- Owner withdraw of unused STX.

## Files
- contracts/claimflex.clar — main Clarity contract.

## Contract overview (public API)

All owner-only functions require tx-sender == contract-owner.

Owner (admin) calls
- set-claimable(user: principal, amount: uint) -> (ok true | err ...)
  - Assign single user's allocation; increments total-assigned.
- batch-assign(users-amounts: (list 50 (tuple (user principal) (amt uint)))) -> (ok true)
  - Batch assign many users; increments total-assigned.
- reclaim-unclaimed(user: principal) -> (ok amount | err ERR_ALREADY_RECLAIMED)
  - Remove a user's allocation (if unclaimed) and decrement total-assigned.
- reclaim-expired(users: (list 100 principal)) -> (ok true | err ...)
  - If a claim-deadline is set and passed, removes allocations for provided users (owner only).
- set-claim-deadline(block: uint) -> (ok true)
  - Set optional deadline (stored as (some block)).
- withdraw-unused(amount: uint, recipient: principal) -> (ok true | err ...)
  - Transfer STX from contract to recipient (owner only).
- transfer-ownership(new-owner: principal) -> (ok true)
- set-claim-paused(status: bool) -> (ok true)
- set-min-claim(amount: uint) -> (ok true)

User calls
- claim() -> (ok amount | err ...)
  - Claims sender's allocation, respects paused flag, min-claim-amount, optional deadline, and prevents double-claiming.

Read-only
- check-eligibility(user: principal) -> (ok bool)
- has-user-claimed(user: principal) -> (ok bool)
- get-owner() -> (ok principal)
- get-deadline() -> (ok (optional uint))
- get-total-assigned() -> (ok uint)
- get-total-claimed() -> (ok uint)
- get-claimable(user: principal) -> (ok uint)

## Error codes
- ERR_UNAUTHORIZED: u100
- ERR_ALREADY_CLAIMED: u101
- ERR_NOT_ELIGIBLE: u102
- ERR_INSUFFICIENT_BALANCE: u103
- ERR_CLAIM_DEADLINE_PASSED: u104
- ERR_ALREADY_RECLAIMED: u106
- ERR_CLAIM_PAUSED: u107
- ERR_BELOW_MIN_THRESHOLD: u108

The contract uses these constants as (err uNNN) values.

## Typical flows (examples)

1) Owner assigns airdrop
- set-claimable 'ST...  u100
- or batch-assign a list of (user, amt) tuples.

2) User claims
- claim()
  - Checks: not paused, not already claimed, amount > 0, amount >= min threshold, (if deadline some d then current block <= d)
  - On success: transfers STX from contract to user, marks has-claimed true, deletes claimable-stx entry.

3) Owner reclaims unused / expired
- reclaim-unclaimed(user) — reclaim immediately if user hasn't claimed.
- set-claim-deadline(block) then after block passes:
  - reclaim-expired(list-of-users) to clear allocations.

4) Owner withdraws leftover STX
- withdraw-unused(amount, recipient)

## Local development & testing

Prerequisites
- Clarinet for local testing (https://github.com/hirosystems/clarinet)
- Stacks CLI / stacks.js for deployment and integration (optional)
- Node.js for using stacks.js (optional)

Quick local test
- Place contract in contracts/ and run:
  - clarinet test
  - clarinet console
- From clarinet console you can call functions:
  - (contract-call? .claimflex set-claim-deadline u1000)
  - (contract-call? .claimflex set-claim-paused false)
  - (contract-call? .claimflex set-claimable 'ST1...' u100).

Deployment
- Compile and deploy using your preferred Stacks tooling (Stacks CLI, deploy via wallet, or other CI).
- Ensure the contract account funds the contract with sufficient STX to cover claims before users call claim().
- v1.0 — initial implementation: per-user allocations, claim & reclaim flows, optional deadline, pause, min threshold.

For questions, run clarinet console and use contract-call? / call helpers to interact with the contract.
