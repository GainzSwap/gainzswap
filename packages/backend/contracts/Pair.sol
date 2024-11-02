// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IPair } from "./interfaces/IPair.sol";

import { Math } from "./libraries/Math.sol";
import { UQ112x112 } from "./libraries/UQ112x112.sol";

import { PairERC20 } from "./abstracts/PairERC20.sol";

contract Pair is IPair, PairERC20, OwnableUpgradeable {
	using UQ112x112 for uint224;

	uint public constant MINIMUM_LIQUIDITY = 10 ** 3;
	bytes4 private constant SELECTOR =
		bytes4(keccak256(bytes("transfer(address,uint256)")));

	struct PairStorage {
		uint unlocked;
		address router;
		address token0;
		address token1;
		uint112 reserve0;
		uint112 reserve1;
		uint32 blockTimestampLast;
		uint price0CumulativeLast;
		uint price1CumulativeLast;
	}
	// keccak256(abi.encode(uint256(keccak256("gainz.Pair.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant PAIR_STORAGE_LOCATION =
		0xba980d5783bffb5f835d3f0c867bf29893420ce13d96cd991268a83c1f1e4100;

	function _getPairStorage() private pure returns (PairStorage storage $) {
		assembly {
			$.slot := PAIR_STORAGE_LOCATION
		}
	}

	modifier lock() {
		PairStorage storage $ = _getPairStorage();

		require($.unlocked == 1, "Pair: LOCKED");
		$.unlocked = 0;
		_;
		$.unlocked = 1;
	}

	// called once by the router at time of deployment
	function initialize(address _token0, address _token1) external initializer {
		__Ownable_init(msg.sender);
		__PairERC20_init();

		PairStorage storage $ = _getPairStorage();

		$.router = msg.sender;
		$.token0 = _token0;
		$.token1 = _token1;
		$.unlocked = 1;
	}

	// update reserves and, on the first call per block, price accumulators
	function _updatePair(
		uint balance0,
		uint balance1,
		uint112 reserve0,
		uint112 reserve1
	) private {
		PairStorage storage $ = _getPairStorage();

		uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
		uint32 timeElapsed = blockTimestamp - $.blockTimestampLast; // Overflow is intentional here

		if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
			// Multiplication does not overflow due to the Solidity 0.8 overflow checks
			$.price0CumulativeLast +=
				UQ112x112.encode(reserve1).uqdiv(reserve0) *
				timeElapsed;
			$.price1CumulativeLast +=
				UQ112x112.encode(reserve0).uqdiv(reserve1) *
				timeElapsed;
		}

		$.reserve0 = uint112(balance0);
		$.reserve1 = uint112(balance1);
		$.blockTimestampLast = blockTimestamp;
		emit Sync($.reserve0, $.reserve1);
	}

	function router() external view returns (address) {
		return _getPairStorage().router;
	}

	function token0() external view returns (address) {
		return _getPairStorage().token0;
	}

	function token1() external view returns (address) {
		return _getPairStorage().token1;
	}

	function getReserves()
		public
		view
		returns (uint112 reserve0, uint112 reserve1, uint32 _blockTimestampLast)
	{
		PairStorage storage $ = _getPairStorage();

		reserve0 = $.reserve0;
		reserve1 = $.reserve1;
		_blockTimestampLast = $.blockTimestampLast;
	}

	function price0CumulativeLast() external view returns (uint256) {}

	function price1CumulativeLast() external view returns (uint256) {}

	// this low-level function should be called from a contract which performs important safety checks
	function mint(address to) external lock onlyOwner returns (uint liquidity) {
		PairStorage storage $ = _getPairStorage();

		(uint112 reserve0, uint112 reserve1, ) = getReserves(); // gas savings
		uint balance0 = IERC20($.token0).balanceOf(address(this));
		uint balance1 = IERC20($.token1).balanceOf(address(this));
		uint amount0 = balance0 - reserve0;
		uint amount1 = balance1 - reserve1;

		uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
		if (_totalSupply == 0) {
			liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
			_mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
		} else {
			liquidity = Math.min(
				(amount0 * _totalSupply) / reserve0,
				(amount1 * _totalSupply) / reserve1
			);
		}
		require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_MINTED");
		_mint(to, liquidity);

		_updatePair(balance0, balance1, reserve0, reserve1);
		emit Mint(msg.sender, amount0, amount1);
	}

	function burn(
		address to
	) external returns (uint256 amount0, uint256 amount1) {}

	function swap(
		uint256 amount0Out,
		uint256 amount1Out,
		address to,
		bytes calldata data
	) external {}

	function skim(address to) external {}

	function sync() external {}
}
