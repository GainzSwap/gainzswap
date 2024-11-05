import { concat, hexlify, keccak256, solidityPackedKeccak256, AbiCoder, getCreate2Address } from "ethers";
import { ethers } from "hardhat";

import BeaconProxyBuild from "../../artifacts/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol/BeaconProxy.json";

export async function getPairProxyBytecode(pairsBeacon: string, [token0, token1]: [string, string]) {
  // Get the Pair's ABI and encode the initialize function selector with args
  const PairFactory = await ethers.getContractFactory("PairV2");
  const initData = PairFactory.interface.encodeFunctionData("initialize", [token0, token1]);

  // Encode the constructor arguments for BeaconProxy (pairsBeacon address and initData)
  const constructorArgs = new AbiCoder().encode(["address", "bytes"], [pairsBeacon, initData]);

  // Concatenate the BeaconProxy creation code with the constructor arguments
  return hexlify(concat([BeaconProxyBuild.bytecode, constructorArgs]));
}

export async function getPairProxyAddress(
  routerAddress: string,
  pairsBeacon: string,
  [tokenA, tokenB]: [string, string],
) {
  const [token0, token1] = tokenA < tokenB ? [tokenA, tokenB] : [tokenB, tokenA];
  const bytecode = await getPairProxyBytecode(pairsBeacon, [token0, token1]);

  return getCreate2Address(
    routerAddress,
    solidityPackedKeccak256(["address", "address"], [token0, token1]),
    keccak256(bytecode),
  );
}
