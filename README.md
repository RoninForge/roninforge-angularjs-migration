# roninforge-angularjs-migration

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Source-of-truth repo for the **AngularJS to Angular 18** GitHub Copilot instructions package shipped to `github/awesome-copilot` at `instructions/angularjs-to-angular-18.instructions.md`. First in a planned series of enterprise-targeted Copilot products from RoninForge (planned: .NET Framework to .NET 9 migration, HIPAA PHI redaction, T-SQL anti-patterns, characterization tests for legacy code).

## The Problem

- AngularJS 1.x exited Long-Term Support on **December 31, 2021**. Since January 2022 Google has stopped shipping security, browser-compatibility, and jQuery-compatibility fixes.
- The final release is v1.8.3 (April 7, 2022) - a README-only "ultimate-farewell" tag. The substantive code freeze is v1.8.2 (October 2020).
- **CVE-2024-21490** (Regular Expression Denial of Service in `ng-srcset`, all versions 1.3.0 through 1.8.3) has no upstream patch. Commercial extended-support forks (HeroDevs NES, OpenLogic) are the only patched builds.
- Banks, healthcare systems, and government agencies are still on 1.x: compliance freezes, talent gap, ngUpgrade complexity, and the XLTS migration-math formula (`TTM = (LOC/LPW) * 1.4`) that makes the calendar cost visible.
- GitHub Copilot's own issue tracker (#1019, #1128) documents Angular 17+ syntax unawareness; HeroDevs reports 73% of AI-assisted AngularJS migrations fall behind schedule because LLMs emit pre-2025 patterns.

## What this package teaches Copilot

One large `.instructions.md` file (1,971 lines) covering:

- The AngularJS EOL state + CVE-2024-21490 evidence (why a migration is non-optional unless on commercial support)
- 17 Angular 18 canonical patterns (standalone default, signals, control flow `@if`/`@for`/`@switch`, deferrable views `@defer`, function-based interceptors/guards/resolvers, `provideHttpClient`, `provideRouter` + `withComponentInputBinding`, `inject()`, typed reactive forms, OnPush + zoneless dev preview, `DestroyRef` + `takeUntilDestroyed`, `toSignal`/`toObservable`, signal-based `viewChild`/`viewChildren`, `NgOptimizedImage`, Vitest, application builder)
- Three migration paths with effort sizing and case studies: big-bang (3-9mo), ngUpgrade hybrid (6-18mo, recommended), strangler-fig (6-24mo)
- **62 anti-patterns** with BAD/CORRECT pairs and source citations, in three failure modes:
  - **Mode A (15):** AngularJS 1.x patterns emitted for plain "Angular" requests (`$scope.$apply`, `ng-controller`, `$compile`, `$http`, `$q`, `ng-app`, `ng-bind-html`, `ng-click`, `angular.module`, `| filter`, `$resource`, `$cookies`, `$location`, IIFE 'use strict' wrap)
  - **Mode B (35):** Angular 2-17 legacy idioms emitted instead of Angular 18 (`*ngIf` / `*ngFor` / `*ngSwitch`, NgModules, `@Input()` / `@Output()` decorators, constructor DI, class-based interceptors/guards/resolvers, `HttpClientModule`, `RouterModule.forRoot`, `Promise.all` vs `forkJoin`, subscribe leaks, `BehaviorSubject` state, default change detection, `@ViewChild` static, untyped forms, `rxjs/operators` deprecated imports, browser builder)
  - **Mode C (12):** migration-specific mistakes (big-bang advice without ngUpgrade, unmaintained packages, mixed imports, missing `downgradeInjectable` / `downgradeComponent`, wrong bootstrap order, treating `ng update` as a framework migration, literal `$rootScope.$broadcast` ports, `BrowserAnimationsModule` in standalone, zoneless + zone.js polyfill leak)
- Decision tree (LoC-bucket to calendar mapping; condition to path)
- Eight ngUpgrade gotchas with fix snippets
- References (Angular 18 official docs, EOL + CVE advisories, commercial support, case studies, deprecations)

## Repository layout

```
~/development/roninforge-angularjs-migration/
.
.cm  README.md                       This file
.cm  LICENSE                         MIT
.cm  CHANGELOG.md                    semver entries
.cm  META.yml                        slug / type / version / target_paths consumed by submit script
.cm  .editorconfig / .gitattributes  LF-only normalization (awesome-copilot blocks CRLF)
.cm  .codespellrc                    mirrors upstream allowlist
.cm  scripts/
.cm    validate-awesome-copilot-submission.sh   reusable validator, mirrors every blocking CI gate
.cm    submit-to-awesome-copilot.sh             reusable submitter (fork, branch from staged, copy, regen, PR)
.cm  src/                            (placeholder for authoring partials when future packages split sources)
.cm  dist/
.cm    angularjs-to-angular-18.instructions.md  exact file that gets rsynced into upstream instructions/
.cm  tests/golden/                   (placeholder for diff-against-frozen-output tests)
.cm  .github/workflows/validate.yml  runs the validator on every push
```

`research/` is gitignored; it contains internal notes that informed the instructions content but is not part of the public artifact.

## Pipeline scripts (reusable across all RoninForge awesome-copilot packages)

### `scripts/validate-awesome-copilot-submission.sh`

Run inside a clone of `github/awesome-copilot`. Mirrors every blocking CI gate:

1. Preflight (node 20+, npm, jq, git, codespell)
2. `npm ci` if needed
3. Detect artifact type from path
4. Naming convention check (lowercase-kebab; per-type filename regex)
5. Frontmatter schema check (per-type required fields, single-quoted strings)
6. Body content check (instructions must open with `# `)
7. CRLF line-ending check (blocks if found)
8. `codespell --check-filenames --config .codespellrc`
9. 5MB asset cap for skills
10. `gh aw compile --validate` for workflows
11. `npm run plugin:validate` for plugins
12. `npm run skill:validate` for skills/agents (warn-only)
13. **`npm start` + `git diff --exit-code`** (the #1 mechanical bounce - validate-readme.yml fails if README/marketplace are stale)

### `scripts/submit-to-awesome-copilot.sh`

End-to-end pipeline:

1. Read `META.yml` (slug, type, version)
2. `gh auth status`
3. Fork `github/awesome-copilot` to `RoninForge` if not already forked
4. Clone fork to `.upstream-clone/`
5. **Fetch + reset to `upstream/staged` (NEVER `main`)**
6. Cut feature branch from `upstream/staged`
7. Copy `dist/` artifacts to the upstream tree at the correct paths per type
8. Run the validator (above) - aborts on any failure
9. `npm start` to regenerate README + marketplace
10. Commit with `🤖🤖🤖` AI-author fast-track marker
11. Push to fork
12. Open PR with **base: `staged`** (NEVER `main`) - the `check-pr-target.yml` job auto-rejects PRs to main

Supports `--dry-run` (stops before push) and `--no-pr` (pushes branch but skips PR creation).

## Versioning

Pin floors:

- **AngularJS final stable:** 1.8.2 (October 2020, last code release); 1.8.3 (April 2022, README-only farewell). LTS ended Dec 31 2021.
- **Angular 18:** May 22, 2024. Latest 18.x patch recommended for `ng update` schematic stability.
- **Node 20 LTS minimum** for Angular 18 dev server.
- **RxJS 7.5+ minimum** for Angular 18 peer.
- **TypeScript 5.4+ minimum** for Angular 18 peer.

Avoid: AngularJS-era packages no longer maintained (`angular-ui-bootstrap`, `ng-storage`, `ng-flow`, `angular-translate-loader-static-files`); Karma + Jasmine for new test files (Vitest via `ng add @analogjs/vitest-angular`).

## License

MIT - see [LICENSE](LICENSE).

## Links

- [Angular 18 release post](https://blog.angular.dev/angular-v18-is-now-available-e79d5ac0affe)
- [Angular llms.txt for AI-assisted development](https://angular.dev/ai/develop-with-ai)
- [ngUpgrade documentation](https://angular.dev/guide/upgrade)
- [HeroDevs CVE-2024-21490 advisory](https://www.herodevs.com/blog-posts/addressing-the-latest-angularjs-cve-2024-21490)
- [endoflife.date / AngularJS](https://endoflife.date/angularjs)
- [github/awesome-copilot](https://github.com/github/awesome-copilot)
- [RoninForge](https://roninforge.org)


## More from RoninForge

[RoninForge](https://roninforge.org) builds free tools for developers working with AI coding assistants:

- [LLM API pricing comparison](https://roninforge.org/llm-pricing) - Claude, GPT, Gemini, DeepSeek, Mistral, and Grok token prices side by side, verified against official pricing pages
- [GitHub Copilot AI Credits calculator](https://roninforge.org/copilot-credits-calculator) - estimate your monthly credit burn under usage-based billing
- [All Cursor plugins](https://roninforge.org/#plugins)
