// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SFT } from "../abstracts/SFT.sol";

contract LpToken is SFT {
	struct LpAttributes {
		uint256 rewardPerShare;
		uint256 depValuePerShare;
		address pair;
		address tradeToken;
	}

	struct LpBalance {
		uint256 nonce;
		uint256 amount;
		LpAttributes attributes;
	}

	function initialize(address initialOwner) public initializer {
		__SFT_init("Academy-DEX LP Token", "LPADEX", initialOwner);
	}

	/// @notice Returns the SFT balance of a user including detailed attributes.
	/// @param user The address of the user to check.
	/// @return An array of `LpBalance` containing the user's balance details.
	function lpBalanceOf(
		address user
	) public view returns (LpBalance[] memory) {
		SftBalance[] memory _sftBals = _sftBalance(user);
		LpBalance[] memory balance = new LpBalance[](_sftBals.length);

		for (uint256 i; i < _sftBals.length; i++) {
			SftBalance memory _sftBal = _sftBals[i];

			balance[i] = LpBalance({
				nonce: _sftBal.nonce,
				amount: _sftBal.amount,
				attributes: abi.decode(_sftBal.attributes, (LpAttributes))
			});
		}

		return balance;
	}

	function mint(
		uint256 lpAmount,
		address pair,
		address tradeToken,
		address to
	) external onlyOwner returns (uint256) {
		require(lpAmount > 0, "LpToken: LP Amount must be greater than 0");

		bytes memory attributes = abi.encode(
			LpAttributes({
				rewardPerShare: 0,
				pair: pair,
				tradeToken: tradeToken,
				depValuePerShare: 0
			})
		);

		return _mint(to, lpAmount, attributes);
	}

	function getBalanceAt(
		address user,
		uint256 nonce
	) public view returns (LpBalance memory) {
		require(hasSFT(user, nonce), "No Lp balance found at nonce for user");

		return
			LpBalance({
				nonce: nonce,
				amount: balanceOf(user, nonce),
				attributes: abi.decode(
					_getRawTokenAttributes(nonce),
					(LpAttributes)
				)
			});
	}

	function split(
		uint256 nonce,
		address[] calldata addresses,
		uint256[] calldata portions
	) external returns (uint256[] memory splitNonces) {
		require(addresses.length > 1, "LpToken: addresses too short");
		require(
			addresses.length == portions.length,
			"LpToken: Portions addresses mismatch"
		);

		address caller = msg.sender;
		LpBalance memory lpBalance = getBalanceAt(caller, nonce);

		_burn(caller, nonce, lpBalance.amount);
		uint256 totalSplitAmount = 0;
		splitNonces = new uint256[](addresses.length);

		bytes memory attributes = abi.encode(lpBalance.attributes);
		for (uint256 i; i < addresses.length; i++) {
			address to = addresses[i];
			uint256 amount = portions[i];
			totalSplitAmount += amount;

			splitNonces[i] = _mint(to, amount, attributes);
		}
		require(
			totalSplitAmount == lpBalance.amount,
			"LpToken: Invalid Portions"
		);
	}
}
