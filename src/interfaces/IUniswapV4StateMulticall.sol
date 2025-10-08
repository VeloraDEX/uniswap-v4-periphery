// SPDX-License-Identifier: ISC
pragma solidity 0.8.26;
pragma abicoder v2;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

interface IUniswapV4StateMulticall {
    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // protocol fee for the pool
        uint24 protocolFee;
        // lp fee for the pool
        uint24 lpFee;
    }

    struct TickInfo {
        // the total position liquidity that references this tick
        uint128 liquidityGross;
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left)
        int128 liquidityNet;
        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // true if the tick is initialized
        bool initialized;
    }

    struct TickBitMapMappings {
        int16 index;
        uint256 value;
    }

    struct TickInfoMappings {
        int24 index;
        TickInfo value;
    }

    struct StateResult {
        IPoolManager poolManager;
        PoolId poolId;
        PoolKey key;
        uint256 blockTimestamp;
        Slot0 slot0;
        uint128 liquidity;
        int24 tickSpacing;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        TickBitMapMappings[] tickBitmap;
        TickInfoMappings[] ticks;
    }

    function getFullState(IPoolManager poolManager, PoolKey calldata key, int16 tickBitmapStart, int16 tickBitmapEnd)
        external
        view
        returns (StateResult memory state);

    function getFullStateWithoutTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (StateResult memory state);

    function getFullStateWithRelativeBitmaps(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 leftBitmapAmount,
        int16 rightBitmapAmount
    ) external view returns (StateResult memory state);

    function getAdditionalBitmapWithTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (TickBitMapMappings[] memory tickBitmap, TickInfoMappings[] memory ticks);

    function getAdditionalBitmapWithoutTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (TickBitMapMappings[] memory tickBitmap);

    function getPoolStateByTokens(
        IPoolManager poolManager,
        Currency currency0,
        Currency currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (StateResult memory state);
}
