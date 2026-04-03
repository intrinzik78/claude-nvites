# Dispatch: Explore campaign_id narrowing in link cache

**Date:** 2026-03-29
**Workstream:** dev

## Problem

`CachedLink.campaign_id` is `i32` but the `load_active` query includes `WHERE sl.campaign_id IS NULL`, which would return rows with NULL `campaign_id`. `sqlx` will fail to decode NULL into `i32` at runtime. No standalone links exist in the database today, so this hasn't triggered yet.

## Suggested Solution

Decide whether standalone links (no campaign) are a supported concept in nvites.me:

- **If yes:** change `campaign_id` to `Option<i32>`, update `RedirectEvent::insert` signature, update `ActiveLinkRow`, and handle `None` in the handler.
- **If no:** remove the `sl.campaign_id IS NULL` clause from `load_active` and add a `NOT NULL` constraint to `short_link.campaign_id` in a migration.

## Reasoning

The query and the type disagree. One of them is wrong. The fix depends on a product decision about whether links can exist outside of campaigns.

## Confidence

**High** on the problem, **low** on which direction — this is a product question.
