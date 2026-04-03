# Dispatch: Remove dead campaign_email test

**Date:** 2026-03-28
**Workstream:** dev

## Problem

`types::email::campaign_email::tests::list_by_campaign_id` fails on every run — it queries a `campaign_email` table that doesn't exist in any migration. The table existed in the UWZ era but wasn't carried forward in the schema rewrite (94b9b59). The test is a false signal that masks real failures in the test suite.

## Suggested Solution

Delete the `list_by_campaign_id` integration test. If the `CampaignEmail` type and its SQL methods are also dead (no handlers reference them), remove the entire `campaign_email.rs` file and its `mod.rs` registration. Check for any remaining references in route_collection.rs or api-contracts before removing.

## Reasoning

The test can never pass without a migration that creates the table, and creating the table isn't planned — the campaign email feature hasn't been designed for nvites.me yet. When it is, the table and tests will be built from scratch as part of that feature. Keeping a perpetually-failing test erodes confidence in the suite and forces manual filtering of "known failures."

## Confidence

**High** — the table doesn't exist, the test can't pass.
