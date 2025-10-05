// SPDX-License-Identifier: ISC
pragma solidity 0.8.26;
pragma abicoder v2;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import "./interfaces/IUniswapV4StateMulticall.sol";

// laita
contract UniswapV4StateMulticall is IUniswapV4StateMulticall {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    function getFullState(IPoolManager poolManager, PoolKey calldata key, int16 tickBitmapStart, int16 tickBitmapEnd)
        external
        view
        override
        returns (StateResult memory state)
    {
        require(tickBitmapEnd >= tickBitmapStart, "tickBitmapEnd < tickBitmapStart");

        state = _fillStateWithoutTicks(poolManager, key, tickBitmapStart, tickBitmapEnd);
        state.ticks = _calcTicksFromBitMap(poolManager, key, state.tickBitmap);
    }

    function getFullStateWithoutTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view override returns (StateResult memory state) {
        require(tickBitmapEnd >= tickBitmapStart, "tickBitmapEnd < tickBitmapStart");

        return _fillStateWithoutTicks(poolManager, key, tickBitmapStart, tickBitmapEnd);
    }

    function getFullStateWithRelativeBitmaps(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 leftBitmapAmount,
        int16 rightBitmapAmount
    ) external view override returns (StateResult memory state) {
        require(leftBitmapAmount > 0, "leftBitmapAmount <= 0");
        require(rightBitmapAmount > 0, "rightBitmapAmount <= 0");

        state = _fillStateWithoutBitmapsAndTicks(poolManager, key);
        int16 currentBitmapIndex = _getBitmapIndexFromTick(state.slot0.tick / key.tickSpacing);

        state.tickBitmap = _calcTickBitmaps(
            poolManager, key, currentBitmapIndex - leftBitmapAmount, currentBitmapIndex + rightBitmapAmount
        );
        state.ticks = _calcTicksFromBitMap(poolManager, key, state.tickBitmap);
    }

    function getAdditionalBitmapWithTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view override returns (TickBitMapMappings[] memory tickBitmap, TickInfoMappings[] memory ticks) {
        require(tickBitmapEnd >= tickBitmapStart, "tickBitmapEnd < tickBitmapStart");

        tickBitmap = _calcTickBitmaps(poolManager, key, tickBitmapStart, tickBitmapEnd);
        ticks = _calcTicksFromBitMap(poolManager, key, tickBitmap);
    }

    function getAdditionalBitmapWithoutTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view override returns (TickBitMapMappings[] memory tickBitmap) {
        require(tickBitmapEnd >= tickBitmapStart, "tickBitmapEnd < tickBitmapStart");

        return _calcTickBitmaps(poolManager, key, tickBitmapStart, tickBitmapEnd);
    }

    function _fillStateWithoutTicks(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) internal view returns (StateResult memory state) {
        state = _fillStateWithoutBitmapsAndTicks(poolManager, key);
        state.tickBitmap = _calcTickBitmaps(poolManager, key, tickBitmapStart, tickBitmapEnd);
    }

    function _fillStateWithoutBitmapsAndTicks(IPoolManager poolManager, PoolKey calldata key)
        internal
        view
        returns (StateResult memory state)
    {
        PoolId poolId = key.toId();

        // Check if pool exists by trying to get liquidity
        state.liquidity = poolManager.getLiquidity(poolId);

        state.poolManager = poolManager;
        state.poolId = poolId;
        state.key = key;
        state.blockTimestamp = block.timestamp;
        state.tickSpacing = key.tickSpacing;

        // Get slot0 data
        (state.slot0.sqrtPriceX96, state.slot0.tick, state.slot0.protocolFee, state.slot0.lpFee) =
            poolManager.getSlot0(poolId);

        // Get fee growth globals
        (state.feeGrowthGlobal0X128, state.feeGrowthGlobal1X128) = poolManager.getFeeGrowthGlobals(poolId);
    }

    function _calcTickBitmaps(
        IPoolManager poolManager,
        PoolKey calldata key,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) internal view returns (TickBitMapMappings[] memory tickBitmap) {
        PoolId poolId = key.toId();

        uint256 numberOfPopulatedBitmaps = 0;
        for (int256 i = tickBitmapStart; i <= tickBitmapEnd; i++) {
            uint256 bitmap = poolManager.getTickBitmap(poolId, int16(i));
            if (bitmap == 0) continue;
            numberOfPopulatedBitmaps++;
        }

        tickBitmap = new TickBitMapMappings[](numberOfPopulatedBitmaps);
        uint256 globalIndex = 0;
        for (int256 i = tickBitmapStart; i <= tickBitmapEnd; i++) {
            int16 index = int16(i);
            uint256 bitmap = poolManager.getTickBitmap(poolId, index);
            if (bitmap == 0) continue;

            tickBitmap[globalIndex] = TickBitMapMappings({index: index, value: bitmap});
            globalIndex++;
        }
    }

    function _calcTicksFromBitMap(
        IPoolManager poolManager,
        PoolKey calldata key,
        TickBitMapMappings[] memory tickBitmap
    ) internal view returns (TickInfoMappings[] memory ticks) {
        PoolId poolId = key.toId();

        uint256 numberOfPopulatedTicks = 0;
        for (uint256 i = 0; i < tickBitmap.length; i++) {
            uint256 bitmap = tickBitmap[i].value;

            for (uint256 j = 0; j < 256; j++) {
                if (bitmap & (1 << j) > 0) numberOfPopulatedTicks++;
            }
        }

        ticks = new TickInfoMappings[](numberOfPopulatedTicks);
        int24 tickSpacing = key.tickSpacing;

        uint256 globalIndex = 0;
        for (uint256 i = 0; i < tickBitmap.length; i++) {
            uint256 bitmap = tickBitmap[i].value;

            for (uint256 j = 0; j < 256; j++) {
                if (bitmap & (1 << j) > 0) {
                    int24 populatedTick = ((int24(tickBitmap[i].index) << 8) + int24(uint24(j))) * tickSpacing;

                    ticks[globalIndex].index = populatedTick;

                    // Get tick info from pool manager
                    (
                        uint128 liquidityGross,
                        int128 liquidityNet,
                        uint256 feeGrowthOutside0X128,
                        uint256 feeGrowthOutside1X128
                    ) = poolManager.getTickInfo(poolId, populatedTick);

                    TickInfo memory newTickInfo = ticks[globalIndex].value;
                    newTickInfo.liquidityGross = liquidityGross;
                    newTickInfo.liquidityNet = liquidityNet;
                    newTickInfo.feeGrowthOutside0X128 = feeGrowthOutside0X128;
                    newTickInfo.feeGrowthOutside1X128 = feeGrowthOutside1X128;
                    newTickInfo.initialized = liquidityGross != 0;

                    ticks[globalIndex].value = newTickInfo;
                    globalIndex++;
                }
            }
        }
    }

    function _getBitmapIndexFromTick(int24 tick) internal pure returns (int16) {
        return int16(tick >> 8);
    }

    // Additional helper function to get pool state by tokens and fee
    function getPoolStateByTokens(
        IPoolManager poolManager,
        Currency currency0,
        Currency currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (StateResult memory state) {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks});

        return this.getFullState(poolManager, key, tickBitmapStart, tickBitmapEnd);
    }
}
