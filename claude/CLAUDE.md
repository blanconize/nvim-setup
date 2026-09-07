# Global rules (all repos)

Repo-level `AGENTS.md`/`CLAUDE.md` add project specifics and override these.

## Documentation — Context7 MCP (always current)
- The Context7 MCP server is enabled globally (plugin `context7@claude-plugins-official`, authenticated via `CONTEXT7_API_KEY` from `~/.zsh-secrets`; tools `mcp__plugin_context7_context7__resolve-library-id` → `mcp__plugin_context7_context7__query-docs`). It serves current, version-specific docs and code examples for practically every library, framework, CLI and cloud service.
- Before writing code against any library API — even one you "know" (Next.js, React, Prisma, Tailwind, Auth.js, Strapi, Keycloak, Vitest, Zod, PDM …) — look it up: resolve the library, then query one concept per call (≤ 3 queries per question). Pick the version matching the repo's lockfile when offered.
- Training data is stale by definition: when docs and memory disagree, the docs win. Prefer Context7 over web search for library docs. Before bumping a dependency, read its migration guide via Context7.
- Each repo's `AGENTS.md` lists its primary libraries with verified Context7 IDs.

## Workflow
- Red → Green → Refactor. A bug fix starts with the regression test that reproduces it. Production code without a test that went red→green is not committed.
- Before claiming done: run the repo's gate (`pnpm verify` where it exists, otherwise lint + typecheck + test + build) and quote the result.
- `pnpm` only; never `npm`/`yarn` in a pnpm repo. Python repos use `pdm`.
- Migrations are applied by the developer, never by Claude. Deploy only through the repo's `scripts/deploy.sh`; never `pnpm build` inside a project that PM2 serves from — use `build:verify`.
- Commits: no `--no-verify`, no AI attribution trailers.

## TypeScript
- `strict`, `noUncheckedIndexedAccess`. Use `unknown` and narrow; fix the type rather than `@ts-ignore`; narrow rather than `!`.
- Explicit return types on exported functions. Discriminated unions over boolean flags.
- Zod validates every value crossing a trust boundary (request bodies, files, env, external JSON).

## React 19 / Next.js
- Server Components by default; `"use client"` only for interactivity.
- Data: `use(promise)` / Server Components / TanStack Query. State: derived values, `useMemo`, `useReducer`. Forms: `useActionState`. External stores and browser APIs: `useSyncExternalStore`. `useEffect` only for genuine external subscriptions, with cleanup.
- `useCallback` only for functions handed to memoised children.
- Mutations go through `useMutation` or a server action, never a bare `fetch` in an event handler.
- Before writing Next-specific code read the installed docs at `node_modules/next/dist/docs/` (exact installed version) and Context7 (`/vercel/next.js`, matching version) for anything newer or not covered there.

## Code shape
- Function ≤ 30 lines (`.ts`) / ≤ 60 lines (`.tsx`); file ≤ 200 lines; complexity ≤ 10; nesting ≤ 3; ≤ 3 positional parameters. Over a limit = refactor signal.
- Comments only for a non-obvious why. Tests are the documentation: `it("denies a Sachbearbeiter from finalising an invoice")`.
- Read env at the top of one server-only module and re-export typed values.
