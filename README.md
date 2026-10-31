# Thim Thor audit portfolio

I'm an independent smart contract security researcher based in Stockholm. Since March 2025 I have participated in 10 public audit contests on Sherlock, Code4rena and Cantina, with 20 findings (7 High, 13 Medium).

You can find me on [Sherlock](https://audits.sherlock.xyz/watson/thimthor), [Code4rena](https://code4rena.com/@thimthor) and [Cantina](https://cantina.xyz/u/thimen24).

For private audits or questions, email thim@thimthor.com. Website: [thimthor.com](https://thimthor.com).

## Audit Contests

| Contest | Platform | Category | Findings | Rank |
|--- | --- | --- | --- | ---:|
| [Ekubo](https://code4rena.com/audits/2025-11-ekubo) | Code4rena | Concentrated liquidity AMM | [2 M](#ekubo-code4rena) | 2nd |
| [Fluid DEX v2](https://audits.sherlock.xyz/contests/1225) | Sherlock | DEX, lending | [1 H, 2 M](#fluid-dex-v2-sherlock) | 7th |
| [Crestal Network](https://audits.sherlock.xyz/contests/755) | Sherlock | AI agent | [1 H](#crestal-network-sherlock) | 12th |
| [Metric](https://audits.sherlock.xyz/contests/1279) | Sherlock | DEX | [3 M](#metric-sherlock) | 14th |
| [Index Fun Order Book](https://audits.sherlock.xyz/contests/1197) | Sherlock | Prediction market | [1 H](#index-fun-order-book-sherlock) | 14th |
| [stNXM by EaseDeFi](https://audits.sherlock.xyz/contests/1203) | Sherlock | Liquid staking | [1 H, 3 M](#stnxm-by-easedefi-sherlock) | 20th |
| [Ammplify](https://audits.sherlock.xyz/contests/1054) | Sherlock | AMM LP management | [2 H, 2 M](#ammplify-sherlock) | 23rd |
| [Tare](https://audits.sherlock.xyz/contests/1234) | Sherlock | Institutional lending | - | 24th |
| [DRE App (dreUSD)](https://audits.sherlock.xyz/contests/1259) | Sherlock | Stablecoin | - | 34th |
| [Revert StableSwap Hooks](https://cantina.xyz/competitions/e55ee7b9-6c99-42f8-8338-39f3dd134ef3) | Cantina | Uniswap v4 hooks | [1 H, 1 M](#revert-stableswap-hooks-cantina) | 58th |

## Write-ups

- [Fluid DEX v2: D3 liquidation uses the manipulable DexV2 spot price to weight the liquidation penalty](findings/fluid-dex-v2-d3-liquidation-spot-price/) (Medium)
- [Metric: Premature E8 confidence flooring erases configured swap fees](findings/metric-e8-confidence-flooring/) (Medium, selected for the final report)
- [Ammplify: `FeeWalker::up` under-credits compounding fees by `key.width()` on non-visited nodes](findings/ammplify-fee-walker-width/) (High)
- [Ekubo: Oracle data corruption via storage key collision](https://code4rena.com/reports/2025-11-ekubo#m-01-oracle-data-corruption-via-storage-key-collision) (Medium)
- [Ekubo: Router does not check whether an exact-out swap was partial](https://code4rena.com/reports/2025-11-ekubo#m-04-router-does-not-check-if-exact-out-single-swap-was-partial-leading-to-unexpected-results-for-the-users) (Medium, one of two reports)

## All findings

### Ekubo (Code4rena)
- [M] Oracle data corruption via storage key collision
- [M] Router does not check whether an exact-out single swap was partially filled

### Fluid DEX v2 (Sherlock)
- [H] MoneyMarket normal-supply withdraw clamps only the raw burn but withdraws the user-requested amount from Liquidity, draining pooled funds
- [M] D3 liquidation uses manipulable DexV2 spot price to weight the liquidation penalty
- [M] LiquidityLayer failure credits stored balance under `to_`, but stored balances are spendable only by `msg.sender`, so EOA recipients cannot claim

### Crestal Network (Sherlock)
- [H] Arbitrary `transferFrom` in public `Payment::payWithERC20` lets an attacker steal approved funds

### Metric (Sherlock)
- [M] Premature E8 confidence flooring erases configured swap fees
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
- [H] `FeeWalker::up` under-credits compounding fees by a factor of `key.width()` on non-visited nodes
- [H] Inconsistent high-tick exclusivity between `WalkerLib::modify` and `PoolWalker::settle`
- [M] `TimedAdmin` in `Diamond` breaks `acceptOwnership`, so ownership cannot be transferred
- [M] `NFTManager::tokenURI` reads NFTManager storage instead of Diamond storage and reverts

### Revert StableSwap Hooks (Cantina)
- [H] Native ETH `removeLiquidity` reentrancy prices swaps with stale reserves
- [M] Exact-output swaps can round low-decimal input to zero
