# D3 liquidation uses the manipulable DexV2 spot price to weight the liquidation penalty

**Fluid DEX v2** · Sherlock · January 2026 · judged **Medium** · contest rank 7th  
Contest page: https://audits.sherlock.xyz/contests/1225  
Audited commit: `bd466082e02cb70b2746e882e544ba99cb328fc5` (public repo: https://github.com/sherlock-audit/2026-01-fluid-dex-v2)

Submission text as filed, with links to the private contest fork replaced by file references.

---
## Summary

When liquidating a D3 collateral position, the Money Market computes an **average liquidation penalty** by weighting token0/token1 penalties by the position’s **current token composition/value**. That composition is derived using `_getD3SupplyAmounts(... sqrtPriceX96: AT_POOL_PRICE)`, which resolves to the **current DexV2 pool spot `currentSqrtPrice`**.

Because DexV2 swaps are permissionless, a liquidator can **swap to move the pool spot price** immediately before liquidation, shifting the computed weights toward the higher-penalty token and **increasing seized collateral** for the same payback amount (bounded by configured caps).

## Root Cause

In the D3 liquidation withdraw path, the contract:
1) fetches D3 amounts using **spot price** (`AT_POOL_PRICE`), then  
2) uses those spot-dependent amounts to compute a value-weighted penalty.

From `fluid-contracts/contracts/protocols/moneyMarket/core/liquidateModule/main.sol:365-379`

```solidity
(
    vl_.token0SupplyAmount,
    vl_.token1SupplyAmount,
    feeAccruedToken0_,
    feeAccruedToken1_
) = _getD3SupplyAmounts(
    _getDexId(dexKey_),
    GetD3D4AmountsParams({
        tickLower: s_.tickLower,
        tickUpper: s_.tickUpper,
        positionSalt: s_.positionSalt,
        token0Decimals: vl_.token0Decimals,
        token1Decimals: vl_.token1Decimals,
        token0ExchangePrice: token0SupplyExchangePrice_,
        token1ExchangePrice: token1SupplyExchangePrice_,
        sqrtPriceX96: AT_POOL_PRICE
    })
);

// ...prices from oracle...
uint256 supplyValue0_ = (((vl_.token0SupplyAmount * vl_.token0Price) + 1) / 1e18) + 1;
uint256 supplyValue1_ = (((vl_.token1SupplyAmount * vl_.token1Price) + 1) / 1e18) + 1;

averageLiquidationPenalty_ =
    ((vl_.token0LiquidationPenalty * supplyValue0_) +
     (vl_.token1LiquidationPenalty * supplyValue1_)) / (supplyValue0_ + supplyValue1_);

v_.withdrawValue = ((v_.withdrawValue * (1000 + averageLiquidationPenalty_)) - 1) / 1000;
```

`AT_POOL_PRICE` resolves to DexV2’s stored spot `currentSqrtPrice` in helpers.sol:

```solidity
if (params_.sqrtPriceX96 == AT_POOL_PRICE) {
    params_.sqrtPriceX96 = (dexVariables_ >> DSL.BITS_DEX_V2_VARIABLES_CURRENT_SQRT_PRICE) & X72;
    params_.sqrtPriceX96 = BM.fromBigNumber(params_.sqrtPriceX96, DEFAULT_EXPONENT_SIZE, DEFAULT_EXPONENT_MASK);
}
(token0SupplyAmount_, token1SupplyAmount_) = LA.getAmountsForLiquidity(uint160(params_.sqrtPriceX96), ...);
```

DexV2 spot price is permissionlessly movable via swaps (started through `startOperation()` in main.sol) and executed via the D3 swap module `fluid-contracts/contracts/protocols/dexV2/dexTypes/d3/core/swapModule.sol:10`.

## Internal Pre-conditions

- A liquidatable NFT has a **D3 collateral position**.
- The D3 tokens have **different liquidation penalties** (or are capped differently by `maxLiquidationPenalty`), so the weighted average can change.

## External Pre-conditions

- The liquidator can perform DexV2 swaps for the pool (permissionless).
- There is sufficient pool liquidity to move the spot price enough to measurably change the D3 token composition/value split (even within a bounded range).

## Attack Path

1. Identify a liquidatable NFT with a D3 collateral position.
2. Perform one or more DexV2 swaps to move the pool’s **spot** `currentSqrtPrice` in a direction that increases the D3 position’s inferred value-weight toward the **higher-penalty** token.
3. Call `MoneyMarket.liquidate()` with the same payback amount.
4. Because `averageLiquidationPenalty_` is computed from spot-dependent `token0SupplyAmount/token1SupplyAmount`, the penalty increases and the liquidator **seizes more collateral** than they would have at the unmanipulated spot price.

## Impact

**additional user loss during liquidation (MEV/economic manipulation).**

- A liquidator can systematically increase seized collateral for a given payback by manipulating DexV2 spot price right before liquidation.
- The gain is **bounded** by configured liquidation penalties and `maxLiquidationPenalty` (computed during liquidation), but can still be materially large per liquidation.

Measured in the PoC (same pre-state, same payback):
- seized value without spot manipulation ≈ **$3,738**
- seized value after manipulation ≈ **$3,976**
- delta ≈ **$238** extra collateral seized

## PoC

Test file: [`D3LiquidationPenaltyManipulationPoC.t.sol`](D3LiquidationPenaltyManipulationPoC.t.sol). Copy it to `fluid-contracts/test/foundry/moneyMarket/` in the contest repo at the commit above, then run:

```bash
cd fluid-contracts && npm ci --ignore-scripts && forge test --match-contract D3LiquidationPenaltyManipulationPoC -vv
```

Observed output (re-run 2026-10-31, Foundry 1.5.1):

```text
[PASS] test_poc_d3LiquidationSeizeChangesWithSpotPrice() (gas: 17217749)
Logs:
  seizedValueA (USD e18): 3737999988124350988000
  seizedValueB (USD e18): 3975998664990089132000
  delta (USD e18): 237998676865738144000
```

Requires solc 0.8.29 (Foundry 1.5 or later).

## Mitigation

Use a composition/weighting input that is not liquidator-controllable at liquidation time, for example:

- **Decouple penalty-weighting from pool spot price:** compute the D3 amounts for weighting using an oracle-implied `sqrtPriceX96` (similar to how `_getHfInfo()` derives a price from oracle prices) instead of `AT_POOL_PRICE`, while still executing the actual withdraw at the real pool price.
- **Conservative weighting rule:** ensure the penalty used cannot be increased by shifting composition (e.g., use `min(token0LP, token1LP)` or another non-increasing function with respect to composition changes).
