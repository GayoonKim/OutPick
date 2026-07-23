# Lookbook Extraction Fixture Corpus

Fixtures are added by distinct extraction structure, not by brand count.

- `generic/`: platform-independent behavior.
- `platform/`: shared storefront structure such as Cafe24.
- `incidents/`: minimized production failure that is not yet covered elsewhere.

Every fixture directory contains `metadata.json`, `input.html`, optional
`rendered.html`, and `expected.json`. Full pages, cookies, authorization data,
private query values, screenshots, and unrelated markup are prohibited.

A newly observed brand reuses an existing fixture when the same structural
failure is already covered. Add a fixture only for a new selector, rendering,
ordering, filtering, or quality boundary. When several incident fixtures become
equivalent, keep the shared generic/platform fixture and retire redundant HTML.
