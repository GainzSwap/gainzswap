// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TestERC20 is ERC20, Ownable, ERC20Burnable {
	uint8 private immutable _decimals;

	constructor(
		string memory name_,
		string memory symbol_,
		uint8 decimals_
	) ERC20(name_, symbol_) Ownable(msg.sender) {
		_decimals = decimals_;
	}

	function mint(address to, uint256 amt) external onlyOwner {
		_mint(to, amt);
	}

	function decimals() public view override returns (uint8) {
		return _decimals;
	}
}
