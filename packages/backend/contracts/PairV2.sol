// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IPairV2 } from "./interfaces/IPairV2.sol";

import { Math } from "./libraries/Math.sol";
import { UQ112x112 } from "./libraries/UQ112x112.sol";

import { PairERC20 } from "./abstracts/PairERC20.sol";

import "./types.sol";

contract PairV2 is IPairV2, PairERC20, OwnableUpgradeable {
	using UQ112x112 for uint224;

	uint public constant MINIMUM_LIQUIDITY = 10 ** 3;
	bytes4 private constant SELECTOR =
		bytes4(keccak256(bytes("transfer(address,uint256)")));

	/// @custom:storage-location erc7201:gainz.PairV2.storage
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
	// keccak256(abi.encode(uint256(keccak256("gainz.PairV2.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant PAIR_STORAGE_LOCATION =
		0x052a7ca952fd79e6951e1e37bbd8a7a728c978d413c271dcc4d73117e8490200;

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
	function _update(
		uint balance0,
		uint balance1,
		uint112 reserve0,
		uint112 reserve1
	) private {
		PairStorage storage $ = _getPairStorage();

		require(
			balance0 <= type(uint112).max && balance1 <= type(uint112).max,
			"Pair: OVERFLOW"
		);

		uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
		uint32 timeElapsed = blockTimestamp - $.blockTimestampLast; // Overflow is intentional here

		if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
			// * never overflows, and + overflow is desired
			$.price0CumulativeLast +=
				uint(UQ112x112.encode(reserve1).uqdiv(reserve0)) *
				timeElapsed;
			$.price1CumulativeLast +=
				uint(UQ112x112.encode(reserve0).uqdiv(reserve1)) *
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

	function _safeTransfer(address token, address to, uint value) private {
		(bool success, bytes memory data) = token.call(
			abi.encodeWithSelector(SELECTOR, to, value)
		);
		require(
			success && (data.length == 0 || abi.decode(data, (bool))),
			"Pair: TRANSFER_FAILED"
		);
	}

	function price0CumulativeLast() external view returns (uint256) {
		return _getPairStorage().price0CumulativeLast;
	}

	function price1CumulativeLast() external view returns (uint256) {
		return _getPairStorage().price1CumulativeLast;
	}

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

		_update(balance0, balance1, reserve0, reserve1);
		emit Mint(msg.sender, amount0, amount1);
	}

	// this low-level function should be called from a contract which performs important safety checks
	function burn(
		address to
	) external lock onlyOwner returns (uint amount0, uint amount1) {
		PairStorage storage $ = _getPairStorage();

		(uint112 _reserve0, uint112 _reserve1) = ($.reserve0, $.reserve1); // gas savings
		address _token0 = $.token0; // gas savings
		address _token1 = $.token1; // gas savings
		uint balance0 = IERC20(_token0).balanceOf(address(this));
		uint balance1 = IERC20(_token1).balanceOf(address(this));
		uint liquidity = balanceOf(address(this));

		uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
		amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
		amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
		require(
			amount0 > 0 && amount1 > 0,
			"UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED"
		);
		_burn(address(this), liquidity);
		_safeTransfer(_token0, to, amount0);
		_safeTransfer(_token1, to, amount1);
		balance0 = IERC20(_token0).balanceOf(address(this));
		balance1 = IERC20(_token1).balanceOf(address(this));

		_update(balance0, balance1, _reserve0, _reserve1);
		emit Burn(msg.sender, amount0, amount1, to);
	}

	function swap(
		uint amount0Out,
		uint amount1Out,
		address to
	) external lock onlyOwner {
		require(
			amount0Out > 0 || amount1Out > 0,
			"Pair: INSUFFICIENT_OUTPUT_AMOUNT"
		);
		(uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
		require(
			amount0Out < _reserve0 && amount1Out < _reserve1,
			"Pair: INSUFFICIENT_LIQUIDITY"
		);

		uint balance0;
		uint balance1;
		{
			PairStorage storage $ = _getPairStorage();

			// scope for _token{0,1}, avoids stack too deep errors
			address _token0 = $.token0;
			address _token1 = $.token1;
			require(to != _token0 && to != _token1, "Pair: INVALID_TO");
			if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
			if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens

			balance0 = IERC20(_token0).balanceOf(address(this));
			balance1 = IERC20(_token1).balanceOf(address(this));
		}
		uint amount0In = balance0 > _reserve0 - amount0Out
			? balance0 - (_reserve0 - amount0Out)
			: 0;
		uint amount1In = balance1 > _reserve1 - amount1Out
			? balance1 - (_reserve1 - amount1Out)
			: 0;
		require(
			amount0In > 0 || amount1In > 0,
			"Pair: INSUFFICIENT_INPUT_AMOUNT"
		);
		{
			// scope for reserve{0,1}Adjusted, avoids stack too deep errors
			uint balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
			uint balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
			require(
				(balance0Adjusted * balance1Adjusted) >=
					uint(_reserve0) * (_reserve1) * (1000 ** 2),
				"Pair: K"
			);
		}

		_update(balance0, balance1, _reserve0, _reserve1);
		emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
	}

	function skim(address to) external {}

	function sync() external {}
}
