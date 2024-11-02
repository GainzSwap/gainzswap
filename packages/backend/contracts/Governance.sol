// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC1155HolderUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { Epochs } from "./libraries/Epochs.sol";
import { GToken } from "./tokens/GToken/GToken.sol";

library DeployGToken {
	function create(
		Epochs.Storage memory epochs,
		address initialOwner,
		address proxyAdmin
	) external returns (address) {
		return
			address(
				new TransparentUpgradeableProxy(
					address(new GToken()),
					proxyAdmin,
					abi.encodeWithSelector(
						GToken.initialize.selector,
						epochs,
						initialOwner
					)
				)
			);
	}
}

/// @title Governance Contract
/// @notice This contract handles the governance process by allowing users to lock LP tokens and mint GTokens.
/// @dev This contract interacts with the GTokens library and manages LP token payments.
contract Governance is ERC1155HolderUpgradeable, OwnableUpgradeable {
	using Epochs for Epochs.Storage;

	/// @custom:storage-location erc7201:gainz.Governance.storage
	struct GovernanceStorage {
		uint256 rewardPerShare;
		uint256 rewardsReserve;
		address gtoken;
		address router;
		Epochs.Storage epochs;
		address protocolFeesCollector;
	}

	// keccak256(abi.encode(uint256(keccak256("gainz.governance.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant GOVERNANCE_STORAGE_LOCATION =
		0xc28810daea0501c36ac69c5a41a8621a140281f0a38cc30865bbaf3d9b1add00;

	function _getGovernanceStorage()
		private
		pure
		returns (GovernanceStorage storage $)
	{
		assembly {
			$.slot := GOVERNANCE_STORAGE_LOCATION
		}
	}

	/// @notice Function to initialize the Governance contract.
	/// @param epochs The epochs storage instance for managing epochs.
	/// @param protocolFeesCollector The address to collect protocol fees.
	function initialize(
		Epochs.Storage memory epochs,
		address protocolFeesCollector,
		address proxyAdmin
	) public initializer {
		address router = msg.sender;
		__Ownable_init(router);

		GovernanceStorage storage $ = _getGovernanceStorage();

		$.epochs = epochs;
		$.gtoken = DeployGToken.create($.epochs, address(this), proxyAdmin);

		$.router = router;

		require(
			protocolFeesCollector != address(0),
			"Invalid Protocol Fees collector"
		);
		$.protocolFeesCollector = protocolFeesCollector;
	}

	// ******* VIEWS *******
	
	function getGToken() external view returns (address) {
		return _getGovernanceStorage().gtoken;
	}
}
