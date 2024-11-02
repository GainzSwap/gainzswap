// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import 'hardhat/console.sol';

struct LiquidityInfo {
	address pair;
	uint256 liquidity;
	uint256 gTokenSupply;
}

function createLiquidityInfoArray(
	LiquidityInfo memory element
) pure returns (LiquidityInfo[] memory array) {
	assembly ("memory-safe") {
		// Load the free memory pointer
		array := mload(0x40)
		// Set array length to 1
		mstore(array, 1)
		// Store the single element at the next word after the length (where content starts)
		mstore(add(array, 0x20), element)
	}
}
