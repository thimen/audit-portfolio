# Premature E8 confidence flooring erases configured swap fees

**Metric**, Sherlock, July 2026, judged **Medium (selected report)**, contest rank 14th  
Contest page: https://audits.sherlock.xyz/contests/1279  
Audited commit: `0d480892a1647e46c3775c95da400a39888a7c78`

This is the submission I sent in. Links into the private contest fork are replaced by file references.

---
## Summary

`AnchoredPriceProvider::_shapedQuote` (`smart-contracts-poc/contracts/AnchoredPriceProvider.sol:360-371`) rounds the confidence-derived half-spread down in the oracle's coarse E8 price domain before converting the quote to Q64.64. On a low-priced asset, a nonzero confidence component can therefore become zero. The later directional Q64.64 rounding cannot recover the discarded value, so the executable bid is too high, the ask is too low, and swaps pay less than the configured fee.

This is realistic within the project's supported production feeds. The repository maps Pyth feed ID 4 to PEPE/USDC (`smart-contracts-poc/script/js/config/ethereum/feeds/default.json:61-65`), while [Pyth's current metadata](https://pyth.dourolabs.app/v1/symbols?query=PEPE) identifies feed ID 4 as `Crypto.PEPE/USD` with exponent `-10`. Pyth defines the represented price as `mantissa * 10^exponent` and confidence as the uncertainty around that price in the same units ([Pyth payload reference](https://docs.pyth.network/price-feeds/pro/payload-reference)).

For a correct report with `price = 29,900`, `exponent = -10`, and `confidence = 62`, normalization produces the exact E8 midpoint `299` and a 21-bps spread. With allowed parameters `confidenceParam = 1,000,000`, `minMargin = 0.5 bp`, and `marginStep = 10 bp`, the production implementation charges a `21.5231622724 bp` base fee instead of `31.0481339999 bp`. This omits `30.6780810966%` of the configured base-fee yield, or approximately `952.497` quote tokens per one million quote tokens of fee-exclusive volume.

## Root Cause

`AnchoredPriceProvider::_shapedQuote` (`smart-contracts-poc/contracts/AnchoredPriceProvider.sol:360-371`) first truncates `delta` to a whole E8 unit:

```solidity
function _shapedQuote(uint256 mid, uint256 spreadBps)
    internal view returns (bool ok, uint256 sBid, uint256 sAsk)
{
@>  uint256 delta = mid * (spreadBps * confidenceParam) / CONFIDENCE_BASE;
    uint256 bid8 = delta >= mid ? 0 : mid - delta;
    uint256 ask8 = mid + delta;

    sBid = _bandEdge(bid8, stepBidFactor, Math.Rounding.Floor);
    sAsk = _bandEdge(ask8, stepAskFactor, Math.Rounding.Ceil);
```

For the values above, the exact delta is:

```text
299 * 21 * 1,000,000 / 10,000,000,000 = 0.6279 E8
```

The implementation stores this as zero, making both `bid8` and `ask8` equal to `299`. `AnchoredPriceProvider::_bandEdge` (`smart-contracts-poc/contracts/AnchoredPriceProvider.sol:244-250`) then applies correct directional rounding, but only after the confidence information has been lost.

The minimum anchored-band clamp in `AnchoredPriceProvider::_computeBidAsk` (`smart-contracts-poc/contracts/AnchoredPriceProvider.sol:299-348`) does not fix the error. It preserves the mandatory `spread + minMargin` boundary, but it cannot restore configured confidence widening that should extend beyond that boundary.

## Internal Pre-conditions

1. A pool uses a mutable `AnchoredPriceProvider` in reference-oracle mode.
2. `confidenceParam` is nonzero and `marginStep` is positive. The demonstrated `confidenceParam` is accepted by `AnchoredPriceProvider::setConfidenceParam` (`smart-contracts-poc/contracts/AnchoredPriceProvider.sol:186-198`), and the demonstrated `marginStep` is within the `AnchoredPriceProvider::constructor` (`smart-contracts-poc/contracts/AnchoredPriceProvider.sol:163-171`) bounds.
3. The configured widths straddle the anchored clamp. In the PoC, the mandatory half-width is `21.5 bp`; the prematurely floored shaped quote is only `10 bp`, while the precision-preserving shaped quote is approximately `31 bp`.
4. The pool has ordinary liquidity and swap volume.

No malicious administrator, abnormal parameter, stale report, or incorrect oracle value is required.

## External Pre-conditions

1. A correct, fresh oracle report normalizes to a low E8 midpoint and a nonzero spread for which the confidence delta is fractional in E8. `LazerConsumer::_normalize` (`smart-contracts-poc/contracts/oracles/utils/LazerConsumer.sol:330-357`) maps the example report to `mid = 299` exactly and `spreadBps = 21`.
2. Users execute routine swaps through the affected pool. No attacker action is necessary.

## Attack Path

1. The oracle supplies the correct normalized midpoint `299` and spread `21`.
2. `_shapedQuote()` computes the nonzero `0.6279 E8` confidence delta but truncates it to zero.
3. The provider consequently returns the mandatory anchored-band endpoints instead of the wider confidence-plus-margin endpoints.
4. `MetricOmmPool::swap` (`metric-core/contracts/MetricOmmPool.sol:217-248`) obtains those endpoints and passes them to `SwapMath::midAndSpreadFeeX64FromBidAsk` (`metric-core/contracts/libraries/SwapMath.sol:64-72`).
5. Every affected swap therefore uses a lower `baseFeeX64` than the configured quote requires.

## Impact

The PoC measures the direct fee-rate consequence:

```text
charged base fee:              21.523162272446495681 bps
precision-preserving base fee: 31.048133999936622113 bps
omitted share of fee yield:    30.6780810966274802%
omitted per 1m volume:         952.497172749012643161 quote tokens
```

This is realized revenue loss, not a view-only quote discrepancy. The understated base fee flows into the swap fee calculation; `SwapMath::buyToken0InBinSpecifiedOut` (`metric-core/contracts/libraries/SwapMath.sol:360-427`), for example, allocates that fee between the configured recipient and the liquidity retained for LPs. Both recipients therefore receive less on affected volume.

The competition README.md expressly requires rounding to favor the pool and recognizes adverse rounding with qualifying impact as valid. Here, the rounding instead raises the executable bid and lowers the executable ask, favoring traders in both directions. Medium severity is appropriate because the loss requires a specific but realistic conjunction of a low-E8 feed, mutable reference mode, and a band-straddling configuration, while the demonstrated fee-yield loss materially exceeds the competition threshold. This is also consistent with [Sherlock's Medium criteria](https://docs.sherlock.xyz/audits/judging/guidelines) for fund loss under specific states or constraints.

## PoC

Add the following test file to `smart-contracts-poc/test/AnchoredConfidenceFlooringPoC.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AnchoredPriceProvider} from "../contracts/AnchoredPriceProvider.sol";
import {IOffchainOracle} from "../contracts/interfaces/IOffchainOracle.sol";
import {OracleBase} from "../contracts/oracles/providers/OracleBase.sol";
import {toTimeMs} from "../contracts/oracles/utils/TimeMs.sol";
import {MockPoolFactory} from "./mocks/MockPoolFactory.sol";

contract ConfidenceFlooringOracle is OracleBase {
    constructor(address owner, uint256 maxTimeDrift) OracleBase(owner, maxTimeDrift) {}

    function setData(bytes32 feedId, uint64 mid, uint16 spreadBps, uint256 refTime) external {
        oracleData[feedId] = IOffchainOracle.OracleData({
            price: mid, spread0: spreadBps, spread1: 0, timestampMs: toTimeMs(refTime * 1000)
        });
    }
}

contract AnchoredConfidenceFlooringPoCTest is Test {
    uint256 private constant Q64 = 1 << 64;
    uint256 private constant BPS_BASE = 1e18;
    uint256 private constant STEP_DENOM = 1e8 * BPS_BASE;
    uint256 private constant ONE_BPS_E18 = 1e14;
    uint256 private constant CONFIDENCE_BASE = 1e10;

    uint64 private constant MID_E8 = 299;
    uint16 private constant SPREAD_BPS = 21;
    uint256 private constant CONFIDENCE_PARAM = 1_000_000;
    uint256 private constant MIN_MARGIN = 5e13; // 0.5 bps per side
    uint256 private constant MARGIN_STEP = 1e15; // 10 bps per side
    uint256 private constant T0 = 1_000_000;

    bytes32 private constant FEED_ID = bytes32(uint256(4));
    address private constant BASE_TOKEN = address(0xBEEF);
    address private constant QUOTE_TOKEN = address(0xCAFE);

    ConfidenceFlooringOracle private oracle;
    AnchoredPriceProvider private provider;

    function inSwap() external view returns (address) {
        return address(provider);
    }

    function setUp() public {
        vm.warp(T0);
        vm.deal(address(this), 1 ether);

        oracle = new ConfidenceFlooringOracle(address(this), 60);
        MockPoolFactory poolFactory = new MockPoolFactory();
        poolFactory.setPool(address(this), true);
        oracle.addApprovedFactory(address(poolFactory));

        provider = new AnchoredPriceProvider(
            address(this),
            address(oracle),
            FEED_ID,
            bytes32(0),
            MIN_MARGIN,
            60,
            150,
            true,
            int256(MARGIN_STEP),
            BASE_TOKEN,
            QUOTE_TOKEN
        );

        oracle.register{value: 1}(FEED_ID, address(this), address(poolFactory));
        oracle.setData(FEED_ID, MID_E8, SPREAD_BPS, block.timestamp);
        provider.setConfidenceParam(CONFIDENCE_PARAM);
    }

    function test_PoC_nonzeroConfidenceIsDeletedAndBaseFeeIsUndercharged() public {
        uint256 confidenceNumerator = uint256(MID_E8) * SPREAD_BPS * CONFIDENCE_PARAM;

        assertEq(confidenceNumerator, 6_279_000_000);
        assertEq(confidenceNumerator / CONFIDENCE_BASE, 0, "0.6279 E8 is prematurely floored to zero");

        (uint128 actualBid, uint128 actualAsk) = provider.getBidAndAskPrice();
        (uint256 fullPrecisionBid, uint256 fullPrecisionAsk) = _fullPrecisionQuote(confidenceNumerator);

        assertEq(uint256(actualBid), 55_037_179_886_113);
        assertEq(uint256(actualAsk), 55_274_349_674_670);
        assertEq(fullPrecisionBid, 54_984_897_736_678);
        assertEq(fullPrecisionAsk, 55_326_863_478_317);
        assertLt(fullPrecisionBid, actualBid, "flooring raises the executable bid");
        assertGt(fullPrecisionAsk, actualAsk, "flooring lowers the executable ask");

        uint256 actualBaseFeeX64 = _poolBaseFee(actualBid, actualAsk);
        uint256 fullPrecisionBaseFeeX64 = _poolBaseFee(fullPrecisionBid, fullPrecisionAsk);
        uint256 missingBaseFeeX64 = fullPrecisionBaseFeeX64 - actualBaseFeeX64;
        uint256 omittedFeeShare = Math.mulDiv(missingBaseFeeX64, 1e18, fullPrecisionBaseFeeX64);
        uint256 omittedPerMillion = Math.mulDiv(1_000_000e18, missingBaseFeeX64, Q64);

        assertGt(omittedFeeShare, 30e16, "more than 30% of configured base-fee yield is omitted");
        assertGt(omittedPerMillion, 952e18, "more than 952 quote tokens omitted per one million");

        emit log_named_decimal_uint("live base fee (bps)", Math.mulDiv(actualBaseFeeX64, 10_000e18, Q64), 18);
        emit log_named_decimal_uint(
            "full-precision base fee (bps)", Math.mulDiv(fullPrecisionBaseFeeX64, 10_000e18, Q64), 18
        );
        emit log_named_decimal_uint("omitted share of fee yield", omittedFeeShare, 18);
        emit log_named_decimal_uint("fee omitted per 1m volume", omittedPerMillion, 18);
    }

    function _fullPrecisionQuote(uint256 confidenceNumerator) private pure returns (uint256 bid, uint256 ask) {
        uint256 midNumerator = uint256(MID_E8) * CONFIDENCE_BASE;
        uint256 denominator = CONFIDENCE_BASE * STEP_DENOM;

        uint256 shapedBid = Math.mulDiv(
            midNumerator - confidenceNumerator, Q64 * (BPS_BASE - MARGIN_STEP), denominator, Math.Rounding.Floor
        );
        uint256 shapedAsk = Math.mulDiv(
            midNumerator + confidenceNumerator, Q64 * (BPS_BASE + MARGIN_STEP), denominator, Math.Rounding.Ceil
        );

        uint256 half = uint256(SPREAD_BPS) * ONE_BPS_E18 + MIN_MARGIN;
        uint256 refBid = Math.mulDiv(MID_E8, Q64 * (BPS_BASE - half), STEP_DENOM, Math.Rounding.Floor);
        uint256 refAsk = Math.mulDiv(MID_E8, Q64 * (BPS_BASE + half), STEP_DENOM, Math.Rounding.Ceil);

        return (Math.min(refBid, shapedBid), Math.max(refAsk, shapedAsk));
    }

    // Exact formula used by SwapMath.midAndSpreadFeeX64FromBidAsk().
    function _poolBaseFee(uint256 bid, uint256 ask) private pure returns (uint256) {
        uint256 mid = Math.sqrt(bid * ask);
        return Math.mulDiv(ask, Q64, mid, Math.Rounding.Ceil) - Q64;
    }
}
```

Run from `smart-contracts-poc/`:

```bash
forge test --mc AnchoredConfidenceFlooringPoCTest -vv
```

Result:

```text
[PASS] test_PoC_nonzeroConfidenceIsDeletedAndBaseFeeIsUndercharged()
Logs:
  live base fee (bps): 21.523162272446495681
  full-precision base fee (bps): 31.048133999936622113
  omitted share of fee yield: 0.306780810966274802
  fee omitted per 1m volume: 952.497172749012643161

Suite result: ok. 1 passed; 0 failed
```

## Mitigation

Do not round the confidence delta to a whole E8 unit. Carry `mid * spreadBps * confidenceParam` as a numerator through the step-factor multiplication and Q64.64 conversion, then independently round the final bid down and ask up before applying the anchored clamp. Preserve the existing overflow and `delta >= mid` guards, and add regression cases where the exact confidence delta lies strictly between zero and one E8 unit.
