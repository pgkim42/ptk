---
name: ground-the-rec
description: Ground a recommendation in this repo before proposing or implementing it. Use when starting to implement, add, or build a feature (구현, 추가), or when choosing a library, API, pattern, or version.
---

# Ground the rec

A rec is **grounded** when every applicable gate has checkable evidence. Ground before the first rec or the first edit. User asked for code → ground, then implement in the same turn.

Gates are pass conditions, not agents. The main agent runs them. One scout only when Fit needs a tour of unknown code. Paths stays on the main agent.

Order: **Fit**, then **Stale** if a library/API/version remains, then **Paths** if the rec has runtime behavior. Skip a gate that does not apply; do not announce the skip.

## Fit

What this repo already does in this layer.

Done: the rec cites a path or symbol it follows, or states there is no precedent in this layer. A name-search miss is not "no precedent" — look at the neighboring feature in the same layer, or the data/auth pattern this would sit on.

Fit is this repo's current convention. The habit this task is here to change is not a precedent.

## Stale

Applies when the rec names a library, API, or version.

Done: for an existing dependency, cite its resolved version (or declared range if unresolved) and version-matched official docs or source for the behavior relied on. For a new dependency or upgrade, cite current official support and compatibility with this repo's runtime. A version declaration alone does not establish API behavior; latest docs may describe a different version. Training recall is not a source.

## Paths

Applies when the rec has runtime behavior.

Done: state the expected behavior on the success path and the failure/empty/auth/idempotency paths relevant to this change, grounded in existing code or the task's requirements. Name any deferred path with a reason. Cover paths the change introduces as well as existing ones; do not invent inapplicable paths. Design coverage, not a test matrix.

## Output

Cite paths, symbols, or source links in the recommendation, or in a brief explanation before the first edit when implementing directly. Keep grounding evidence in that explanation rather than adding research-only code comments. No gate report. An uncited applicable gate is open; state the uncertainty and keep dependent recommendations provisional until it is resolved.
