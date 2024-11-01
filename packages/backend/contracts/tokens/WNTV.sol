// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title WNTV (Wrapped Native Token)
/// @notice This contract wraps native tokens into ERC20-compliant WNTV tokens.
contract WNTV is ERC20Upgradeable {
	/// @notice Constructor initializes the ERC20Upgradeable token with name and symbol.
	function initialize() public initializer {
		__ERC20_init("Wrapped Native Token", "WNTV");
	}

	/// @notice Unwraps WNTV tokens back into native tokens.
	/// @param amount The amount of WNTV tokens to unwrap.
	/// @dev This function burns the specified amount of WNTV tokens and sends the equivalent amount of native tokens to the user.
	function withdraw(uint256 amount) public {
		require(balanceOf(msg.sender) >= amount, "WNTV: Insufficient balance");
		_burn(msg.sender, amount);
		payable(msg.sender).transfer(amount);
	}

	/// @notice Allows an approved spender to use WNTV tokens on behalf of the sender.
	/// @param owner The address of the token owner.
	/// @param spender The address of the spender allowed to use the tokens.
	/// @dev This function mints WNTV tokens to the owner and approves the spender to use the minted tokens.
	function receiveForSpender(address owner, address spender) public payable {
		_mint(owner, msg.value);
		_approve(owner, spender, msg.value);
	}

	/// @notice Wraps native tokens into WNTV tokens for `owner`. The amount of WNTV minted equals the amount of native tokens sent.
	/// @param owner The address of the token owner.
	/// @dev This function mints WNTV tokens equivalent to the amount of native tokens sent by the user.
	function receiveFor(address owner) public payable {
		_mint(owner, msg.value);
	}
}
