# Thim Thor — audit portfolio

Independent smart contract security researcher, Stockholm. 20 valid findings (7 High, 13 Medium) in 10 public contests on Sherlock, Code4rena and Cantina since March 2025.

Profiles: [Sherlock](https://audits.sherlock.xyz/watson/thimthor) · [Code4rena](https://code4rena.com/@thimthor) · [thimthor.com](https://thimthor.com) · thim@thimthor.com

## Contests

| Contest | Platform | Date | Rank | High | Medium | |
|---|---|---|---:|---:|---:|---|
| [Ekubo](https://code4rena.com/reports/2025-11-ekubo) | Code4rena | Nov 2025 | 2nd | 0 | 2 | Only warden with 2 valid findings |
| [Fluid DEX v2](https://audits.sherlock.xyz/contests/1225) | Sherlock | Jan 2026 | 7th | 1 | 2 | 3 of the 4 valid issues |
| [Crestal Network](https://audits.sherlock.xyz/contests/755) | Sherlock | Mar 2025 | 12th | 1 | 0 | First contest |
| [Metric](https://audits.sherlock.xyz/contests/1279) | Sherlock | Jul 2026 | 14th | 0 | 3 | Write-up selected for final report |
| [Index Fun Order Book](https://audits.sherlock.xyz/contests/1197) | Sherlock | Oct 2025 | 14th | 1 | 0 | |
| [stNXM by EaseDeFi](https://audits.sherlock.xyz/contests/1203) | Sherlock | Nov 2025 | 20th | 1 | 3 | |
| [Ammplify](https://audits.sherlock.xyz/contests/1054) | Sherlock | Sep 2025 | 23rd | 2 | 2 | |
| [Tare](https://audits.sherlock.xyz/contests/1234) | Sherlock | Jul 2026 | 24th | – | – | No valid issues by any participant |
| [DRE App (dreUSD)](https://audits.sherlock.xyz/contests/1259) | Sherlock | Jun 2026 | 34th | – | – | No valid issues by any participant |
| [Revert StableSwap Hooks](https://cantina.xyz/competitions/e55ee7b9-6c99-42f8-8338-39f3dd134ef3/leaderboard) | Cantina | May 2026 | 58th | 1 | 1 | |
| **10 contests** | | | | **7** | **13** | |

## Write-ups

| Finding | Severity |
|---|---|
| [Fluid DEX v2 · D3 liquidation uses the manipulable DexV2 spot price to weight the liquidation penalty](findings/fluid-dex-v2-d3-liquidation-spot-price/) | Medium |
| [Metric · Premature E8 confidence flooring erases configured swap fees](findings/metric-e8-confidence-flooring/) | Medium, selected report |
| [Ammplify · `FeeWalker::up` under-credits compounding fees by `key.width()` on non-visited nodes](findings/ammplify-fee-walker-width/) | High |
| Ekubo · [Oracle data corruption via storage key collision](https://code4rena.com/reports/2025-11-ekubo#m-01-oracle-data-corruption-via-storage-key-collision) | Medium |
| Ekubo · [Router does not check whether an exact-out swap was partial](https://code4rena.com/reports/2025-11-ekubo#m-04-router-does-not-check-if-exact-out-single-swap-was-partial-leading-to-unexpected-results-for-the-users) | Medium, one of two valid reports |

## All valid findings

Titles are from my submissions; severity is the final judged severity.

**Ekubo** (Code4rena)
- M · Oracle data corruption via storage key collision (`token << 32 | index` collides with another token's `Counts` slot)
- M · Router does not check whether an exact-out single swap was partially filled

**Fluid DEX v2** (Sherlock)
- H · MoneyMarket normal-supply withdraw clamps only the raw burn but withdraws the user-requested amount from Liquidity, draining pooled funds
- M · D3 liquidation uses manipulable DexV2 spot price to weight the liquidation penalty
- M · LiquidityLayer failure credits stored balance under `to_`, but stored balances are spendable only by `msg.sender`, so EOA recipients cannot claim

**Crestal Network** (Sherlock)
- H · Arbitrary `transferFrom` in public `Payment::payWithERC20` lets an attacker steal approved funds

**Metric** (Sherlock)
- M · Premature E8 confidence flooring erases configured swap fees (selected report)
- M · Synthetic ratio quantization can halve the pool ask and drain nearly half of LP principal
- M · Pyth E8 normalization discards the price remainder and underprices pool inventory

**Index Fun Order Book** (Sherlock)
- H · Buyer fee rate charged to the seller in `_executeTokenSwap` and to the matcher in `_executeAgainstMatcher` (two reports, judged as one issue)

**stNXM by EaseDeFi** (Sherlock)
- H · `removeTokenIdAtIndex` lets the owner remove active staking NFTs from accounting to mint underpriced shares and drain the vault
- M · Duplicate tranche entries let the owner over-withdraw vault assets
- M · `stNXM::extendDeposit` removes stake from accounting
- M · Uniswap TWAP oracle bricks the Morpho market when the pool keeps default observation cardinality

**Ammplify** (Sherlock)
- H · `FeeWalker::up` under-credits compounding fees by a factor of `key.width()` on non-visited nodes
- H · Inconsistent high-tick exclusivity between `WalkerLib::modify` and `PoolWalker::settle`
- M · `TimedAdmin` in `Diamond` breaks `acceptOwnership`, so ownership cannot be transferred
- M · `NFTManager::tokenURI` reads NFTManager storage instead of Diamond storage and reverts

**Revert StableSwap Hooks** (Cantina)
- 1 High, 1 Medium. Cantina does not publish finding titles for this competition.
