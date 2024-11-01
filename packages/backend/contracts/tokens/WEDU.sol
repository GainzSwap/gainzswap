// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title WEDU (Wrapped EduChain) Token
/// @notice This contract wraps EduChain (EDU) native tokens into ERC20-compliant WEDU tokens.
contract WEDU is ERC20Upgradeable {
	/// @notice Constructor initializes the ERC20Upgradeable token with name and symbol.
	function initialize() public initializer {
		__ERC20_init("Wrapped EduChain", "WEDU");
	}

	/// @notice Fallback function to receive EDU and automatically wrap it into WEDU.
	/// The received EDU will be wrapped as WEDU and credited to the sender.
	receive() external payable {
		deposit();
	}

	/// @notice Wraps EDU into WEDU tokens. The amount of WEDU minted equals the amount of EDU sent.
	/// @dev This function mints WEDU tokens equivalent to the amount of EDU sent by the user.
	function deposit() public payable {
		_mint(msg.sender, msg.value);
	}

	/// @notice Unwraps WEDU tokens back into EDU.
	/// @param amount The amount of WEDU tokens to unwrap.
	/// @dev This function burns the specified amount of WEDU tokens and sends the equivalent amount of EDU to the user.
	function withdraw(uint256 amount) public {
		require(balanceOf(msg.sender) >= amount, "WEDU: Insufficient balance");
		_burn(msg.sender, amount);
		payable(msg.sender).transfer(amount);
	}

	/// @notice Allows an approved spender to use WEDU tokens on behalf of the sender.
	/// @param owner The address of the token owner.
	/// @param spender The address of the spender allowed to use the tokens.
	/// @dev This function mints WEDU tokens to the owner and approves the spender to use the minted tokens.
	function receiveForSpender(address owner, address spender) public payable {
		_mint(owner, msg.value);
		_approve(owner, spender, msg.value);
	}
}
