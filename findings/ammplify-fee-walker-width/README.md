# `FeeWalker::up` under-credits compounding fees by a factor of `key.width()` on non-visited nodes

**Ammplify**, Sherlock, September 2025, judged **High**, contest rank 23rd  
Contest page: https://audits.sherlock.xyz/contests/1054  
Audited commit: `a8b3f0caeac0422ad298368463dea61c92c03b7e`

This is the submission I sent in. Links into the private contest fork are replaced by file references.

---
## Summary

A missing width multiplier in `FeeWalker::up` (`Ammplify/src/walkers/Fee.sol:255`) will cause an under-crediting of compounding fees by a factor of key.width() at every non-visited node on the way up.

## Root Cause

In `FeeWalker::up` (`Ammplify/src/walkers/Fee.sol:255`) for non-visited nodes, the compounding liquidity is calculated on a node scale

```solidity
uint256 compoundingLiq = node.liq.mLiq - node.liq.ncLiq;
```

This is then multiplied by `colMakerXRateX128`, which expects compoundingLiq to be column-scaled.

```solidity
node.fees.xCFees =
    add128Fees(node.fees.xCFees, FullMath.mulX128(colMakerXRateX128, compoundingLiq, false), data, true);
node.fees.yCFees =
    add128Fees(node.fees.yCFees, FullMath.mulX128(colMakerYRateX128, compoundingLiq, false), data, false);

```

This will cause the Fees to be underreported by a factor of width and therefore reduce compounding rewards for makers.

This is a discrepancy from `FeeWalker::chargeTrueFeeRate` (`Ammplify/src/walkers/Fee.sol:418`), which scales by width correctly
```solidity
uint256 compoundingLiq = width * (node.liq.mLiq - node.liq.ncLiq);
node.fees.xCFees = 
    add128Fees(node.fees.xCFees, FullMath.mulX128(colMakerXRateX128, compoundingLiq, false), data, true);
node.fees.yCFees =
    add128Fees(node.fees.yCFees, FullMath.mulX128(colMakerYRateX128, compoundingLiq, false), data, false);
```

## Internal Pre-conditions

1. The protocol must have a node with `key.width() > 1` and nonzero `mLiq` and `ncLiq`.
2. The walk must reach this node on the up pass with `visit == false`.
3. Maker fees must be present to compound.

## External Pre-conditions

1. The protocol must have multiple ticks or positions aggregated under a single node (width > 1).
2. The pool must generate fees for makers.

## Attack Path

1. A user provides maker liquidity across multiple ticks, creating a node with width > 1.
2. Swap fees are generated and credited to the protocol.
3. The protocol walks up the tree, reaching the node with `visit == false`.
4. FeeWalker::up applies column rates to local liquidity, under-crediting compounding fees by a factor of `width`.

## Impact

Maker compounding fees (xCFees/yCFees) are consumed by LiqWalker::compound on the same up step right after FeeWalker::up.

At non-visited ancestors (including root), compounding balances are under-credited by up to the node’s width factor, causing:
- Under-compounding (too little assignment of new maker liq from fees).
- Persistent under-accounting of compounding fee buckets for these nodes.

Visited nodes (leaves/some siblings) are fine because they use `chargeTrueFeeRate which multiplies by width correctly. The bug affects internal nodes where visit = false — notably including the root (unless root = LCA), making the discrepancy material.

## PoC

No PoC was submitted.

## Mitigation

Change the `compoundingLiq` (`Ammplify/src/walkers/Fee.sol:255`) calculation in `FeeWalker::up` visit == false

```diff
- uint256 compoundingLiq = node.liq.mLiq - node.liq.ncLiq;
+ uint256 compoundingLiq = uint256(key.width()) * (node.liq.mLiq - node.liq.ncLiq);

```
