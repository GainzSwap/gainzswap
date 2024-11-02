// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Epochs } from "../libraries/Epochs.sol";

import "hardhat/console.sol";

abstract contract OldRouter is OwnableUpgradeable {
	struct PairData {
		uint256 sellVolume;
		uint256 buyVolume;
		uint256 lpRewardsPershare;
		uint256 tradeRewardsPershare;
		uint256 totalLiq;
		uint256 rewardsReserve;
	}

	struct GlobalData {
		uint256 rewardsReserve;
		uint256 taxRewards;
		uint256 rewardsPerShare;
		uint256 totalTradeVolume;
		uint256 lastTimestamp;
		uint256 totalLiq;
	}

	/// @custom:storage-location erc7201:router.storage
	struct OldRouterStorage {
		Epochs.Storage epochs;
		EnumerableSet.AddressSet pairs;
		EnumerableSet.AddressSet tradeTokens;
		address _wEduAddress;
		mapping(address => address) tokensPairAddress;
		mapping(address => PairData) pairsData;
		GlobalData globalData;
		address lpToken;
		address governance;
		address adexTokenAddress;
		address proxyAdmin;
		address pairBeacon;
	}

	// keccak256(abi.encode(uint256(keccak256("router.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant OLD_ROUTER_STORAGE_LOCATION =
		0x012ef321094c8c682aa635dfdfcd754624a7473f08ad6ac415bb7f35eb12a100;

	function _getOldRouterStorage()
		private
		pure
		returns (OldRouterStorage storage $)
	{
		assembly {
			$.slot := OLD_ROUTER_STORAGE_LOCATION
		}
	}

	// ### INTERNAL VIEWS ###

	function _getWEDU() internal view returns (address) {
		return _getOldRouterStorage()._wEduAddress;
	}

	function _getProxyAdmin() internal view returns (address) {
		return _getOldRouterStorage().proxyAdmin;
	}

	function _getOldEpochsStorage()
		internal
		view
		returns (Epochs.Storage storage)
	{
		OldRouterStorage storage $ = _getOldRouterStorage();
		return $.epochs;
	}
}
