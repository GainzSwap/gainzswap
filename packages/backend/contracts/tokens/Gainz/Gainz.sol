// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

import { GainzInfo } from "./GainzInfo.sol";

/**
 * @title Gainz
 * @dev ERC20Upgradeable token representing the Academy-DEX base token. This token is mintable only upon deployment,
 * with the total supply set to the maximum defined in the `GainzInfo` library. The token is burnable
 * and is controlled by the owner of the contract.
 */
contract Gainz is ERC20Upgradeable, ERC20BurnableUpgradeable {
	/**
	 * @dev Initializes the ERC20Upgradeable token with the name "Gainz Token" and symbol "Gainz".
	 * Mints the maximum supply of tokens to the contract owner.
	 */
	function initialize() public initializer {
		__ERC20_init("Gainz Token", "Gainz");
		// Mint the maximum supply to the contract owner.
		_mint(msg.sender, GainzInfo.MAX_SUPPLY);
	}
}
