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
		uint256 supply;
		uint256 stakeWeight;
		LiquidityInfo[] lpDetails;
	}

	// Constants for lock periods and percentage loss calculations
	uint256 public constant MIN_EPOCHS_LOCK = 30;
	uint256 public constant MAX_EPOCHS_LOCK = 1080;

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

		// Update supply
		uint256 supply = 0;
		for (uint256 index; index < self.lpDetails.length; index++) {
			supply += self.lpDetails[index].liqValue;
		}
		self.supply = supply;

		// Calculate stake weight based on supply and epochs locked
		self.stakeWeight = self.supply * epochsLocked;

		return self;
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

		return self.supply * voteWeight;
	}
}
