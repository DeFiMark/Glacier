// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/InputHelpers.sol";
import "../balancer-labs/v2-solidity-utils/contracts/helpers/LogCompression.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";

import "@balancer-labs/v2-pool-utils/contracts/BasePoolAuthorization.sol";
import "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";

import "../balancer-labs/v2-vault/contracts/interfaces/IBasePool.sol";

import "./WeightedMath.sol";
import "./WeightedOracleMath.sol";
import "./WeightedPoolUserDataHelpers.sol";
import "./WeightedPool2TokensMiscData.sol";

library Samples {
    using WordCodec for int256;
    using WordCodec for uint256;
    using WordCodec for bytes32;

    uint256 internal constant _TIMESTAMP_OFFSET = 0;
    uint256 internal constant _ACC_LOG_INVARIANT_OFFSET = 31;
    uint256 internal constant _INST_LOG_INVARIANT_OFFSET = 84;
    uint256 internal constant _ACC_LOG_BPT_PRICE_OFFSET = 106;
    uint256 internal constant _INST_LOG_BPT_PRICE_OFFSET = 159;
    uint256 internal constant _ACC_LOG_PAIR_PRICE_OFFSET = 181;
    uint256 internal constant _INST_LOG_PAIR_PRICE_OFFSET = 234;

    /**
     * @dev Updates a sample, accumulating the new data based on the elapsed time since the previous update. Returns the
     * updated sample.
     *
     * IMPORTANT: This function does not perform any arithmetic checks. In particular, it assumes the caller will never
     * pass values that cannot be represented as 22 bit signed integers. Additionally, it also assumes
     * `currentTimestamp` is greater than `sample`'s timestamp.
     */
    function update(
        bytes32 sample,
        int256 instLogPairPrice,
        int256 instLogBptPrice,
        int256 instLogInvariant,
        uint256 currentTimestamp
    ) internal pure returns (bytes32) {
        // Because elapsed can be represented as a 31 bit unsigned integer, and the received values can be represented
        // as 22 bit signed integers, we don't need to perform checked arithmetic.

        int256 elapsed = int256(currentTimestamp - timestamp(sample));
        int256 accLogPairPrice = _accLogPairPrice(sample) +
            instLogPairPrice *
            elapsed;
        int256 accLogBptPrice = _accLogBptPrice(sample) +
            instLogBptPrice *
            elapsed;
        int256 accLogInvariant = _accLogInvariant(sample) +
            instLogInvariant *
            elapsed;

        return
            pack(
                instLogPairPrice,
                accLogPairPrice,
                instLogBptPrice,
                accLogBptPrice,
                instLogInvariant,
                accLogInvariant,
                currentTimestamp
            );
    }

    /**
     * @dev Returns the instant value stored in `sample` for `variable`.
     */
    function instant(bytes32 sample, IPriceOracle.Variable variable)
        internal
        pure
        returns (int256)
    {
        if (variable == IPriceOracle.Variable.PAIR_PRICE) {
            return _instLogPairPrice(sample);
        } else if (variable == IPriceOracle.Variable.BPT_PRICE) {
            return _instLogBptPrice(sample);
        } else {
            // variable == IPriceOracle.Variable.INVARIANT
            return _instLogInvariant(sample);
        }
    }

    /**
     * @dev Returns the accumulator value stored in `sample` for `variable`.
     */
    function accumulator(bytes32 sample, IPriceOracle.Variable variable)
        internal
        pure
        returns (int256)
    {
        if (variable == IPriceOracle.Variable.PAIR_PRICE) {
            return _accLogPairPrice(sample);
        } else if (variable == IPriceOracle.Variable.BPT_PRICE) {
            return _accLogBptPrice(sample);
        } else {
            // variable == IPriceOracle.Variable.INVARIANT
            return _accLogInvariant(sample);
        }
    }

    /**
     * @dev Returns `sample`'s timestamp.
     */
    function timestamp(bytes32 sample) internal pure returns (uint256) {
        return sample.decodeUint31(_TIMESTAMP_OFFSET);
    }

    /**
     * @dev Returns `sample`'s instant value for the logarithm of the pair price.
     */
    function _instLogPairPrice(bytes32 sample) private pure returns (int256) {
        return sample.decodeInt22(_INST_LOG_PAIR_PRICE_OFFSET);
    }

    /**
     * @dev Returns `sample`'s accumulator of the logarithm of the pair price.
     */
    function _accLogPairPrice(bytes32 sample) private pure returns (int256) {
        return sample.decodeInt53(_ACC_LOG_PAIR_PRICE_OFFSET);
    }

    /**
     * @dev Returns `sample`'s instant value for the logarithm of the BPT price.
     */
    function _instLogBptPrice(bytes32 sample) private pure returns (int256) {
        return sample.decodeInt22(_INST_LOG_BPT_PRICE_OFFSET);
    }

    /**
     * @dev Returns `sample`'s accumulator of the logarithm of the BPT price.
     */
    function _accLogBptPrice(bytes32 sample) private pure returns (int256) {
        return sample.decodeInt53(_ACC_LOG_BPT_PRICE_OFFSET);
    }

    /**
     * @dev Returns `sample`'s instant value for the logarithm of the invariant.
     */
    function _instLogInvariant(bytes32 sample) private pure returns (int256) {
        return sample.decodeInt22(_INST_LOG_INVARIANT_OFFSET);
    }

    /**
     * @dev Returns `sample`'s accumulator of the logarithm of the invariant.
     */
    function _accLogInvariant(bytes32 sample) private pure returns (int256) {
        return sample.decodeInt53(_ACC_LOG_INVARIANT_OFFSET);
    }

    /**
     * @dev Returns a sample created by packing together its components.
     */
    function pack(
        int256 instLogPairPrice,
        int256 accLogPairPrice,
        int256 instLogBptPrice,
        int256 accLogBptPrice,
        int256 instLogInvariant,
        int256 accLogInvariant,
        uint256 _timestamp
    ) internal pure returns (bytes32) {
        return
            instLogPairPrice.encodeInt22(_INST_LOG_PAIR_PRICE_OFFSET) |
            accLogPairPrice.encodeInt53(_ACC_LOG_PAIR_PRICE_OFFSET) |
            instLogBptPrice.encodeInt22(_INST_LOG_BPT_PRICE_OFFSET) |
            accLogBptPrice.encodeInt53(_ACC_LOG_BPT_PRICE_OFFSET) |
            instLogInvariant.encodeInt22(_INST_LOG_INVARIANT_OFFSET) |
            accLogInvariant.encodeInt53(_ACC_LOG_INVARIANT_OFFSET) |
            _timestamp.encodeUint(_TIMESTAMP_OFFSET); // Using 31 bits
    }

    /**
     * @dev Unpacks a sample into its components.
     */
    function unpack(bytes32 sample)
        internal
        pure
        returns (
            int256 logPairPrice,
            int256 accLogPairPrice,
            int256 logBptPrice,
            int256 accLogBptPrice,
            int256 logInvariant,
            int256 accLogInvariant,
            uint256 _timestamp
        )
    {
        logPairPrice = _instLogPairPrice(sample);
        accLogPairPrice = _accLogPairPrice(sample);
        logBptPrice = _instLogBptPrice(sample);
        accLogBptPrice = _accLogBptPrice(sample);
        logInvariant = _instLogInvariant(sample);
        accLogInvariant = _accLogInvariant(sample);
        _timestamp = timestamp(sample);
    }
}

library Buffer {
    // The buffer is a circular storage structure with 1024 slots.
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 internal constant SIZE = 1024;

    /**
     * @dev Returns the index of the element before the one pointed by `index`.
     */
    function prev(uint256 index) internal pure returns (uint256) {
        return sub(index, 1);
    }

    /**
     * @dev Returns the index of the element after the one pointed by `index`.
     */
    function next(uint256 index) internal pure returns (uint256) {
        return add(index, 1);
    }

    /**
     * @dev Returns the index of an element `offset` slots after the one pointed by `index`.
     */
    function add(uint256 index, uint256 offset)
        internal
        pure
        returns (uint256)
    {
        return (index + offset) % SIZE;
    }

    /**
     * @dev Returns the index of an element `offset` slots before the one pointed by `index`.
     */
    function sub(uint256 index, uint256 offset)
        internal
        pure
        returns (uint256)
    {
        return (index + SIZE - offset) % SIZE;
    }
}

interface IPriceOracle {
    // The three values that can be queried:
    //
    // - PAIR_PRICE: the price of the tokens in the Pool, expressed as the price of the second token in units of the
    //   first token. For example, if token A is worth $2, and token B is worth $4, the pair price will be 2.0.
    //   Note that the price is computed *including* the tokens decimals. This means that the pair price of a Pool with
    //   DAI and USDC will be close to 1.0, despite DAI having 18 decimals and USDC 6.
    //
    // - BPT_PRICE: the price of the Pool share token (BPT), in units of the first token.
    //   Note that the price is computed *including* the tokens decimals. This means that the BPT price of a Pool with
    //   USDC in which BPT is worth $5 will be 5.0, despite the BPT having 18 decimals and USDC 6.
    //
    // - INVARIANT: the value of the Pool's invariant, which serves as a measure of its liquidity.
    enum Variable {
        PAIR_PRICE,
        BPT_PRICE,
        INVARIANT
    }

    /**
     * @dev Returns the time average weighted price corresponding to each of `queries`. Prices are represented as 18
     * decimal fixed point values.
     */
    function getTimeWeightedAverage(OracleAverageQuery[] memory queries)
        external
        view
        returns (uint256[] memory results);

    /**
     * @dev Returns latest sample of `variable`. Prices are represented as 18 decimal fixed point values.
     */
    function getLatest(Variable variable) external view returns (uint256);

    /**
     * @dev Information for a Time Weighted Average query.
     *
     * Each query computes the average over a window of duration `secs` seconds that ended `ago` seconds ago. For
     * example, the average over the past 30 minutes is computed by settings secs to 1800 and ago to 0. If secs is 1800
     * and ago is 1800 as well, the average between 60 and 30 minutes ago is computed instead.
     */
    struct OracleAverageQuery {
        Variable variable;
        uint256 secs;
        uint256 ago;
    }

    /**
     * @dev Returns largest time window that can be safely queried, where 'safely' means the Oracle is guaranteed to be
     * able to produce a result and not revert.
     *
     * If a query has a non-zero `ago` value, then `secs + ago` (the oldest point in time) must be smaller than this
     * value for 'safe' queries.
     */
    function getLargestSafeQueryWindow() external view returns (uint256);

    /**
     * @dev Returns the accumulators corresponding to each of `queries`.
     */
    function getPastAccumulators(OracleAccumulatorQuery[] memory queries)
        external
        view
        returns (int256[] memory results);

    /**
     * @dev Information for an Accumulator query.
     *
     * Each query estimates the accumulator at a time `ago` seconds ago.
     */
    struct OracleAccumulatorQuery {
        Variable variable;
        uint256 ago;
    }
}

contract PoolPriceOracle is IPoolPriceOracle {
    using Buffer for uint256;
    using Samples for bytes32;

    // Each sample in the buffer accumulates information for up to 2 minutes. This is simply to reduce the size of the
    // buffer: small time deviations will not have any significant effect.
    // solhint-disable not-rely-on-time
    uint256 private constant _MAX_SAMPLE_DURATION = 2 minutes;

    // We use a mapping to simulate an array: the buffer won't grow or shrink, and since we will always use valid
    // indexes using a mapping saves gas by skipping the bounds checks.
    mapping(uint256 => bytes32) internal _samples;

    function getSample(uint256 index)
        external
        view
        override
        returns (
            int256 logPairPrice,
            int256 accLogPairPrice,
            int256 logBptPrice,
            int256 accLogBptPrice,
            int256 logInvariant,
            int256 accLogInvariant,
            uint256 timestamp
        )
    {
        _require(index < Buffer.SIZE, Errors.ORACLE_INVALID_INDEX);

        bytes32 sample = _getSample(index);
        return sample.unpack();
    }

    function getTotalSamples() external pure override returns (uint256) {
        return Buffer.SIZE;
    }

    /**
     * @dev Processes new price and invariant data, updating the latest sample or creating a new one.
     *
     * Receives the new logarithms of values to store: `logPairPrice`, `logBptPrice` and `logInvariant`, as well the
     * index of the latest sample and the timestamp of its creation.
     *
     * Returns the index of the latest sample. If different from `latestIndex`, the caller should also store the
     * timestamp, and pass it on future calls to this function.
     */
    function _processPriceData(
        uint256 latestSampleCreationTimestamp,
        uint256 latestIndex,
        int256 logPairPrice,
        int256 logBptPrice,
        int256 logInvariant
    ) internal returns (uint256) {
        // Read latest sample, and compute the next one by updating it with the newly received data.
        bytes32 sample = _getSample(latestIndex).update(
            logPairPrice,
            logBptPrice,
            logInvariant,
            block.timestamp
        );

        // We create a new sample if more than _MAX_SAMPLE_DURATION seconds have elapsed since the creation of the
        // latest one. In other words, no sample accumulates data over a period larger than _MAX_SAMPLE_DURATION.
        bool newSample = block.timestamp - latestSampleCreationTimestamp >=
            _MAX_SAMPLE_DURATION;
        latestIndex = newSample ? latestIndex.next() : latestIndex;

        // Store the updated or new sample.
        _samples[latestIndex] = sample;

        return latestIndex;
    }

    /**
     * @dev Returns the instant value for `variable` in the sample pointed to by `index`.
     */
    function _getInstantValue(IPriceOracle.Variable variable, uint256 index)
        internal
        view
        returns (int256)
    {
        bytes32 sample = _getSample(index);
        _require(sample.timestamp() > 0, Errors.ORACLE_NOT_INITIALIZED);

        return sample.instant(variable);
    }

    /**
     * @dev Returns the value of the accumulator for `variable` `ago` seconds ago. `latestIndex` must be the index of
     * the latest sample in the buffer.
     *
     * Reverts under the following conditions:
     *  - if the buffer is empty.
     *  - if querying past information and the buffer has not been fully initialized.
     *  - if querying older information than available in the buffer. Note that a full buffer guarantees queries for the
     *    past 34 hours will not revert.
     *
     * If requesting information for a timestamp later than the latest one, it is extrapolated using the latest
     * available data.
     *
     * When no exact information is available for the requested past timestamp (as usually happens, since at most one
     * timestamp is stored every two minutes), it is estimated by performing linear interpolation using the closest
     * values. This process is guaranteed to complete performing at most 10 storage reads.
     */
    function _getPastAccumulator(
        IPriceOracle.Variable variable,
        uint256 latestIndex,
        uint256 ago
    ) internal view returns (int256) {
        // `ago` must not be before the epoch.
        _require(block.timestamp >= ago, Errors.ORACLE_INVALID_SECONDS_QUERY);
        uint256 lookUpTime = block.timestamp - ago;

        bytes32 latestSample = _getSample(latestIndex);
        uint256 latestTimestamp = latestSample.timestamp();

        // The latest sample only has a non-zero timestamp if no data was ever processed and stored in the buffer.
        _require(latestTimestamp > 0, Errors.ORACLE_NOT_INITIALIZED);

        if (latestTimestamp <= lookUpTime) {
            // The accumulator at times ahead of the latest one are computed by extrapolating the latest data. This is
            // equivalent to the instant value not changing between the last timestamp and the look up time.

            // We can use unchecked arithmetic since the accumulator can be represented in 53 bits, timestamps in 31
            // bits, and the instant value in 22 bits.
            uint256 elapsed = lookUpTime - latestTimestamp;
            return
                latestSample.accumulator(variable) +
                (latestSample.instant(variable) * int256(elapsed));
        } else {
            // The look up time is before the latest sample, but we need to make sure that it is not before the oldest
            // sample as well.

            // Since we use a circular buffer, the oldest sample is simply the next one.
            uint256 oldestIndex = latestIndex.next();
            {
                // Local scope used to prevent stack-too-deep errors.
                bytes32 oldestSample = _getSample(oldestIndex);
                uint256 oldestTimestamp = oldestSample.timestamp();

                // For simplicity's sake, we only perform past queries if the buffer has been fully initialized. This
                // means the oldest sample must have a non-zero timestamp.
                _require(oldestTimestamp > 0, Errors.ORACLE_NOT_INITIALIZED);
                // The only remaining condition to check is for the look up time to be between the oldest and latest
                // timestamps.
                _require(
                    oldestTimestamp <= lookUpTime,
                    Errors.ORACLE_QUERY_TOO_OLD
                );
            }

            // Perform binary search to find nearest samples to the desired timestamp.
            (bytes32 prev, bytes32 next) = _findNearestSample(
                lookUpTime,
                oldestIndex
            );

            // `next`'s timestamp is guaranteed to be larger than `prev`'s, so we can skip checked arithmetic.
            uint256 samplesTimeDiff = next.timestamp() - prev.timestamp();

            if (samplesTimeDiff > 0) {
                // We estimate the accumulator at the requested look up time by interpolating linearly between the
                // previous and next accumulators.

                // We can use unchecked arithmetic since the accumulators can be represented in 53 bits, and timestamps
                // in 31 bits.
                int256 samplesAccDiff = next.accumulator(variable) -
                    prev.accumulator(variable);
                uint256 elapsed = lookUpTime - prev.timestamp();
                return
                    prev.accumulator(variable) +
                    ((samplesAccDiff * int256(elapsed)) /
                        int256(samplesTimeDiff));
            } else {
                // Rarely, one of the samples will have the exact requested look up time, which is indicated by `prev`
                // and `next` being the same. In this case, we simply return the accumulator at that point in time.
                return prev.accumulator(variable);
            }
        }
    }

    /**
     * @dev Finds the two samples with timestamps before and after `lookUpDate`. If one of the samples matches exactly,
     * both `prev` and `next` will be it. `offset` is the index of the oldest sample in the buffer.
     *
     * Assumes `lookUpDate` is greater or equal than the timestamp of the oldest sample, and less or equal than the
     * timestamp of the latest sample.
     */
    function _findNearestSample(uint256 lookUpDate, uint256 offset)
        internal
        view
        returns (bytes32 prev, bytes32 next)
    {
        // We're going to perform a binary search in the circular buffer, which requires it to be sorted. To achieve
        // this, we offset all buffer accesses by `offset`, making the first element the oldest one.

        // Auxiliary variables in a typical binary search: we will look at some value `mid` between `low` and `high`,
        // periodically increasing `low` or decreasing `high` until we either find a match or determine the element is
        // not in the array.
        uint256 low = 0;
        uint256 high = Buffer.SIZE - 1;
        uint256 mid;

        // If the search fails and no sample has a timestamp of `lookUpDate` (as is the most common scenario), `sample`
        // will be either the sample with the largest timestamp smaller than `lookUpDate`, or the one with the smallest
        // timestamp larger than `lookUpDate`.
        bytes32 sample;
        uint256 sampleTimestamp;

        while (low <= high) {
            // Mid is the floor of the average.
            uint256 midWithoutOffset = (high + low) / 2;

            // Recall that the buffer is not actually sorted: we need to apply the offset to access it in a sorted way.
            mid = midWithoutOffset.add(offset);
            sample = _getSample(mid);
            sampleTimestamp = sample.timestamp();

            if (sampleTimestamp < lookUpDate) {
                // If the mid sample is bellow the look up date, then increase the low index to start from there.
                low = midWithoutOffset + 1;
            } else if (sampleTimestamp > lookUpDate) {
                // If the mid sample is above the look up date, then decrease the high index to start from there.

                // We can skip checked arithmetic: it is impossible for `high` to ever be 0, as a scenario where `low`
                // equals 0 and `high` equals 1 would result in `low` increasing to 1 in the previous `if` clause.
                high = midWithoutOffset - 1;
            } else {
                // sampleTimestamp == lookUpDate
                // If we have an exact match, return the sample as both `prev` and `next`.
                return (sample, sample);
            }
        }

        // In case we reach here, it means we didn't find exactly the sample we where looking for.
        return
            sampleTimestamp < lookUpDate
                ? (sample, _getSample(mid.next()))
                : (_getSample(mid.prev()), sample);
    }

    /**
     * @dev Returns the sample that corresponds to a given `index`.
     *
     * Using this function instead of accessing storage directly results in denser bytecode (since the storage slot is
     * only computed here).
     */
    function _getSample(uint256 index) internal view returns (bytes32) {
        return _samples[index];
    }
}

interface IMinimalSwapInfoPool is IBasePool {
    function onSwap(
        SwapRequest memory swapRequest,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut
    ) external returns (uint256 amount);
}

contract WeightedPool2Tokens is
    IMinimalSwapInfoPool,
    IPriceOracle,
    BasePoolAuthorization,
    BalancerPoolToken,
    TemporarilyPausable,
    PoolPriceOracle,
    WeightedMath,
    WeightedOracleMath
{
    using FixedPoint for uint256;
    using WeightedPoolUserDataHelpers for bytes;
    using WeightedPool2TokensMiscData for bytes32;

    uint256 private constant _MINIMUM_BPT = 1e6;

    // 1e18 corresponds to 1.0, or a 100% fee
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 1e17; // 10%
    // The swap fee is internally stored using 64 bits, which is enough to represent _MAX_SWAP_FEE_PERCENTAGE.

    bytes32 internal _miscData;
    uint256 private _lastInvariant;

    IVault private immutable _vault;
    bytes32 private immutable _poolId;

    IERC20 internal immutable _token0;
    IERC20 internal immutable _token1;

    uint256 private immutable _normalizedWeight0;
    uint256 private immutable _normalizedWeight1;

    // The protocol fees will always be charged using the token associated with the max weight in the pool.
    // Since these Pools will register tokens only once, we can assume this index will be constant.
    uint256 private immutable _maxWeightTokenIndex;

    // All token balances are normalized to behave as if the token had 18 decimals. We assume a token's decimals will
    // not change throughout its lifetime, and store the corresponding scaling factor for each at construction time.
    // These factors are always greater than or equal to one: tokens with more than 18 decimals are not supported.
    uint256 internal immutable _scalingFactor0;
    uint256 internal immutable _scalingFactor1;

    event OracleEnabledChanged(bool enabled);
    event SwapFeePercentageChanged(uint256 swapFeePercentage);

    modifier onlyVault(bytes32 poolId) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }

    struct NewPoolParams {
        IVault vault;
        string name;
        string symbol;
        IERC20 token0;
        IERC20 token1;
        uint256 normalizedWeight0;
        uint256 normalizedWeight1;
        uint256 swapFeePercentage;
        uint256 pauseWindowDuration;
        uint256 bufferPeriodDuration;
        bool oracleEnabled;
        address owner;
    }

    constructor(NewPoolParams memory params)
        // Base Pools are expected to be deployed using factories. By using the factory address as the action
        // disambiguator, we make all Pools deployed by the same factory share action identifiers. This allows for
        // simpler management of permissions (such as being able to manage granting the 'set fee percentage' action in
        // any Pool created by the same factory), while still making action identifiers unique among different factories
        // if the selectors match, preventing accidental errors.
        Authentication(bytes32(uint256(msg.sender)))
        BalancerPoolToken(params.name, params.symbol)
        BasePoolAuthorization(params.owner)
        TemporarilyPausable(
            params.pauseWindowDuration,
            params.bufferPeriodDuration
        )
    {
        _setOracleEnabled(params.oracleEnabled);
        _setSwapFeePercentage(params.swapFeePercentage);

        bytes32 poolId = params.vault.registerPool(
            IVault.PoolSpecialization.TWO_TOKEN
        );

        // Pass in zero addresses for Asset Managers
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = params.token0;
        tokens[1] = params.token1;
        params.vault.registerTokens(poolId, tokens, new address[](2));

        // Set immutable state variables - these cannot be read from during construction
        _vault = params.vault;
        _poolId = poolId;

        _token0 = params.token0;
        _token1 = params.token1;

        _scalingFactor0 = _computeScalingFactor(params.token0);
        _scalingFactor1 = _computeScalingFactor(params.token1);

        // Ensure each normalized weight is above them minimum and find the token index of the maximum weight
        _require(params.normalizedWeight0 >= _MIN_WEIGHT, Errors.MIN_WEIGHT);
        _require(params.normalizedWeight1 >= _MIN_WEIGHT, Errors.MIN_WEIGHT);

        // Ensure that the normalized weights sum to ONE
        uint256 normalizedSum = params.normalizedWeight0.add(
            params.normalizedWeight1
        );
        _require(
            normalizedSum == FixedPoint.ONE,
            Errors.NORMALIZED_WEIGHT_INVARIANT
        );

        _normalizedWeight0 = params.normalizedWeight0;
        _normalizedWeight1 = params.normalizedWeight1;
        _maxWeightTokenIndex = params.normalizedWeight0 >=
            params.normalizedWeight1
            ? 0
            : 1;
    }

    // Getters / Setters

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }

    function getMiscData()
        external
        view
        returns (
            int256 logInvariant,
            int256 logTotalSupply,
            uint256 oracleSampleCreationTimestamp,
            uint256 oracleIndex,
            bool oracleEnabled,
            uint256 swapFeePercentage
        )
    {
        bytes32 miscData = _miscData;
        logInvariant = miscData.logInvariant();
        logTotalSupply = miscData.logTotalSupply();
        oracleSampleCreationTimestamp = miscData.oracleSampleCreationTimestamp();
        oracleIndex = miscData.oracleIndex();
        oracleEnabled = miscData.oracleEnabled();
        swapFeePercentage = miscData.swapFeePercentage();
    }

    function getSwapFeePercentage() public view returns (uint256) {
        return _miscData.swapFeePercentage();
    }

    // Caller must be approved by the Vault's Authorizer
    function setSwapFeePercentage(uint256 swapFeePercentage)
        public
        virtual
        authenticate
        whenNotPaused
    {
        _setSwapFeePercentage(swapFeePercentage);
    }

    function _setSwapFeePercentage(uint256 swapFeePercentage) private {
        _require(
            swapFeePercentage >= _MIN_SWAP_FEE_PERCENTAGE,
            Errors.MIN_SWAP_FEE_PERCENTAGE
        );
        _require(
            swapFeePercentage <= _MAX_SWAP_FEE_PERCENTAGE,
            Errors.MAX_SWAP_FEE_PERCENTAGE
        );

        _miscData = _miscData.setSwapFeePercentage(swapFeePercentage);
        emit SwapFeePercentageChanged(swapFeePercentage);
    }

    function _isOwnerOnlyAction(bytes32 actionId)
        internal
        view
        virtual
        override
        returns (bool)
    {
        return
            (actionId == getActionId(BasePool.setSwapFeePercentage.selector)) ||
            (actionId ==
                getActionId(BasePool.setAssetManagerPoolConfig.selector));
    }

    /**
     * @dev Balancer Governance can always enable the Oracle, even if it was originally not enabled. This allows for
     * Pools that unexpectedly drive much more volume and liquidity than expected to serve as Price Oracles.
     *
     * Note that the Oracle can only be enabled - it can never be disabled.
     */
    function enableOracle() external whenNotPaused authenticate {
        _setOracleEnabled(true);

        // Cache log invariant and supply only if the pool was initialized
        if (totalSupply() > 0) {
            _cacheInvariantAndSupply();
        }
    }

    function _setOracleEnabled(bool enabled) internal {
        _miscData = _miscData.setOracleEnabled(enabled);
        emit OracleEnabledChanged(enabled);
    }

    // Caller must be approved by the Vault's Authorizer
    function setPaused(bool paused) external authenticate {
        _setPaused(paused);
    }

    function getNormalizedWeights() external view returns (uint256[] memory) {
        return _normalizedWeights();
    }

    function _normalizedWeights()
        internal
        view
        virtual
        returns (uint256[] memory)
    {
        uint256[] memory normalizedWeights = new uint256[](2);
        normalizedWeights[0] = _normalizedWeights(true);
        normalizedWeights[1] = _normalizedWeights(false);
        return normalizedWeights;
    }

    function _normalizedWeights(bool token0)
        internal
        view
        virtual
        returns (uint256)
    {
        return token0 ? _normalizedWeight0 : _normalizedWeight1;
    }

    function getLastInvariant() external view returns (uint256) {
        return _lastInvariant;
    }

    /**
     * @dev Returns the current value of the invariant.
     */
    function getInvariant() public view returns (uint256) {
        (, uint256[] memory balances, ) = getVault().getPoolTokens(getPoolId());

        // Since the Pool hooks always work with upscaled balances, we manually
        // upscale here for consistency
        _upscaleArray(balances);

        uint256[] memory normalizedWeights = _normalizedWeights();
        return WeightedMath._calculateInvariant(normalizedWeights, balances);
    }

    // Swap Hooks

    function onSwap(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut
    )
        public
        virtual
        override
        whenNotPaused
        onlyVault(request.poolId)
        returns (uint256)
    {
        bool tokenInIsToken0 = request.tokenIn == _token0;

        uint256 scalingFactorTokenIn = _scalingFactor(tokenInIsToken0);
        uint256 scalingFactorTokenOut = _scalingFactor(!tokenInIsToken0);

        uint256 normalizedWeightIn = _normalizedWeights(tokenInIsToken0);
        uint256 normalizedWeightOut = _normalizedWeights(!tokenInIsToken0);

        // All token amounts are upscaled.
        balanceTokenIn = _upscale(balanceTokenIn, scalingFactorTokenIn);
        balanceTokenOut = _upscale(balanceTokenOut, scalingFactorTokenOut);

        // Update price oracle with the pre-swap balances
        _updateOracle(
            request.lastChangeBlock,
            tokenInIsToken0 ? balanceTokenIn : balanceTokenOut,
            tokenInIsToken0 ? balanceTokenOut : balanceTokenIn
        );

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // Fees are subtracted before scaling, to reduce the complexity of the rounding direction analysis.
            // This is amount - fee amount, so we round up (favoring a higher fee amount).
            uint256 feeAmount = request.amount.mulUp(getSwapFeePercentage());
            request.amount = _upscale(
                request.amount.sub(feeAmount),
                scalingFactorTokenIn
            );

            uint256 amountOut = _onSwapGivenIn(
                request,
                balanceTokenIn,
                balanceTokenOut,
                normalizedWeightIn,
                normalizedWeightOut
            );

            // amountOut tokens are exiting the Pool, so we round down.
            return _downscaleDown(amountOut, scalingFactorTokenOut);
        } else {
            request.amount = _upscale(request.amount, scalingFactorTokenOut);

            uint256 amountIn = _onSwapGivenOut(
                request,
                balanceTokenIn,
                balanceTokenOut,
                normalizedWeightIn,
                normalizedWeightOut
            );

            // amountIn tokens are entering the Pool, so we round up.
            amountIn = _downscaleUp(amountIn, scalingFactorTokenIn);

            // Fees are added after scaling happens, to reduce the complexity of the rounding direction analysis.
            // This is amount + fee amount, so we round up (favoring a higher fee amount).
            return amountIn.divUp(getSwapFeePercentage().complement());
        }
    }

    function _onSwapGivenIn(
        SwapRequest memory swapRequest,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 normalizedWeightIn,
        uint256 normalizedWeightOut
    ) private pure returns (uint256) {
        // Swaps are disabled while the contract is paused.
        return
            WeightedMath._calcOutGivenIn(
                currentBalanceTokenIn,
                normalizedWeightIn,
                currentBalanceTokenOut,
                normalizedWeightOut,
                swapRequest.amount
            );
    }

    function _onSwapGivenOut(
        SwapRequest memory swapRequest,
        uint256 currentBalanceTokenIn,
        uint256 currentBalanceTokenOut,
        uint256 normalizedWeightIn,
        uint256 normalizedWeightOut
    ) private pure returns (uint256) {
        // Swaps are disabled while the contract is paused.
        return
            WeightedMath._calcInGivenOut(
                currentBalanceTokenIn,
                normalizedWeightIn,
                currentBalanceTokenOut,
                normalizedWeightOut,
                swapRequest.amount
            );
    }

    // Join Hook

    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    )
        public
        virtual
        override
        onlyVault(poolId)
        whenNotPaused
        returns (
            uint256[] memory amountsIn,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        // All joins, including initializations, are disabled while the contract is paused.

        uint256 bptAmountOut;
        if (totalSupply() == 0) {
            (bptAmountOut, amountsIn) = _onInitializePool(
                poolId,
                sender,
                recipient,
                userData
            );

            // On initialization, we lock _MINIMUM_BPT by minting it for the zero address. This BPT acts as a minimum
            // as it will never be burned, which reduces potential issues with rounding, and also prevents the Pool from
            // ever being fully drained.
            _require(bptAmountOut >= _MINIMUM_BPT, Errors.MINIMUM_BPT);
            _mintPoolTokens(address(0), _MINIMUM_BPT);
            _mintPoolTokens(recipient, bptAmountOut - _MINIMUM_BPT);

            // amountsIn are amounts entering the Pool, so we round up.
            _downscaleUpArray(amountsIn);

            // There are no due protocol fee amounts during initialization
            dueProtocolFeeAmounts = new uint256[](2);
        } else {
            _upscaleArray(balances);

            // Update price oracle with the pre-join balances
            _updateOracle(lastChangeBlock, balances[0], balances[1]);

            (bptAmountOut, amountsIn, dueProtocolFeeAmounts) = _onJoinPool(
                poolId,
                sender,
                recipient,
                balances,
                lastChangeBlock,
                protocolSwapFeePercentage,
                userData
            );

            // Note we no longer use `balances` after calling `_onJoinPool`, which may mutate it.

            _mintPoolTokens(recipient, bptAmountOut);

            // amountsIn are amounts entering the Pool, so we round up.
            _downscaleUpArray(amountsIn);
            // dueProtocolFeeAmounts are amounts exiting the Pool, so we round down.
            _downscaleDownArray(dueProtocolFeeAmounts);
        }

        // Update cached total supply and invariant using the results after the join that will be used for future
        // oracle updates.
        _cacheInvariantAndSupply();
    }

    /**
     * @dev Called when the Pool is joined for the first time; that is, when the BPT total supply is zero.
     *
     * Returns the amount of BPT to mint, and the token amounts the Pool will receive in return.
     *
     * Minted BPT will be sent to `recipient`, except for _MINIMUM_BPT, which will be deducted from this amount and sent
     * to the zero address instead. This will cause that BPT to remain forever locked there, preventing total BTP from
     * ever dropping below that value, and ensuring `_onInitializePool` can only be called once in the entire Pool's
     * lifetime.
     *
     * The tokens granted to the Pool will be transferred from `sender`. These amounts are considered upscaled and will
     * be downscaled (rounding up) before being returned to the Vault.
     */
    function _onInitializePool(
        bytes32,
        address,
        address,
        bytes memory userData
    ) private returns (uint256, uint256[] memory) {
        BaseWeightedPool.JoinKind kind = userData.joinKind();
        _require(kind == BaseWeightedPool.JoinKind.INIT, Errors.UNINITIALIZED);

        uint256[] memory amountsIn = userData.initialAmountsIn();
        InputHelpers.ensureInputLengthMatch(amountsIn.length, 2);
        _upscaleArray(amountsIn);

        uint256[] memory normalizedWeights = _normalizedWeights();

        uint256 invariantAfterJoin = WeightedMath._calculateInvariant(
            normalizedWeights,
            amountsIn
        );

        // Set the initial BPT to the value of the invariant times the number of tokens. This makes BPT supply more
        // consistent in Pools with similar compositions but different number of tokens.
        uint256 bptAmountOut = Math.mul(invariantAfterJoin, 2);

        _lastInvariant = invariantAfterJoin;

        return (bptAmountOut, amountsIn);
    }

    /**
     * @dev Called whenever the Pool is joined after the first initialization join (see `_onInitializePool`).
     *
     * Returns the amount of BPT to mint, the token amounts that the Pool will receive in return, and the number of
     * tokens to pay in protocol swap fees.
     *
     * Implementations of this function might choose to mutate the `balances` array to save gas (e.g. when
     * performing intermediate calculations, such as subtraction of due protocol fees). This can be done safely.
     *
     * Minted BPT will be sent to `recipient`.
     *
     * The tokens granted to the Pool will be transferred from `sender`. These amounts are considered upscaled and will
     * be downscaled (rounding up) before being returned to the Vault.
     *
     * Due protocol swap fees will be taken from the Pool's balance in the Vault (see `IBasePool.onJoinPool`). These
     * amounts are considered upscaled and will be downscaled (rounding down) before being returned to the Vault.
     */
    function _onJoinPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    )
        private
        returns (
            uint256,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256[] memory normalizedWeights = _normalizedWeights();

        // Due protocol swap fee amounts are computed by measuring the growth of the invariant between the previous join
        // or exit event and now - the invariant's growth is due exclusively to swap fees. This avoids spending gas
        // computing them on each individual swap
        uint256 invariantBeforeJoin = WeightedMath._calculateInvariant(
            normalizedWeights,
            balances
        );

        uint256[] memory dueProtocolFeeAmounts = _getDueProtocolFeeAmounts(
            balances,
            normalizedWeights,
            _lastInvariant,
            invariantBeforeJoin,
            protocolSwapFeePercentage
        );

        // Update current balances by subtracting the protocol fee amounts
        _mutateAmounts(balances, dueProtocolFeeAmounts, FixedPoint.sub);
        (uint256 bptAmountOut, uint256[] memory amountsIn) = _doJoin(
            balances,
            normalizedWeights,
            userData
        );

        // Update the invariant with the balances the Pool will have after the join, in order to compute the
        // protocol swap fee amounts due in future joins and exits.
        _mutateAmounts(balances, amountsIn, FixedPoint.add);
        _lastInvariant = WeightedMath._calculateInvariant(
            normalizedWeights,
            balances
        );

        return (bptAmountOut, amountsIn, dueProtocolFeeAmounts);
    }

    function _doJoin(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        bytes memory userData
    ) private view returns (uint256, uint256[] memory) {
        BaseWeightedPool.JoinKind kind = userData.joinKind();

        if (kind == BaseWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT) {
            return
                _joinExactTokensInForBPTOut(
                    balances,
                    normalizedWeights,
                    userData
                );
        } else if (
            kind == BaseWeightedPool.JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT
        ) {
            return
                _joinTokenInForExactBPTOut(
                    balances,
                    normalizedWeights,
                    userData
                );
        } else {
            _revert(Errors.UNHANDLED_JOIN_KIND);
        }
    }

    function _joinExactTokensInForBPTOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        bytes memory userData
    ) private view returns (uint256, uint256[] memory) {
        (uint256[] memory amountsIn, uint256 minBPTAmountOut) = userData
            .exactTokensInForBptOut();
        InputHelpers.ensureInputLengthMatch(amountsIn.length, 2);

        _upscaleArray(amountsIn);

        uint256 bptAmountOut = WeightedMath._calcBptOutGivenExactTokensIn(
            balances,
            normalizedWeights,
            amountsIn,
            totalSupply(),
            getSwapFeePercentage()
        );

        _require(bptAmountOut >= minBPTAmountOut, Errors.BPT_OUT_MIN_AMOUNT);

        return (bptAmountOut, amountsIn);
    }

    function _joinTokenInForExactBPTOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        bytes memory userData
    ) private view returns (uint256, uint256[] memory) {
        (uint256 bptAmountOut, uint256 tokenIndex) = userData
            .tokenInForExactBptOut();
        // Note that there is no maximum amountIn parameter: this is handled by `IVault.joinPool`.

        _require(tokenIndex < 2, Errors.OUT_OF_BOUNDS);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[tokenIndex] = WeightedMath._calcTokenInGivenExactBptOut(
            balances[tokenIndex],
            normalizedWeights[tokenIndex],
            bptAmountOut,
            totalSupply(),
            getSwapFeePercentage()
        );

        return (bptAmountOut, amountsIn);
    }

    // Exit Hook

    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    )
        public
        virtual
        override
        onlyVault(poolId)
        returns (uint256[] memory, uint256[] memory)
    {
        _upscaleArray(balances);

        (
            uint256 bptAmountIn,
            uint256[] memory amountsOut,
            uint256[] memory dueProtocolFeeAmounts
        ) = _onExitPool(
                poolId,
                sender,
                recipient,
                balances,
                lastChangeBlock,
                protocolSwapFeePercentage,
                userData
            );

        // Note we no longer use `balances` after calling `_onExitPool`, which may mutate it.

        _burnPoolTokens(sender, bptAmountIn);

        // Both amountsOut and dueProtocolFeeAmounts are amounts exiting the Pool, so we round down.
        _downscaleDownArray(amountsOut);
        _downscaleDownArray(dueProtocolFeeAmounts);

        // Update cached total supply and invariant using the results after the exit that will be used for future
        // oracle updates, only if the pool was not paused (to minimize code paths taken while paused).
        if (_isNotPaused()) {
            _cacheInvariantAndSupply();
        }

        return (amountsOut, dueProtocolFeeAmounts);
    }

    /**
     * @dev Called whenever the Pool is exited.
     *
     * Returns the amount of BPT to burn, the token amounts for each Pool token that the Pool will grant in return, and
     * the number of tokens to pay in protocol swap fees.
     *
     * Implementations of this function might choose to mutate the `balances` array to save gas (e.g. when
     * performing intermediate calculations, such as subtraction of due protocol fees). This can be done safely.
     *
     * BPT will be burnt from `sender`.
     *
     * The Pool will grant tokens to `recipient`. These amounts are considered upscaled and will be downscaled
     * (rounding down) before being returned to the Vault.
     *
     * Due protocol swap fees will be taken from the Pool's balance in the Vault (see `IBasePool.onExitPool`). These
     * amounts are considered upscaled and will be downscaled (rounding down) before being returned to the Vault.
     */
    function _onExitPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    )
        private
        returns (
            uint256 bptAmountIn,
            uint256[] memory amountsOut,
            uint256[] memory dueProtocolFeeAmounts
        )
    {
        // Exits are not completely disabled while the contract is paused: proportional exits (exact BPT in for tokens
        // out) remain functional.

        uint256[] memory normalizedWeights = _normalizedWeights();

        if (_isNotPaused()) {
            // Update price oracle with the pre-exit balances
            _updateOracle(lastChangeBlock, balances[0], balances[1]);

            // Due protocol swap fee amounts are computed by measuring the growth of the invariant between the previous
            // join or exit event and now - the invariant's growth is due exclusively to swap fees. This avoids
            // spending gas calculating the fees on each individual swap.
            uint256 invariantBeforeExit = WeightedMath._calculateInvariant(
                normalizedWeights,
                balances
            );
            dueProtocolFeeAmounts = _getDueProtocolFeeAmounts(
                balances,
                normalizedWeights,
                _lastInvariant,
                invariantBeforeExit,
                protocolSwapFeePercentage
            );

            // Update current balances by subtracting the protocol fee amounts
            _mutateAmounts(balances, dueProtocolFeeAmounts, FixedPoint.sub);
        } else {
            // If the contract is paused, swap protocol fee amounts are not charged and the oracle is not updated
            // to avoid extra calculations and reduce the potential for errors.
            dueProtocolFeeAmounts = new uint256[](2);
        }

        (bptAmountIn, amountsOut) = _doExit(
            balances,
            normalizedWeights,
            userData
        );

        // Update the invariant with the balances the Pool will have after the exit, in order to compute the
        // protocol swap fees due in future joins and exits.
        _mutateAmounts(balances, amountsOut, FixedPoint.sub);
        _lastInvariant = WeightedMath._calculateInvariant(
            normalizedWeights,
            balances
        );

        return (bptAmountIn, amountsOut, dueProtocolFeeAmounts);
    }

    function _doExit(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        bytes memory userData
    ) private view returns (uint256, uint256[] memory) {
        BaseWeightedPool.ExitKind kind = userData.exitKind();

        if (kind == BaseWeightedPool.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT) {
            return
                _exitExactBPTInForTokenOut(
                    balances,
                    normalizedWeights,
                    userData
                );
        } else if (
            kind == BaseWeightedPool.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT
        ) {
            return _exitExactBPTInForTokensOut(balances, userData);
        } else {
            // ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT
            return
                _exitBPTInForExactTokensOut(
                    balances,
                    normalizedWeights,
                    userData
                );
        }
    }

    function _exitExactBPTInForTokenOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        bytes memory userData
    ) private view whenNotPaused returns (uint256, uint256[] memory) {
        // This exit function is disabled if the contract is paused.

        (uint256 bptAmountIn, uint256 tokenIndex) = userData
            .exactBptInForTokenOut();
        // Note that there is no minimum amountOut parameter: this is handled by `IVault.exitPool`.

        _require(tokenIndex < 2, Errors.OUT_OF_BOUNDS);

        // We exit in a single token, so we initialize amountsOut with zeros
        uint256[] memory amountsOut = new uint256[](2);

        // And then assign the result to the selected token
        amountsOut[tokenIndex] = WeightedMath._calcTokenOutGivenExactBptIn(
            balances[tokenIndex],
            normalizedWeights[tokenIndex],
            bptAmountIn,
            totalSupply(),
            getSwapFeePercentage()
        );

        return (bptAmountIn, amountsOut);
    }

    function _exitExactBPTInForTokensOut(
        uint256[] memory balances,
        bytes memory userData
    ) private view returns (uint256, uint256[] memory) {
        // This exit function is the only one that is not disabled if the contract is paused: it remains unrestricted
        // in an attempt to provide users with a mechanism to retrieve their tokens in case of an emergency.
        // This particular exit function is the only one that remains available because it is the simplest one, and
        // therefore the one with the lowest likelihood of errors.

        uint256 bptAmountIn = userData.exactBptInForTokensOut();
        // Note that there is no minimum amountOut parameter: this is handled by `IVault.exitPool`.

        uint256[] memory amountsOut = WeightedMath
            ._calcTokensOutGivenExactBptIn(
                balances,
                bptAmountIn,
                totalSupply()
            );
        return (bptAmountIn, amountsOut);
    }

    function _exitBPTInForExactTokensOut(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        bytes memory userData
    ) private view whenNotPaused returns (uint256, uint256[] memory) {
        // This exit function is disabled if the contract is paused.

        (uint256[] memory amountsOut, uint256 maxBPTAmountIn) = userData
            .bptInForExactTokensOut();
        InputHelpers.ensureInputLengthMatch(amountsOut.length, 2);
        _upscaleArray(amountsOut);

        uint256 bptAmountIn = WeightedMath._calcBptInGivenExactTokensOut(
            balances,
            normalizedWeights,
            amountsOut,
            totalSupply(),
            getSwapFeePercentage()
        );
        _require(bptAmountIn <= maxBPTAmountIn, Errors.BPT_IN_MAX_AMOUNT);

        return (bptAmountIn, amountsOut);
    }

    // Oracle functions

    function getLargestSafeQueryWindow()
        external
        pure
        override
        returns (uint256)
    {
        return 34 hours;
    }

    function getLatest(Variable variable)
        external
        view
        override
        returns (uint256)
    {
        int256 instantValue = _getInstantValue(
            variable,
            _miscData.oracleIndex()
        );
        return LogCompression.fromLowResLog(instantValue);
    }

    function getTimeWeightedAverage(OracleAverageQuery[] memory queries)
        external
        view
        override
        returns (uint256[] memory results)
    {
        results = new uint256[](queries.length);

        uint256 oracleIndex = _miscData.oracleIndex();

        OracleAverageQuery memory query;
        for (uint256 i = 0; i < queries.length; ++i) {
            query = queries[i];
            _require(query.secs != 0, Errors.ORACLE_BAD_SECS);

            int256 beginAccumulator = _getPastAccumulator(
                query.variable,
                oracleIndex,
                query.ago + query.secs
            );
            int256 endAccumulator = _getPastAccumulator(
                query.variable,
                oracleIndex,
                query.ago
            );
            results[i] = LogCompression.fromLowResLog(
                (endAccumulator - beginAccumulator) / int256(query.secs)
            );
        }
    }

    function getPastAccumulators(OracleAccumulatorQuery[] memory queries)
        external
        view
        override
        returns (int256[] memory results)
    {
        results = new int256[](queries.length);

        uint256 oracleIndex = _miscData.oracleIndex();

        OracleAccumulatorQuery memory query;
        for (uint256 i = 0; i < queries.length; ++i) {
            query = queries[i];
            results[i] = _getPastAccumulator(
                query.variable,
                oracleIndex,
                query.ago
            );
        }
    }

    /**
     * @dev Updates the Price Oracle based on the Pool's current state (balances, BPT supply and invariant). Must be
     * called on *all* state-changing functions with the balances *before* the state change happens, and with
     * `lastChangeBlock` as the number of the block in which any of the balances last changed.
     */
    function _updateOracle(
        uint256 lastChangeBlock,
        uint256 balanceToken0,
        uint256 balanceToken1
    ) internal {
        bytes32 miscData = _miscData;
        if (miscData.oracleEnabled() && block.number > lastChangeBlock) {
            int256 logSpotPrice = WeightedOracleMath._calcLogSpotPrice(
                _normalizedWeight0,
                balanceToken0,
                _normalizedWeight1,
                balanceToken1
            );

            int256 logBPTPrice = WeightedOracleMath._calcLogBPTPrice(
                _normalizedWeight0,
                balanceToken0,
                miscData.logTotalSupply()
            );

            uint256 oracleCurrentIndex = miscData.oracleIndex();
            uint256 oracleCurrentSampleInitialTimestamp = miscData
                .oracleSampleCreationTimestamp();
            uint256 oracleUpdatedIndex = _processPriceData(
                oracleCurrentSampleInitialTimestamp,
                oracleCurrentIndex,
                logSpotPrice,
                logBPTPrice,
                miscData.logInvariant()
            );

            if (oracleCurrentIndex != oracleUpdatedIndex) {
                // solhint-disable not-rely-on-time
                miscData = miscData.setOracleIndex(oracleUpdatedIndex);
                miscData = miscData.setOracleSampleCreationTimestamp(
                    block.timestamp
                );
                _miscData = miscData;
            }
        }
    }

    /**
     * @dev Stores the logarithm of the invariant and BPT total supply, to be later used in each oracle update. Because
     * it is stored in miscData, which is read in all operations (including swaps), this saves gas by not requiring to
     * compute or read these values when updating the oracle.
     *
     * This function must be called by all actions that update the invariant and BPT supply (joins and exits). Swaps
     * also alter the invariant due to collected swap fees, but this growth is considered negligible and not accounted
     * for.
     */
    function _cacheInvariantAndSupply() internal {
        bytes32 miscData = _miscData;
        if (miscData.oracleEnabled()) {
            miscData = miscData.setLogInvariant(
                LogCompression.toLowResLog(_lastInvariant)
            );
            miscData = miscData.setLogTotalSupply(
                LogCompression.toLowResLog(totalSupply())
            );
            _miscData = miscData;
        }
    }

    // Query functions

    /**
     * @dev Returns the amount of BPT that would be granted to `recipient` if the `onJoinPool` hook were called by the
     * Vault with the same arguments, along with the number of tokens `sender` would have to supply.
     *
     * This function is not meant to be called directly, but rather from a helper contract that fetches current Vault
     * data, such as the protocol swap fee percentage and Pool balances.
     *
     * Like `IVault.queryBatchSwap`, this function is not view due to internal implementation details: the caller must
     * explicitly use eth_call instead of eth_sendTransaction.
     */
    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptOut, uint256[] memory amountsIn) {
        InputHelpers.ensureInputLengthMatch(balances.length, 2);

        _queryAction(
            poolId,
            sender,
            recipient,
            balances,
            lastChangeBlock,
            protocolSwapFeePercentage,
            userData,
            _onJoinPool,
            _downscaleUpArray
        );

        // The `return` opcode is executed directly inside `_queryAction`, so execution never reaches this statement,
        // and we don't need to return anything here - it just silences compiler warnings.
        return (bptOut, amountsIn);
    }

    /**
     * @dev Returns the amount of BPT that would be burned from `sender` if the `onExitPool` hook were called by the
     * Vault with the same arguments, along with the number of tokens `recipient` would receive.
     *
     * This function is not meant to be called directly, but rather from a helper contract that fetches current Vault
     * data, such as the protocol swap fee percentage and Pool balances.
     *
     * Like `IVault.queryBatchSwap`, this function is not view due to internal implementation details: the caller must
     * explicitly use eth_call instead of eth_sendTransaction.
     */
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptIn, uint256[] memory amountsOut) {
        InputHelpers.ensureInputLengthMatch(balances.length, 2);

        _queryAction(
            poolId,
            sender,
            recipient,
            balances,
            lastChangeBlock,
            protocolSwapFeePercentage,
            userData,
            _onExitPool,
            _downscaleDownArray
        );

        // The `return` opcode is executed directly inside `_queryAction`, so execution never reaches this statement,
        // and we don't need to return anything here - it just silences compiler warnings.
        return (bptIn, amountsOut);
    }

    // Helpers

    function _getDueProtocolFeeAmounts(
        uint256[] memory balances,
        uint256[] memory normalizedWeights,
        uint256 previousInvariant,
        uint256 currentInvariant,
        uint256 protocolSwapFeePercentage
    ) private view returns (uint256[] memory) {
        // Initialize with zeros
        uint256[] memory dueProtocolFeeAmounts = new uint256[](2);

        // Early return if the protocol swap fee percentage is zero, saving gas.
        if (protocolSwapFeePercentage == 0) {
            return dueProtocolFeeAmounts;
        }

        // The protocol swap fees are always paid using the token with the largest weight in the Pool. As this is the
        // token that is expected to have the largest balance, using it to pay fees should not unbalance the Pool.
        dueProtocolFeeAmounts[_maxWeightTokenIndex] = WeightedMath
            ._calcDueTokenProtocolSwapFeeAmount(
                balances[_maxWeightTokenIndex],
                normalizedWeights[_maxWeightTokenIndex],
                previousInvariant,
                currentInvariant,
                protocolSwapFeePercentage
            );

        return dueProtocolFeeAmounts;
    }

    /**
     * @dev Mutates `amounts` by applying `mutation` with each entry in `arguments`.
     *
     * Equivalent to `amounts = amounts.map(mutation)`.
     */
    function _mutateAmounts(
        uint256[] memory toMutate,
        uint256[] memory arguments,
        function(uint256, uint256) pure returns (uint256) mutation
    ) private pure {
        toMutate[0] = mutation(toMutate[0], arguments[0]);
        toMutate[1] = mutation(toMutate[1], arguments[1]);
    }

    /**
     * @dev This function returns the appreciation of one BPT relative to the
     * underlying tokens. This starts at 1 when the pool is created and grows over time
     */
    function getRate() public view returns (uint256) {
        // The initial BPT supply is equal to the invariant times the number of tokens.
        return Math.mul(getInvariant(), 2).divDown(totalSupply());
    }

    // Scaling

    /**
     * @dev Returns a scaling factor that, when multiplied to a token amount for `token`, normalizes its balance as if
     * it had 18 decimals.
     */
    function _computeScalingFactor(IERC20 token)
        private
        view
        returns (uint256)
    {
        // Tokens that don't implement the `decimals` method are not supported.
        uint256 tokenDecimals = ERC20(address(token)).decimals();

        // Tokens with more than 18 decimals are not supported.
        uint256 decimalsDifference = Math.sub(18, tokenDecimals);
        return 10**decimalsDifference;
    }

    /**
     * @dev Returns the scaling factor for one of the Pool's tokens. Reverts if `token` is not a token registered by the
     * Pool.
     */
    function _scalingFactor(bool token0) internal view returns (uint256) {
        return token0 ? _scalingFactor0 : _scalingFactor1;
    }

    /**
     * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
     * scaling or not.
     */
    function _upscale(uint256 amount, uint256 scalingFactor)
        internal
        pure
        returns (uint256)
    {
        return Math.mul(amount, scalingFactor);
    }

    /**
     * @dev Same as `_upscale`, but for an entire array (of two elements). This function does not return anything, but
     * instead *mutates* the `amounts` array.
     */
    function _upscaleArray(uint256[] memory amounts) internal view {
        amounts[0] = Math.mul(amounts[0], _scalingFactor(true));
        amounts[1] = Math.mul(amounts[1], _scalingFactor(false));
    }

    /**
     * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
     * whether it needed scaling or not. The result is rounded down.
     */
    function _downscaleDown(uint256 amount, uint256 scalingFactor)
        internal
        pure
        returns (uint256)
    {
        return Math.divDown(amount, scalingFactor);
    }

    /**
     * @dev Same as `_downscaleDown`, but for an entire array (of two elements). This function does not return anything,
     * but instead *mutates* the `amounts` array.
     */
    function _downscaleDownArray(uint256[] memory amounts) internal view {
        amounts[0] = Math.divDown(amounts[0], _scalingFactor(true));
        amounts[1] = Math.divDown(amounts[1], _scalingFactor(false));
    }

    /**
     * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
     * whether it needed scaling or not. The result is rounded up.
     */
    function _downscaleUp(uint256 amount, uint256 scalingFactor)
        internal
        pure
        returns (uint256)
    {
        return Math.divUp(amount, scalingFactor);
    }

    /**
     * @dev Same as `_downscaleUp`, but for an entire array (of two elements). This function does not return anything,
     * but instead *mutates* the `amounts` array.
     */
    function _downscaleUpArray(uint256[] memory amounts) internal view {
        amounts[0] = Math.divUp(amounts[0], _scalingFactor(true));
        amounts[1] = Math.divUp(amounts[1], _scalingFactor(false));
    }

    function _getAuthorizer() internal view override returns (IAuthorizer) {
        // Access control management is delegated to the Vault's Authorizer. This lets Balancer Governance manage which
        // accounts can call permissioned functions: for example, to perform emergency pauses.
        // If the owner is delegated, then *all* permissioned functions, including `setSwapFeePercentage`, will be under
        // Governance control.
        return getVault().getAuthorizer();
    }

    function _queryAction(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData,
        function(
            bytes32,
            address,
            address,
            uint256[] memory,
            uint256,
            uint256,
            bytes memory
        )
            internal
            returns (uint256, uint256[] memory, uint256[] memory) _action,
        function(uint256[] memory) internal view _downscaleArray
    ) private {
        // This uses the same technique used by the Vault in queryBatchSwap. Refer to that function for a detailed
        // explanation.

        if (msg.sender != address(this)) {
            // We perform an external call to ourselves, forwarding the same calldata. In this call, the else clause of
            // the preceding if statement will be executed instead.

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(this).call(msg.data);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // This call should always revert to decode the bpt and token amounts from the revert reason
                switch success
                case 0 {
                    // Note we are manually writing the memory slot 0. We can safely overwrite whatever is
                    // stored there as we take full control of the execution and then immediately return.

                    // We copy the first 4 bytes to check if it matches with the expected signature, otherwise
                    // there was another revert reason and we should forward it.
                    returndatacopy(0, 0, 0x04)
                    let error := and(
                        mload(0),
                        0xffffffff00000000000000000000000000000000000000000000000000000000
                    )

                    // If the first 4 bytes don't match with the expected signature, we forward the revert reason.
                    if eq(
                        eq(
                            error,
                            0x43adbafb00000000000000000000000000000000000000000000000000000000
                        ),
                        0
                    ) {
                        returndatacopy(0, 0, returndatasize())
                        revert(0, returndatasize())
                    }

                    // The returndata contains the signature, followed by the raw memory representation of the
                    // `bptAmount` and `tokenAmounts` (array: length + data). We need to return an ABI-encoded
                    // representation of these.
                    // An ABI-encoded response will include one additional field to indicate the starting offset of
                    // the `tokenAmounts` array. The `bptAmount` will be laid out in the first word of the
                    // returndata.
                    //
                    // In returndata:
                    // [ signature ][ bptAmount ][ tokenAmounts length ][ tokenAmounts values ]
                    // [  4 bytes  ][  32 bytes ][       32 bytes      ][ (32 * length) bytes ]
                    //
                    // We now need to return (ABI-encoded values):
                    // [ bptAmount ][ tokeAmounts offset ][ tokenAmounts length ][ tokenAmounts values ]
                    // [  32 bytes ][       32 bytes     ][       32 bytes      ][ (32 * length) bytes ]

                    // We copy 32 bytes for the `bptAmount` from returndata into memory.
                    // Note that we skip the first 4 bytes for the error signature
                    returndatacopy(0, 0x04, 32)

                    // The offsets are 32-bytes long, so the array of `tokenAmounts` will start after
                    // the initial 64 bytes.
                    mstore(0x20, 64)

                    // We now copy the raw memory array for the `tokenAmounts` from returndata into memory.
                    // Since bpt amount and offset take up 64 bytes, we start copying at address 0x40. We also
                    // skip the first 36 bytes from returndata, which correspond to the signature plus bpt amount.
                    returndatacopy(0x40, 0x24, sub(returndatasize(), 36))

                    // We finally return the ABI-encoded uint256 and the array, which has a total length equal to
                    // the size of returndata, plus the 32 bytes of the offset but without the 4 bytes of the
                    // error signature.
                    return(0, add(returndatasize(), 28))
                }
                default {
                    // This call should always revert, but we fail nonetheless if that didn't happen
                    invalid()
                }
            }
        } else {
            _upscaleArray(balances);

            (uint256 bptAmount, uint256[] memory tokenAmounts, ) = _action(
                poolId,
                sender,
                recipient,
                balances,
                lastChangeBlock,
                protocolSwapFeePercentage,
                userData
            );

            _downscaleArray(tokenAmounts);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // We will return a raw representation of `bptAmount` and `tokenAmounts` in memory, which is composed of
                // a 32-byte uint256, followed by a 32-byte for the array length, and finally the 32-byte uint256 values
                // Because revert expects a size in bytes, we multiply the array length (stored at `tokenAmounts`) by 32
                let size := mul(mload(tokenAmounts), 32)

                // We store the `bptAmount` in the previous slot to the `tokenAmounts` array. We can make sure there
                // will be at least one available slot due to how the memory scratch space works.
                // We can safely overwrite whatever is stored in this slot as we will revert immediately after that.
                let start := sub(tokenAmounts, 0x20)
                mstore(start, bptAmount)

                // We send one extra value for the error signature "QueryError(uint256,uint256[])" which is 0x43adbafb
                // We use the previous slot to `bptAmount`.
                mstore(
                    sub(start, 0x20),
                    0x0000000000000000000000000000000000000000000000000000000043adbafb
                )
                start := sub(start, 0x04)

                // When copying from `tokenAmounts` into returndata, we copy the additional 68 bytes to also return
                // the `bptAmount`, the array length, and the error signature.
                revert(start, add(size, 68))
            }
        }
    }
}
