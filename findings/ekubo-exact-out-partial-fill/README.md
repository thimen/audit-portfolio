# Exact-Out Swaps Fill Partially, Exposing Users to Bad Execution Prices

**Ekubo**, Code4rena, November 2025, judged **Medium**, contest rank 2nd  
Contest page: https://code4rena.com/audits/2025-11-ekubo  
Contest repository: https://github.com/code-423n4/2025-11-ekubo  
Credited on M-04, Router does not check if Exact Out Single Swap was partial leading to unexpected results for the users: https://code4rena.com/reports/2025-11-ekubo#m-04-router-does-not-check-if-exact-out-single-swap-was-partial-leading-to-unexpected-results-for-the-users

This is the submission I sent in. The run command repeats `forge test`, as submitted. Remove the repeat to run it.

---
## Finding description and impact

The Core.swap function allows exact-output swaps (specified by a negative amount) to return successfully even if the requested amount was not fully filled. This occurs when the swap reaches the sqrtRatioLimit (price limit) or runs out of liquidity.

In Core.sol:

```solidity
// src/Core.sol:806
if (amountRemaining == 0 || sqrtRatio == sqrtRatioLimit) {
    break;
}
```

The loop breaks if sqrtRatio == sqrtRatioLimit regardless of amountRemaining. The function then returns the partial balanceUpdate without reverting.

Similarly, Router.sol (single-hop path) checks the input amount against calculatedAmountThreshold (max input) but does not verify that the output amount matches the requested exact output.

```solidity
// src/Router.sol:116
int128 amountCalculated = params.isToken1() ? -balanceUpdate.delta0() : -balanceUpdate.delta1();
if (amountCalculated < calculatedAmountThreshold) {
    revert SlippageCheckFailed(calculatedAmountThreshold, amountCalculated);
}
```

Impact:

This behavior breaks the standard invariant for exact-output swaps ("fill or revert"). Users typically calculate their maximum input amount (calculatedAmountThreshold) based on the full output amount and an expected average price.

If a swap is partially filled, the user might pay for the filled portion at a price that is significantly worse than the expected average price. However, the transaction succeeds because the total input amount paid for the partial fill is less than the maximum allowed for the full order.

This exposes users to attacks where a malicious actor:

1. Manipulates the pool price to be very unfavorable (expensive).
2. Provides a small amount of liquidity at this bad price.
3. The user's exact-output swap consumes this expensive liquidity.
4. The swap stops (partial fill) because liquidity runs out or price limit is reached.
5. The user pays a high price per unit for the small amount received.
6. The transaction succeeds because the total input paid is small (due to the small output amount), bypassing the calculatedAmountThreshold check.

## Recommended mitigation steps

Enforce that exact-output swaps must be fully filled.

In Core.swap, revert if isExactOut and amountRemaining != 0 when the loop breaks due to price limit.

```solidity
if (amountRemaining == 0 || sqrtRatio == sqrtRatioLimit) {
    if (isExactOut && amountRemaining != 0) revert ExactOutputNotFilled();
    break;
}
```

Alternatively, update Router.sol to verify that the output delta matches the requested amount for exact-output swaps.

## Proof of Concept

The following test demonstrates that an exact-output swap for 1000 units succeeds even when only 99 units are available, and the user pays for those 99 units.

Create a new file PoC_ExactOutPartialFill.t.sol:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {FullTest} from "./FullTest.sol";
import {PoolKey} from "../src/types/poolKey.sol";
import {SqrtRatio, MIN_SQRT_RATIO, MAX_SQRT_RATIO} from "../src/types/sqrtRatio.sol";
import {TokenAmount, RouteNode} from "../src/Router.sol";
import {PoolBalanceUpdate} from "../src/types/poolBalanceUpdate.sol";
import {PoolState} from "../src/types/poolState.sol";
import {tickToSqrtRatio} from "../src/math/ticks.sol";
import {CoreStorageLayout} from "../src/libraries/CoreStorageLayout.sol";
import {PoolId} from "../src/types/poolId.sol";
import "forge-std/console.sol";

contract PoC_ExactOutPartialFill is FullTest {
    function test_exactOut_partialFill() public {
        // Create pool at tick 0. Price = 1.
        PoolKey memory poolKey = createPool(0, 100, 100); 

        // Add liquidity in range [-100, 100].
        // This liquidity supports trading in both directions around tick 0.
        // We add a small amount (100 units) to simulate thin liquidity.
        createPosition(poolKey, -100, 100, 100, 100);
        
        // Swap 0 -> 1 (Buy Token1).
        // User requests Exact Output 1000 Token1.
        int128 exactOutAmount = -1000;
        // User is willing to pay up to 2000 Token0 (assuming full fill).
        uint128 maxInputAmount = 2000;
        
        token0.approve(address(router), maxInputAmount);
        
        // Execute swap
        PoolBalanceUpdate update = router.swap(
            poolKey,
            true, // isToken1 (Output 1)
            exactOutAmount,
            MIN_SQRT_RATIO, // Price Limit (Down)
            0,
            -int256(uint256(maxInputAmount)), // calculatedAmountThreshold (max input, negative)
            address(this)
        );
        
        console.log("Swap 0 -> 1 (Buy Token1)");
        console.log("Output (Token1):", uint128(-update.delta1()));
        console.log("Input (Token0):", uint128(update.delta0()));
        
        // Assertions
        // The user requested 1000 but got less (partial fill)
        assertTrue(uint128(-update.delta1()) < uint128(-exactOutAmount), "Should be partial fill");
        // The user paid some input
        assertTrue(update.delta0() > 0, "Should have paid input");
        // The transaction succeeded despite partial fill
    }
}
```

Run with:

```
forge test --forge test --match-contract PoC_ExactOutPartialFill -vv
```
