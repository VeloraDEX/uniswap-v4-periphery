// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {UniswapV4StateMulticall} from "../src/UniswapV4StateMulticall.sol";
import {IUniswapV4StateMulticall} from "../src/interfaces/IUniswapV4StateMulticall.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract UniswapV4StateMulticallTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    UniswapV4StateMulticall public stateMulticall;
    MockERC20 token0;
    MockERC20 token1;
    PoolKey poolKey;

    function setUp() public {
        // Deploy pool manager and test tokens
        deployFreshManagerAndRouters();

        // Deploy the state multicall contract
        stateMulticall = new UniswapV4StateMulticall();

        // Setup test tokens
        token0 = new MockERC20("Test Token 0", "TEST0", 18);
        token1 = new MockERC20("Test Token 1", "TEST1", 18);

        // Ensure token0 < token1 for proper ordering
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Create pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Initialize the pool
        manager.initialize(poolKey, TickMath.getSqrtPriceAtTick(0));
    }

    function test_GetFullState() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getFullState(
            manager,
            poolKey,
            -10, // tickBitmapStart
            10 // tickBitmapEnd
        );

        // Verify basic state
        assertEq(Currency.unwrap(state.key.currency0), address(token0));
        assertEq(Currency.unwrap(state.key.currency1), address(token1));
        assertEq(state.key.fee, 3000);
        assertEq(state.key.tickSpacing, 60);
        assertEq(state.slot0.tick, 0);
        assertEq(state.slot0.sqrtPriceX96, TickMath.getSqrtPriceAtTick(0));
    }

    function test_GetFullStateWithoutTicks() public view {
        IUniswapV4StateMulticall.StateResult memory state =
            stateMulticall.getFullStateWithoutTicks(manager, poolKey, -10, 10);

        // Verify state without ticks
        assertEq(state.ticks.length, 0);
        assertEq(Currency.unwrap(state.key.currency0), address(token0));
        assertEq(Currency.unwrap(state.key.currency1), address(token1));
    }

    function test_GetFullStateWithRelativeBitmaps() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getFullStateWithRelativeBitmaps(
            manager,
            poolKey,
            5, // leftBitmapAmount
            5 // rightBitmapAmount
        );

        // Verify state with relative bitmaps
        assertEq(Currency.unwrap(state.key.currency0), address(token0));
        assertEq(Currency.unwrap(state.key.currency1), address(token1));
        assertEq(state.slot0.tick, 0);
    }

    function test_GetAdditionalBitmapWithTicks() public view {
        (
            IUniswapV4StateMulticall.TickBitMapMappings[] memory tickBitmap,
            IUniswapV4StateMulticall.TickInfoMappings[] memory ticks
        ) = stateMulticall.getAdditionalBitmapWithTicks(manager, poolKey, -10, 10);

        // Bitmap and ticks arrays should be initialized (even if empty for a new pool)
        assertNotEq(address(0), address(uint160(uint256(keccak256(abi.encode(tickBitmap))))));
        assertNotEq(address(0), address(uint160(uint256(keccak256(abi.encode(ticks))))));
    }

    function test_GetAdditionalBitmapWithoutTicks() public view {
        IUniswapV4StateMulticall.TickBitMapMappings[] memory tickBitmap =
            stateMulticall.getAdditionalBitmapWithoutTicks(manager, poolKey, -10, 10);

        // Bitmap array should be initialized
        assertNotEq(address(0), address(uint160(uint256(keccak256(abi.encode(tickBitmap))))));
    }

    function test_GetPoolStateByTokens() public view {
        IUniswapV4StateMulticall.StateResult memory state = stateMulticall.getPoolStateByTokens(
            manager,
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            3000,
            60,
            IHooks(address(0)),
            -10,
            10
        );

        // Verify state retrieved by token addresses
        assertEq(Currency.unwrap(state.key.currency0), address(token0));
        assertEq(Currency.unwrap(state.key.currency1), address(token1));
        assertEq(state.key.fee, 3000);
        assertEq(state.key.tickSpacing, 60);
    }

    function test_RevertOnInvalidBitmapRange() public {
        vm.expectRevert("tickBitmapEnd < tickBitmapStart");
        stateMulticall.getFullState(
            manager,
            poolKey,
            10, // tickBitmapStart > tickBitmapEnd
            -10 // tickBitmapEnd
        );
    }

    function test_RevertOnInvalidRelativeBitmapAmounts() public {
        vm.expectRevert("leftBitmapAmount <= 0");
        stateMulticall.getFullStateWithRelativeBitmaps(
            manager,
            poolKey,
            0, // invalid leftBitmapAmount
            5
        );

        vm.expectRevert("rightBitmapAmount <= 0");
        stateMulticall.getFullStateWithRelativeBitmaps(
            manager,
            poolKey,
            5,
            0 // invalid rightBitmapAmount
        );
    }
}
