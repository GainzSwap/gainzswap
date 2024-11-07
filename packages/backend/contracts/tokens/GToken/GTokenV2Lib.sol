// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { TokenPayment } from "../../libraries/TokenPayments.sol";
import { Math } from "../../libraries/Math.sol";

import "../../types.sol";

/// @title GToken Library
/// @notice This library provides functions for managing GToken attributes, including staking, claiming rewards, and calculating stake weights and rewards.
library GTokenV2Lib {
	/// @dev Attributes struct holds the data related to a participant's stake in the GToken contract.
	struct Attributes {
		uint256 rewardPerShare;
		uint256 epochStaked;
		uint256 epochsLocked;
		uint256 lastClaimEpoch;
		uint256 stakeWeight;
		LiquidityInfo lpDetails;
	}

	// Constants for lock periods and percentage loss calculations
	uint256 public constant MIN_EPOCHS_LOCK = 30;
	uint256 public constant MAX_EPOCHS_LOCK = 1080;
	uint256 public constant MIN_EPOCHS_LOCK_PERCENT_LOSS = 55e4; // 55% in basis points
	uint256 public constant MAX_EPOCHS_LOCK_PERCENT_LOSS = 15e4; // 15% in basis points
	uint256 public constant MAX_PERCENT_LOSS = 100e4; // 100% in basis points

	/// @notice Computes the stake weight based on the amount of LP tokens and the epochs locked.
	/// @param self The Attributes struct of the participant.
	/// @return The updated Attributes struct with the computed stake weight.
	function computeStakeWeight(
		Attributes memory self
	) internal pure returns (Attributes memory) {
		uint256 epochsLocked = self.epochsLocked;
		require(
			MIN_EPOCHS_LOCK <= epochsLocked && epochsLocked <= MAX_EPOCHS_LOCK,
			"GToken: Invalid epochsLocked"
		);

		// Calculate stake weight based on supply and epochs locked
		self.stakeWeight = self.lpDetails.liqValue * epochsLocked;

		return self;
	}

	/// @notice Splits an `Attributes` struct into multiple portions based on the specified liquidity portions.
	/// @param self The original `Attributes` struct to split.
	/// @param liquidityPortions An array of percentages (as portions of 1e18) to divide the liquidity into.
	/// @return splitAttributes An array of new `Attributes` structs with the allocated portions.
	function split(
		Attributes memory self,
		uint256[] memory liquidityPortions
	) internal pure returns (Attributes[] memory splitAttributes) {
		// Initialize the array to store split `Attributes` structs
		splitAttributes = new Attributes[](liquidityPortions.length);

		uint256 portionSum;
		uint256 liqValueSum;

		// Loop through each portion and split attributes
		for (uint256 i = 0; i < liquidityPortions.length; i++) {
			uint256 splitLiquidity = liquidityPortions[i];
			uint256 liqValue = (splitLiquidity * self.lpDetails.liqValue) /
				self.lpDetails.liquidity;

			splitAttributes[i] = computeStakeWeight(
				Attributes({
					rewardPerShare: self.rewardPerShare,
					epochStaked: self.epochStaked,
					epochsLocked: self.epochsLocked,
					lastClaimEpoch: self.lastClaimEpoch,
					stakeWeight: 0,
					lpDetails: LiquidityInfo({
						token0: self.lpDetails.token0,
						token1: self.lpDetails.token1,
						liquidity: splitLiquidity,
						liqValue: liqValue
					})
				})
			);

			portionSum += splitAttributes[i].lpDetails.liquidity;
			liqValueSum += splitAttributes[i].lpDetails.liqValue;
		}

		// last portion gets un used liqValue, if any
		splitAttributes[splitAttributes.length - 1].lpDetails.liqValue +=
			self.lpDetails.liqValue -
			liqValueSum;

		return splitAttributes;
	}

	function supply(Attributes memory self) internal pure returns (uint256) {
		return self.lpDetails.liqValue;
	}

	/// @notice Calculates the number of epochs that have elapsed since staking.
	/// @param self The Attributes struct of the participant.
	/// @param currentEpoch The current epoch.
	/// @return The number of epochs elapsed since staking.
	function epochsElapsed(
		Attributes memory self,
		uint256 currentEpoch
	) internal pure returns (uint256) {
		if (currentEpoch <= self.epochStaked) {
			return 0;
		}
		return currentEpoch - self.epochStaked;
	}

	/// @notice Calculates the number of epochs remaining until the stake is unlocked.
	/// @param self The Attributes struct of the participant.
	/// @param currentEpoch The current epoch.
	/// @return The number of epochs remaining until unlock.
	function epochsLeft(
		Attributes memory self,
		uint256 currentEpoch
	) internal pure returns (uint256) {
		uint256 elapsed = epochsElapsed(self, currentEpoch);
		if (elapsed >= self.epochsLocked) {
			return 0;
		}
		return self.epochsLocked - elapsed;
	}

	/// @notice Calculates the user's vote power based on the locked GToken amount and remaining epochs.
	/// @param self The Attributes struct of the participant.
	/// @return The calculated vote power as a uint256.
	/// @dev see https://wiki.sovryn.com/en/governance/about-sovryn-governance
	function votePower(
		Attributes memory self,
		uint256 currentEpoch
	) internal pure returns (uint256) {
		uint256 xPow = (MAX_EPOCHS_LOCK - epochsLeft(self, currentEpoch)) ** 2;
		uint256 mPow = MAX_EPOCHS_LOCK ** 2;

		uint256 voteWeight = ((9 * xPow) / mPow) + 1;

		return self.lpDetails.liqValue * voteWeight;
	}

	/// @notice Calculates the number of epochs since the last reward claim.
	/// @param self The Attributes struct of the participant.
	/// @return The number of epochs since the last claim.
	function epochsUnclaimed(
		Attributes memory self
	) internal pure returns (uint256) {
		return self.epochsLocked - self.lastClaimEpoch;
	}

	/// @notice Calculates the amount of value to keep based on epochs elapsed and locked.
	/// @param self The Attributes struct of the participant.
	/// @param value The total value amount.
	/// @param currentEpoch The current epoch.
	/// @return The amount of value to keep after applying penalties.
	function valueToKeep(
		Attributes memory self,
		uint256 value,
		uint256 currentEpoch
	) internal pure returns (uint256) {
		// Calculate percentage loss based on epochs locked
		uint256 epochsLockedPercentLoss = Math.linearInterpolation(
			MIN_EPOCHS_LOCK,
			MAX_EPOCHS_LOCK,
			self.epochsLocked,
			MIN_EPOCHS_LOCK_PERCENT_LOSS,
			MAX_EPOCHS_LOCK_PERCENT_LOSS
		);

		// Calculate the percentage of the value to keep after penalties
		uint256 percentLost = epochsElapsedPercentLoss(
			epochsElapsed(self, currentEpoch),
			epochsLockedPercentLoss,
			self.epochsLocked
		);

		uint256 percentToKeep = MAX_PERCENT_LOSS - percentLost;
		return (value * percentToKeep) / MAX_PERCENT_LOSS;
	}

	function hasNativeToken(
		Attributes memory self,
		address wNativeToken
	) internal pure returns (bool itHas) {
		itHas =
			self.lpDetails.token0 == wNativeToken ||
			self.lpDetails.token1 == wNativeToken;
	}

	/// @notice Calculates the percentage loss of the reward based on elapsed epochs.
	/// @param elapsed The number of epochs elapsed since staking.
	/// @param lockedPercentLoss The percentage loss based on epochs locked.
	/// @param locked The total epochs locked.
	/// @return The percentage loss based on epochs elapsed.
	function epochsElapsedPercentLoss(
		uint256 elapsed,
		uint256 lockedPercentLoss,
		uint256 locked
	) private pure returns (uint256) {
		uint256 remainingTime = elapsed > locked ? 0 : locked - elapsed;

		return
			Math.linearInterpolation(
				0,
				locked,
				remainingTime,
				0,
				lockedPercentLoss
			);
	}
}
