import { keccak256 } from "ethers";

import PairBuild from "../artifacts/contracts/Pair.sol/Pair.json";

describe.skip("RUNS", function () {
  it("computes init code", () => {
    console.log("Pair Init Code Hash: ", keccak256(PairBuild.bytecode));
  });
});
