---
name: find-skills
description: Discover installable agent skills when a user asks whether a reusable skill exists or wants skill-search options. Search read-only, verify upstream quality and overlap, and never install without separate authorization.
---

# Find Skills

Use discovery to improve recall, not to decide installation.

On Windows PowerShell 7, run scripts/search-skills.ps1 with a specific Query so
npm's generated command shim cannot break the search. Add Owner only when the
request names or justifies an upstream owner. On non-Windows hosts, use the
native npx skills find command.

The Windows wrapper validates that the cached package is named skills, its
skills bin points to bin/cli.mjs, and the entrypoint stays inside the npm cache
before invoking Node. If the cache is absent, it may ask npx.cmd to hydrate the
cache, but it does not alter PATH or install a global package.

Before recommending a result, check its upstream repository, maintenance,
license, requested permissions, target-workflow fit, and overlap with native,
plugin, MCP, or installed-skill capabilities. Popularity and Awesome/Trending
placement are discovery evidence only.

Return the candidate, source URL, observed install count, decisive fit or
overlap evidence, and one of: recommend, do_not_install, or
needs_more_evidence.

Never run skills add, skills update, or another mutating command unless the user
separately authorizes that exact action.
