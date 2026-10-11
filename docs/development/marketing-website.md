# Frontier Systems public website

The owner requested a dedicated GitHub Pages advertising, fundraising and sale site on DiscordPHP.org's domain, preferring a subdomain. It is hosted separately from the main DiscordPHP website:

- Public site: https://frontier-systems.discordphp.org/
- Fundraisers: https://frontier-systems.discordphp.org/support.html
- Availability: https://frontier-systems.discordphp.org/buy.html
- Website source: https://github.com/discord-php/frontier-systems-site
- Launch PR: https://github.com/discord-php/frontier-systems-site/pull/1

## Launch evidence

Final reviewed feature head `9c6fb70391f84f87ce6ca565ec7b77a04cfd5655`; launch PR CI run `38105717319` passed. Merge/deployed revision `4fc718d3024e09270d4a9387bfde0167f5b74740`; publication run `38105749822` passed build and deployment. Public `build.json` reports that exact revision. Local Node build and focused output, serialization, fallback, alternate-base and sale-state checks passed; desktop/mobile browser navigation and layouts were reviewed. Mobile image sizing was corrected before the final CI run.

All three public primary pages returned 200 HTML to Discordbot's documented user agent. Inline previews have seven components each, zero gallery items, and 624/612/620 emitted UTF-8 bytes for home/support/buy. The official Discord Embed Debugger rendered the home preview as `type: components`, with its text, separator and three link buttons. This is website unfurling, not bot command or interaction functionality.

The generated 1200×630 brand PNG returned 200 `image/png`, 21,096 bytes. Live/local SHA-256 matched `7C20FF70CFA91F64D92937796B99CEE4CF7C41BF242E48F6785061482A49BBF0`. Open Graph and Twitter Card fallbacks are included. Original MIT SVG/raster geometry is explicitly conceptual branding, not gameplay; current gameplay verification captures remain internal. No screenshot uploads, analytics, cookies, external fonts or third-party runtime JavaScript were added.

DNS has one new DNS-only CNAME: `frontier-systems.discordphp.org` → `discord-php.github.io`. Public Cloudflare/Google DNS resolved it; GitHub's DNS check succeeded and requested its TLS certificate. Existing DiscordPHP apex, mail and verification records are preserved. HTTPS enforcement is the final hosting check once certificate issuance completes; Coordinator tracks that state and must not bypass certificate errors.

At the owner's insecure-connection report (2026-10-11 around 02:58 UTC), verified TLS failed with Windows `SEC_E_WRONG_PRINCIPAL`; GitHub still reported certificate state `new` and enforcement unavailable. DNS/domain health was valid. Coordinator used GitHub's documented provisioning recovery once: remove and immediately restore only this website's custom-domain setting. The domain was restored, DNS check succeeded and the UI showed certificate requested (1 of 3). No TLS validation bypass, DNS/proxy weakening or parent-site hosting change. At 02:58:48 UTC issuance was still pending. Allow the restarted request to progress rather than repeatedly cancelling it. [GitHub recovery guidance](https://docs.github.com/en/pages/getting-started-with-github-pages/securing-your-github-pages-site-with-https#troubleshooting-certificate-provisioning-certificate-not-yet-created-error). Proof: ignored `var/ci/frontier-website/certificate-pending.jpg`.

The owner explicitly approved this remaining website follow-up in the existing ten-minute Coordinator automation. The original plan waited for HTTPS before merging homepage-link PRs [Valgorithms #6](https://github.com/valzargaming/valgorithms.com/pull/6) at `08d3f7e3474b8b3733a6e5db00d0de7c5a039ffe` and [DiscordPHP.org #9](https://github.com/discord-php/DiscordPHP.org/pull/9) at `6c60b44277c50e07826942ab6c357374e3f12ef4`, with matching-head guards, then verify publishing and update this record. Both PRs passed their applicable build checks; The owner superseded that wait on 2026-10-11: website links may publish before HTTPS is ready. Notify the delegated Discord setup chat when the HTTPS site link is usable.

Local browser/crawler/CI proof is ignored under `var/ci/frontier-website/`. It is operational evidence, not public gameplay gallery content.

## Upkeep and sale boundary

Owner requested a Frontier Systems entry in Valgorithms' project shelf. The existing Valgorithms PR #6 now also adds a Games card with official website, source and support links, truthful prototype/sales status and existing shelf styling. Its new exact head is `063683460dc3604ebd022a65bb618fcddf6943cd`, superseding `08d3f7e3474b8b3733a6e5db00d0de7c5a039ffe` for review/CI/merge. Local syntax, build and output checks passed (8 pages, 7 assets, six preview tests); desktop and 390px mobile shelf inspected, no horizontal overflow/browser errors. The owner removed HTTPS readiness as a publication gate; exact-head CI remains required. Local isolated checkout: ignored `var/valgorithms-site-repo`.

Update website copy after meaningful verified player-visible milestones alongside campaign upkeep. The website repository's `site/content.json` controls URLs and reviewed status date; `tools/build.mjs` generates the static pages. Public links lead to existing $5,000 USD initial-development funding and $5/$15/$30 memberships on Ko-fi; no unverified raised totals are shown.

The buy page currently explains that no finished-game sale is open and links source-prototype instructions/acceptance. Contributions are not preorders or game keys. Future sale support is implemented through an owner-approved `storeUrl`, `saleLabel` and `saleDescription`; an incomplete offer fails the build. The site does not process transactions or hold payment information. Review an actual release, price/offer and official storefront before opening sales.

GitHub Pages publishes only the website repository's validated `dist/` from main. It cannot publish game releases or replace the DiscordPHP.org parent site. The parent-site promotion and Valgorithms homepage feature remain in place.

Official specifications:
- https://docs.discord.com/developers/link-previews/component-embeds
- https://docs.discord.com/developers/link-previews/overview
- https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site


## Owner override: links publish independently of HTTPS

On 2026-10-11 the owner instructed not to wait for HTTPS before publishing links elsewhere. Reviewed exact-head green Valgorithms PR6 (063683460dc3604ebd022a65bb618fcddf6943cd) and DiscordPHP.org PR9 (6c60b44277c50e07826942ab6c357374e3f12ef4) were guarded squash-merged to e793a2c1c88a9af755de8d8ec82aa77f3c069350 and 8a6c815e3fbfede6e8c91b967acd8b4ccce72477. Valgorithms Pages run38120111492 is in progress; deployed live-link confirmation remains pending. Certificate issuance/enforcement and secure-site verification remain a separate Coordinator obligation; no certificate warnings were bypassed. The recurring prompt preserves this override.


Both parent-site link deployments completed successfully: Valgorithms run38120111492 at e793a2c1c88a9af755de8d8ec82aa77f3c069350; DiscordPHP.org Pages run38120113852 at8a6c815e3fbfede6e8c91b967acd8b4ccce72477. Live GET checks on2026-10-11 returned200 for both homepages and exact HTTPS Frontier link; Valgorithms also contains The shelf. Certificate remains new and secure custom-domain verification pending independently.

