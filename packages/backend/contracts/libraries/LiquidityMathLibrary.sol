// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { AMMLibrary } from "./AMMLibrary.sol";
import { FullMath } from "./FullMath.sol";
import { Math } from "./Math.sol";

import { PairV2 } from "../PairV2.sol";

// library containing some math for dealing with the liquidity shares of a pair, e.g. computing their exact value
// in terms of the underlying tokens
library LiquidityMathLibrary {
	// computes liquidity value given all the parameters of the pair
	function computeLiquidityValueForReserve(
		uint256 reserve,
		uint256 totalSupply,
		uint256 liquidityAmount
	) internal pure returns (uint256) {
		return (reserve * liquidityAmount) / totalSupply;
	}
}
