// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PriceOracle } from "../PriceOracle.sol";

library DeployPriceOracle {
	function create() external returns (address oracle) {
		bytes memory bytecode = type(PriceOracle).creationCode;
		bytes32 salt = keccak256(abi.encodePacked(address(this)));
		assembly {
			oracle := create2(0, add(bytecode, 32), mload(bytecode), salt)
		}
	}

}
