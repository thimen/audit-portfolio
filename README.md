# Thim Thor Audit Portfolio

I'm an independent smart contract security researcher. I have been taking part in public audit contests on Sherlock, Code4rena and Cantina since March 2025.

**Highlights**

- 20 findings across 10 contests: 7 High, 13 Medium
- 2nd place at Ekubo (Code4rena)
- 7th place at Fluid DEX v2 (Sherlock)
- Metric finding selected for the final report

You can find me on [Sherlock](https://audits.sherlock.xyz/watson/thimthor), [Code4rena](https://code4rena.com/@thimthor) and [Cantina](https://cantina.xyz/u/thimen24).

For roles, private audits or questions, email thim@thimthor.com. Website: [thimthor.com](https://thimthor.com).

## Audit Contests

| Contest | Platform | Date | Category | Findings | Rank |
|--- | --- | --- | --- | --- | ---:|
| [Ekubo](https://code4rena.com/audits/2025-11-ekubo) | Code4rena | Nov 2025 | Concentrated liquidity AMM | 2 M | 2nd |
| [Fluid DEX v2](https://audits.sherlock.xyz/contests/1225) | Sherlock | Jan 2026 | DEX, lending | 1 H, 2 M | 7th |
| [Crestal Network](https://audits.sherlock.xyz/contests/755) | Sherlock | Mar 2025 | AI agent | 1 H | 12th |
| [Metric](https://audits.sherlock.xyz/contests/1279) | Sherlock | Jul 2026 | DEX | 3 M | 14th |
| [Index Fun Order Book](https://audits.sherlock.xyz/contests/1197) | Sherlock | Oct 2025 | Prediction market | 1 H | 14th |
| [stNXM by EaseDeFi](https://audits.sherlock.xyz/contests/1203) | Sherlock | Nov 2025 | Liquid staking | 1 H, 3 M | 20th |
| [Ammplify](https://audits.sherlock.xyz/contests/1054) | Sherlock | Sep 2025 | AMM LP management | 2 H, 2 M | 23rd |
| [Tare](https://audits.sherlock.xyz/contests/1234) | Sherlock | Jul 2026 | Institutional lending | No H/M | 24th |
| [DRE App (dreUSD)](https://audits.sherlock.xyz/contests/1259) | Sherlock | Jun 2026 | Stablecoin | No H/M | 34th |
| [Revert StableSwap Hooks](https://cantina.xyz/competitions/e55ee7b9-6c99-42f8-8338-39f3dd134ef3) | Cantina | Apr 2026 | Uniswap v4 hooks | 1 H, 1 M | 56th |

## Write-ups

- [Fluid DEX v2: withdraw amount exceeds the burned position balance](findings/fluid-dex-v2-withdraw-clamp/) (High, Foundry PoC)
- [Metric: confidence flooring undercharges swap fees](findings/metric-e8-confidence-flooring/) (Medium, selected report, Foundry PoC)
- [Ekubo: storage collision in the Oracle extension](findings/ekubo-oracle-storage-collision/) (Medium, Foundry PoC)
- [Ekubo: exact-out swaps fill partially](findings/ekubo-exact-out-partial-fill/) (Medium, Foundry PoC)
- [Fluid DEX v2: D3 liquidation penalty weighted by the spot price](findings/fluid-dex-v2-d3-liquidation-spot-price/) (Medium, Foundry PoC)
- [Ammplify: fee walker omits the width on unvisited nodes](findings/ammplify-fee-walker-width/) (High)
- [Crestal Network: public `payWithERC20` takes approved funds](findings/crestal-pay-with-erc20/) (High, Foundry PoC)

## All findings

### Ekubo (Code4rena)
- [M] [Oracle data corruption via storage key collision](findings/ekubo-oracle-storage-collision/)
- [M] [Router does not check whether an exact-out single swap was partially filled](findings/ekubo-exact-out-partial-fill/)

### Fluid DEX v2 (Sherlock)
- [H] [MoneyMarket normal-supply withdraw clamps only the raw burn but withdraws the user-requested amount from Liquidity, draining pooled funds](findings/fluid-dex-v2-withdraw-clamp/)
- [M] [D3 liquidation uses manipulable DexV2 spot price to weight the liquidation penalty](findings/fluid-dex-v2-d3-liquidation-spot-price/)
- [M] LiquidityLayer failure credits stored balance under `to_`, but stored balances are spendable only by `msg.sender`, so EOA recipients cannot claim

### Crestal Network (Sherlock)
- [H] [Arbitrary `transferFrom` in public `Payment::payWithERC20` lets an attacker steal approved funds](findings/crestal-pay-with-erc20/)

### Metric (Sherlock)
- [M] [Premature E8 confidence flooring erases configured swap fees](findings/metric-e8-confidence-flooring/) (selected for report)
- [M] Synthetic ratio quantization can halve the pool ask and drain nearly half of LP principal
- [M] Pyth E8 normalization discards the price remainder and underprices pool inventory

### Index Fun Order Book (Sherlock)
- [H] Buyer fee rate charged to the seller in `_executeTokenSwap` and to the matcher in `_executeAgainstMatcher`

### stNXM by EaseDeFi (Sherlock)
- [H] `removeTokenIdAtIndex` lets the owner remove active staking NFTs from accounting to mint underpriced shares and drain the vault
- [M] Duplicate tranche entries let the owner over-withdraw vault assets
- [M] `stNXM::extendDeposit` removes stake from accounting
- [M] Uniswap TWAP oracle bricks the Morpho market when the pool keeps default observation cardinality

### Ammplify (Sherlock)
- [H] [`FeeWalker::up` under-credits compounding fees by a factor of `key.width()` on non-visited nodes](findings/ammplify-fee-walker-width/)
- [H] Inconsistent high-tick exclusivity between `WalkerLib::modify` and `PoolWalker::settle`
- [M] `TimedAdmin` in `Diamond` breaks `acceptOwnership`, so ownership cannot be transferred
- [M] `NFTManager::tokenURI` reads NFTManager storage instead of Diamond storage and reverts

### Revert StableSwap Hooks (Cantina)
- [H] Native ETH `removeLiquidity` reentrancy prices swaps with stale reserves
- [M] Exact-output swaps can round low-decimal input to zero
