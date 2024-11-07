// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { GTokenV2Lib } from "./GTokenV2Lib.sol";
import { SFT } from "../../abstracts/SFT.sol";
import { Epochs } from "../../libraries/Epochs.sol";

import "../../types.sol";

struct GTokenV2Balance {
	uint256 nonce;
	uint256 amount;
	uint256 votePower;
	GTokenV2Lib.Attributes attributes;
}

/// @title GToken Contract
/// @notice This contract handles the minting of governance tokens (GToken) used in the ADEX platform.
/// @dev The contract extends a semi-fungible token (SFT) and uses GToken attributes for staking.
contract GTokenV2 is SFT {
	using GTokenV2Lib for GTokenV2Lib.Attributes;
	using Epochs for Epochs.Storage;

	struct Reward {
		uint256 rewardPerShare;
		uint256 rewardsReserve;
	}

	/// @custom:storage-location erc7201:gainz.GToken.storage
	struct GTokenStorage {
		uint256 totalStakeWeight;
		uint256 totalSupply;
		mapping(address => Reward) tokenRewards;
		address protocolFeesCollector;
		Epochs.Storage epochs;
	}

	// keccak256(abi.encode(uint256(keccak256("gainz.GToken.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant GTOKEN_STORAGE_LOCATION =
		0xb8e7eb3bf49f83cb3ff588efef6ab82dab4dc692401ee0d26d4dc4d075b6c500;

	function _getGTokenStorage()
		private
		pure
		returns (GTokenStorage storage $)
	{
		assembly {
			$.slot := GTOKEN_STORAGE_LOCATION
		}
	}

	/// @notice Constructor to initialize the GToken contract.
	/// @dev Sets the name and symbol of the SFT for GToken.
	function initialize(
		Epochs.Storage memory epochs,
		address initialOwner
	) public initializer {
		__SFT_init("GainzSwap Governance Token", "GToken", initialOwner);
		_getGTokenStorage().epochs = epochs;
	}

	/// @notice Mints a new GToken for the given address.
	/// @dev The function encodes GToken attributes and mints the token with those attributes.
	/// @param to The address that will receive the minted GToken.
	/// @param rewardPerShare The reward per share at the time of minting.
	/// @param epochsLocked The number of epochs for which the LP tokens are locked.
	/// @param currentEpoch The current epoch when the GToken is minted.
	/// @param lpDetails An array of LiquidityInfo structs representing the LP token payments.
	/// @return uint256 The token ID of the newly minted GToken.
	function mintGToken(
		address to,
		uint256 rewardPerShare,
		uint256 epochsLocked,
		uint256 currentEpoch,
		LiquidityInfo memory lpDetails
	) external canUpdate returns (uint256) {
		// Create GToken attributes and compute the stake weight
		GTokenV2Lib.Attributes memory attributes = GTokenV2Lib
			.Attributes({
				rewardPerShare: rewardPerShare,
				epochStaked: currentEpoch,
				lastClaimEpoch: currentEpoch,
				epochsLocked: epochsLocked,
				stakeWeight: 0,
				lpDetails: lpDetails
			})
			.computeStakeWeight();

		// Mint the GToken with the specified attributes and return the token ID
		return _mint(to, attributes.supply(), abi.encode(attributes));
	}

	function update(
		address user,
		uint256 nonce,
		GTokenV2Lib.Attributes memory attr
	) external canUpdate returns (uint256) {
		attr = attr.computeStakeWeight();
		return super.update(user, nonce, attr.supply(), abi.encode(attr));
	}

	/**
	 * @notice Retrieves the governance token balance and attributes for a specific user at a given nonce.
	 * @dev This function checks if the user has a Semi-Fungible Token (SFT) at the provided nonce.
	 * If the user does not have a balance at the specified nonce, the function will revert with an error.
	 * The function then returns the governance balance for the user at that nonce.
	 *
	 * @param user The address of the user whose balance is being queried.
	 * @param nonce The nonce for the specific GToken to retrieve.
	 *
	 * @return GTokenV2Balance A struct containing the nonce, amount, and attributes of the GToken.
	 *
	 * Requirements:
	 * - The user must have a GToken balance at the specified nonce.
	 */
	function getBalanceAt(
		address user,
		uint256 nonce
	) public view returns (GTokenV2Balance memory) {
		require(
			hasSFT(user, nonce),
			"No GToken balance found at nonce for user"
		);

		return
			_packageGTokenV2Balance(
				nonce,
				balanceOf(user, nonce),
				_getRawTokenAttributes(nonce)
			);
	}

	function _packageGTokenV2Balance(
		uint256 nonce,
		uint256 amount,
		bytes memory attr
	) private view returns (GTokenV2Balance memory) {
		GTokenV2Lib.Attributes memory attrUnpacked = abi.decode(
			attr,
			(GTokenV2Lib.Attributes)
		);
		uint256 epochsLeft = attrUnpacked.epochsLeft(
			attrUnpacked.epochsElapsed(
				_getGTokenStorage().epochs.currentEpoch()
			)
		);
		uint256 votePower = attrUnpacked.votePower(epochsLeft);

		return
			GTokenV2Balance({
				nonce: nonce,
				amount: amount,
				attributes: attrUnpacked,
				votePower: votePower
			});
	}

	/**
	 * @notice Retrieves the entire GToken balance and attributes for a specific user.
	 * @dev This function queries all Semi-Fungible Tokens (SFTs) held by the user and decodes
	 * the attributes for each GToken.
	 *
	 * @param user The address of the user whose balances are being queried.
	 *
	 * @return GTokenV2Balance[] An array of structs, each containing the nonce, amount, and attributes
	 * of the user's GToken.
	 */
	function getGTokenV2Balance(
		address user
	) public view returns (GTokenV2Balance[] memory) {
		SftBalance[] memory _sftBals = _sftBalance(user);
		GTokenV2Balance[] memory balance = new GTokenV2Balance[](
			_sftBals.length
		);

		for (uint256 i = 0; i < _sftBals.length; i++) {
			SftBalance memory _sftBal = _sftBals[i];

			balance[i] = _packageGTokenV2Balance(
				_sftBal.nonce,
				_sftBal.amount,
				_sftBal.attributes
			);
		}

		return balance;
	}

	function totalStakeWeight() public view returns (uint256) {
		return _getGTokenStorage().totalStakeWeight;
	}

	function totalSupply() public view returns (uint256) {
		return _getGTokenStorage().totalSupply;
	}

	function decimal() external pure returns (uint8) {
		return 18;
	}

	/// @dev the attributes beign updated must have be updated by calling the `computeStakeWeight` method on them
	function _update(
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory values
	) internal override {
		super._update(from, to, ids, values);

		for (uint256 i; i < ids.length; i++) {
			uint256 id = ids[i];
			GTokenV2Lib.Attributes memory attr = abi.decode(
				_getRawTokenAttributes(id),
				(GTokenV2Lib.Attributes)
			);

			if (from == address(0) && to != address(0)) {
				// We are minting, so increase staking weight
				GTokenStorage storage $ = _getGTokenStorage();
				$.totalStakeWeight += attr.stakeWeight;
				$.totalSupply += attr.supply();
			} else if (from != address(0) && to == address(0)) {
				// We are burning, so decrease staking weight
				GTokenStorage storage $ = _getGTokenStorage();
				$.totalStakeWeight -= attr.stakeWeight;
				$.totalSupply -= attr.supply();
			}
		}
	}

	/// @notice Splits a GToken into portions and distributes it to the specified addresses.
	/// @dev If an address is the zero address, the allotted portion is burned.
	/// This function can be called by the contract owner or the token's owner.
	/// @param nonce The nonce of the GToken to split.
	/// @param addresses An array of addresses to receive the split portions.
	/// @param liquidityPortions An array of liquidityPortions representing the amounts to be split.
	/// @return splitNonces An array of nonces for the newly minted split tokens.
	function split(
		uint256 nonce,
		address[] calldata addresses,
		uint256[] calldata liquidityPortions
	) external returns (uint256[] memory splitNonces) {
		require(
			addresses.length > 0 &&
				addresses.length == liquidityPortions.length,
			"Invalid Addresses and portions"
		);

		address user = addresses[0];

		require(
			hasSFT(user, nonce) || isOperator(msg.sender),
			"Caller not authorized"
		);

		GTokenV2Lib.Attributes memory attributes = getBalanceAt(user, nonce)
			.attributes;
		GTokenV2Lib.Attributes[] memory splitAttributes = attributes.split(
			liquidityPortions
		);

		splitNonces = new uint256[](splitAttributes.length);
		for (uint256 i = 0; i < splitAttributes.length; i++) {
			splitNonces[i] = _mint(
				addresses[i],
				splitAttributes[i].supply(),
				abi.encode(splitAttributes[i])
			);
		}

		// Burn the original token after splitting
		_burn(user, nonce, attributes.supply());
	}
}
