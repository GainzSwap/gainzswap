// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IPair } from "./interfaces/IPair.sol";

contract Pair is IPair, ERC20Upgradeable {
	uint public constant MINIMUM_LIQUIDITY = 10 ** 3;
	bytes4 private constant SELECTOR =
		bytes4(keccak256(bytes("transfer(address,uint256)")));

	struct PairStorage {
		address router;
		address token0;
		address token1;
		uint112 reserve0; 
		uint112 reserve1; 
		uint32 blockTimestampLast; 
		uint price0CumulativeLast;
		uint price1CumulativeLast;
		bytes32 domainSeperator;
	}
	// keccak256(abi.encode(uint256(keccak256("gainz.Pair.storage")) - 1)) & ~bytes32(uint256(0xff));
	bytes32 private constant PAIR_STORAGE_LOCATION =
		0xba980d5783bffb5f835d3f0c867bf29893420ce13d96cd991268a83c1f1e4100;

	function _getPairStorage() private pure returns (PairStorage storage $) {
		assembly {
			$.slot := PAIR_STORAGE_LOCATION
		}
	}

	function DOMAIN_SEPARATOR() external view returns (bytes32) {
		return _getPairStorage().domainSeperator;
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
		external
		view
		returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
	{}

	function price0CumulativeLast() external view returns (uint256) {}

	function price1CumulativeLast() external view returns (uint256) {}

	function mint(address to) external returns (uint256 liquidity) {}

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

	// called once by the router at time of deployment
	function initialize(address _token0, address _token1) external initializer {
		__ERC20_init("GainzLP", "GNZ-LP");

		PairStorage storage $ = _getPairStorage();

		$.router = msg.sender;
		$.token0 = _token0;
		$.token1 = _token1;

		uint chainId;
		assembly {
			chainId := chainid()
		}
		$.domainSeperator = keccak256(
			abi.encode(
				keccak256(
					"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
				),
				keccak256(bytes(name())),
				keccak256(bytes("1")),
				chainId,
				address(this)
			)
		);
	}
}
