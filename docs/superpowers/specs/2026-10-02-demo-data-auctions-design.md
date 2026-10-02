# Local Demo Data for Auctions and Existing Roles

## Goal

Populate the existing local web portal with useful demo records so the ADMIN,
SHIPPER, and CARRIER views can be inspected, with emphasis on auction flows.
Keep the current PostgreSQL and MongoDB volumes and all records outside the
explicit demo fixtures.

## Current findings

- The local Mongo database already contains auction history, but has no `OPEN`
  auctions. Its `PENDING` auctions all have future registration windows, so a
  carrier currently has no auction to join.
- The existing Mongo init-script bind in Compose points to a missing/empty host
  path. Mongo init scripts also do not run again when the current volume already
  contains a database.
- The bidding service already has the auction, bid, and registration schemas
  needed for demo fixtures.
- Driver profiles exist under fleet data and can be managed by a carrier. The
  repository has no active standalone driver portal/login flow, so this change
  will not claim to implement or seed a DRIVER role.

## Recommended design

Add a repeatable demo-seed command to the bidding service and run it against the
already-running local Mongo database. Use stable IDs reserved for demo fixtures
and upsert only those auction, registration, and bid documents. Do not drop a
database, clear collections, or modify non-demo records. Compute the active
fixture dates at seed time so registration and live auctions are visible now,
including when the seed is run on a later day.

Remove the broken host bind mount for the absent Mongo init seed. The explicit
command is the source of truth for loading data into both a fresh and an
already-populated local volume. Document its invocation next to the local
Compose instructions.

### Demo scenarios

Seed fixtures that cover:

1. A `PENDING` public auction with registration open now and bidding not yet
   started.
2. A live `OPEN` public auction with multiple carrier registrations and bids,
   including a leading and an outbid carrier.
3. A live `OPEN` sealed auction with registered carriers and bids.
4. A `COMPLETED` public auction with a winner and a completed one without a
   winner.
5. A `CANCELLED` auction visible in history.
6. Registration records that demonstrate the supported payment, deposit, and
   participation-fee states without contradicting each auction's state.

Reference existing shipper and carrier accounts, verified vehicles, and the
current Mongo schemas. Do not create identity accounts or change SQL business
data as part of this seed.

## User-visible result

After running the command, the existing web portal should show an auction open
for registration and active public/sealed auctions for the carrier account,
with related history available to the auction owner. Admin, shipper, and carrier
logins continue to use their existing data. Carrier driver-management screens
continue to use fleet-service driver profiles; a standalone driver experience
is explicitly outside this change.

## Safety and repeatability

- Re-running the command updates only records whose IDs belong to this demo
  fixture set.
- Existing auctions and records created outside the fixture set remain intact.
- The script uses the bidding service's configured Mongo connection and current
  schema fields/enums.
- Fixture dates are refreshed by the command; it does not run automatically on
  every service restart.

## Acceptance criteria

- Compose can start without trying to mount the missing seed file.
- The documented command succeeds against the existing local Mongo volume.
- A second run creates no duplicate fixtures and leaves non-demo records intact.
- At least one registration window and one public plus one sealed auction are
  actionable at the time the seed runs.
- The listed terminal and registration scenarios are visible through the
  existing portal/API flows.
- No new driver login, driver portal, or DRIVER role is implied by the seed.

## Out of scope

- Implementing the standalone driver application or driver authentication.
- Resetting or migrating the existing databases.
- Creating/changing accounts, passwords, wallet balances, or PostgreSQL records.
- Changing auction business rules or adding new product screens.
