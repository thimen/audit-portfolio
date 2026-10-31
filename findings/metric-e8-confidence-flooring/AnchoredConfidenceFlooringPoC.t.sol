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
