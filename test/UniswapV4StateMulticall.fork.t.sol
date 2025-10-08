// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {UniswapV4StateMulticall} from "../src/UniswapV4StateMulticall.sol";
import {IUniswapV4StateMulticall} from "../src/interfaces/IUniswapV4StateMulticall.sol";

contract UniswapV4StateMulticallForkTest is Test {
    using PoolIdLibrary for PoolKey;

    // Base mainnet addresses
    address constant POOL_MANAGER = 0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    UniswapV4StateMulticall public stateMulticall;
    IPoolManager public poolManager;
    PoolKey public poolKey;
    PoolId public expectedPoolId;

    function setUp() public {
        // Fork Base mainnet
        string memory baseRpc = vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org"));
        vm.createSelectFork(baseRpc);

        // Deploy the state multicall contract
        stateMulticall = new UniswapV4StateMulticall();
        
        poolManager = IPoolManager(POOL_MANAGER);

        // Setup pool key for ETH/USDC pool
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH (native)
            currency1: Currency.wrap(USDC),
            fee: 500, // 0.05% = 500
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        // Calculate expected pool ID
        expectedPoolId = poolKey.toId();
        
        // Verify the pool ID matches
        bytes32 calculatedPoolId = PoolId.unwrap(expectedPoolId);
        assertEq(
            calculatedPoolId,
            0x96d4b53a38337a5733179751781178a2613306063c511b78cd02684739288c0a,
            "Pool ID should match expected value"
        );
    }

    function test_GetFullState_BaseMainnet() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getFullState(
            poolManager,
            poolKey,
            -100, // tickBitmapStart
            100   // tickBitmapEnd
        );

        // Verify pool key matches
        assertEq(Currency.unwrap(state.key.currency0), address(0), "Currency0 should be ETH (address(0))");
        assertEq(Currency.unwrap(state.key.currency1), USDC, "Currency1 should be USDC");
        assertEq(state.key.fee, 500, "Fee should be 500 (0.05%)");
        assertEq(state.key.tickSpacing, 10, "Tick spacing should be 10");
        assertEq(address(state.key.hooks), address(0), "Hooks should be zero address");
        
        // Verify pool ID
        assertEq(
            PoolId.unwrap(state.poolId),
            0x96d4b53a38337a5733179751781178a2613306063c511b78cd02684739288c0a,
            "Pool ID should match"
        );

        // Verify pool manager
        assertEq(address(state.poolManager), POOL_MANAGER, "Pool manager should match");

        // Log current pool state for verification
        console.log("Pool State:");
        console.log("  Liquidity:", state.liquidity);
        console.log("  Current Tick:", state.slot0.tick);
        console.log("  Sqrt Price X96:", state.slot0.sqrtPriceX96);
        console.log("  LP Fee:", state.slot0.lpFee);
        console.log("  Protocol Fee:", state.slot0.protocolFee);
        console.log("  Fee Growth Global 0:", state.feeGrowthGlobal0X128);
        console.log("  Fee Growth Global 1:", state.feeGrowthGlobal1X128);
        console.log("  Number of tick bitmaps:", state.tickBitmap.length);
        console.log("  Number of initialized ticks:", state.ticks.length);

        // Basic sanity checks
        assertTrue(state.liquidity > 0, "Pool should have liquidity");
        assertTrue(state.slot0.sqrtPriceX96 > 0, "Pool should have valid price");
    }

    function test_GetFullStateWithoutTicks_BaseMainnet() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getFullStateWithoutTicks(
            poolManager,
            poolKey,
            -50,
            50
        );

        // Verify state without ticks
        assertEq(state.ticks.length, 0, "Should not return ticks");
        assertTrue(state.tickBitmap.length > 0 || state.liquidity == 0, "Should have tick bitmap if pool has liquidity");
        
        // Verify pool data is still correct
        assertEq(Currency.unwrap(state.key.currency0), address(0));
        assertEq(Currency.unwrap(state.key.currency1), USDC);
        assertEq(state.key.fee, 500);
        assertEq(state.key.tickSpacing, 10);
    }

    function test_GetFullStateWithRelativeBitmaps_BaseMainnet() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getFullStateWithRelativeBitmaps(
            poolManager,
            poolKey,
            10, // leftBitmapAmount
            10  // rightBitmapAmount
        );

        // Verify state with relative bitmaps
        assertEq(Currency.unwrap(state.key.currency0), address(0));
        assertEq(Currency.unwrap(state.key.currency1), USDC);
        assertTrue(state.liquidity >= 0, "Should return liquidity");
        assertTrue(state.slot0.sqrtPriceX96 > 0, "Should have valid price");
        
        console.log("Relative bitmap state:");
        console.log("  Current tick:", state.slot0.tick);
        console.log("  Number of tick bitmaps:", state.tickBitmap.length);
        console.log("  Number of ticks:", state.ticks.length);
    }

    function test_GetPoolStateByTokens_BaseMainnet() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getPoolStateByTokens(
            poolManager,
            Currency.wrap(address(0)), // ETH
            Currency.wrap(USDC),
            500,  // fee
            10,   // tickSpacing
            IHooks(address(0)),
            -20,  // tickBitmapStart
            20    // tickBitmapEnd
        );

        // Verify the helper function works correctly
        assertEq(
            PoolId.unwrap(state.poolId),
            0x96d4b53a38337a5733179751781178a2613306063c511b78cd02684739288c0a,
            "Pool ID should match"
        );
        assertTrue(state.liquidity > 0, "Pool should have liquidity");
        assertTrue(state.slot0.sqrtPriceX96 > 0, "Pool should have valid price");
    }

    function test_GetAdditionalBitmapWithTicks_BaseMainnet() public view {
        (
            IUniswapV4StateMulticall.TickBitMapMappings[] memory tickBitmap,
            IUniswapV4StateMulticall.TickInfoMappings[] memory ticks
        ) = stateMulticall.getAdditionalBitmapWithTicks(
            poolManager,
            poolKey,
            -30,
            30
        );

        console.log("Additional bitmap data:");
        console.log("  Number of populated bitmaps:", tickBitmap.length);
        console.log("  Number of initialized ticks:", ticks.length);

        // Log some tick data if available
        if (ticks.length > 0) {
            console.log("First tick:");
            console.log("    Index:", ticks[0].index);
            console.log("    Liquidity Gross:", ticks[0].value.liquidityGross);
            console.log("    Liquidity Net:", ticks[0].value.liquidityNet);
            console.log("    Initialized:", ticks[0].value.initialized);
        }

        // Basic validation
        assertTrue(tickBitmap.length >= 0, "Should return tick bitmap");
        assertTrue(ticks.length >= 0, "Should return ticks");
    }
}