import "@nomicfoundation/hardhat-toolbox";
import { task } from "hardhat/config";
import { copyFilesRecursively, getRouterLibraries } from "../utilities";
import { ZeroAddress } from "ethers";
import * as path from "path";

task("upgradeFromAcademyDEX", "Upgrades router").setAction(async (_, hre) => {
  const { ethers } = hre;

  const srcArtifacts = path.join(process.env.OLD_CODE_BACKEND_PATH!, "artifacts/contracts");
  const destArtifacts = "artifacts/contracts";

  const srcDeployments = path.join(process.env.OLD_CODE_BACKEND_PATH!, "deployments", hre.network.name);
  const destDeployments = "deployments/" + hre.network.name;

  await copyFilesRecursively(srcArtifacts, destArtifacts);
  await copyFilesRecursively(srcDeployments, destDeployments);

  const routerUpgradeFactory = async () =>
    ethers.getContractFactory("RouterV2", {
      libraries: await getRouterLibraries(ethers),
    });

  const { deployer } = await hre.getNamedAccounts();
  const router = await ethers.getContract("Router", deployer);
  const routerAddress = await router.getAddress();
  // Check old deployment
  try {
    await router.getWEDU();
  } catch (error) {
    console.log("Already upgraded from Academy-DEX");
    return;
  }

  await hre.run("compile");
  const routerImplementation = await hre.upgrades.forceImport(routerAddress, await routerUpgradeFactory());

  await hre.upgrades.upgradeProxy(routerImplementation, await routerUpgradeFactory(), {
    unsafeAllow: ["external-library-linking"],
    redeployImplementation: "always",
  });

  const routerV2 = await ethers.getContractAt("RouterV2", routerAddress);
  await routerV2.runInit();

  const { abi, metadata } = await hre.deployments.getExtendedArtifact("RouterV2");
  await hre.deployments.save("RouterV2", { abi, metadata, address: routerAddress });

  const { save, getExtendedArtifact } = hre.deployments;

  const governanceAdr = await routerV2.getGovernance();
  const governance = await hre.ethers.getContractAt("GovernanceV2", governanceAdr);
  const gTokenAddr = await governance.getGToken();

  const artifactsToSave = [
    ["RouterV2", routerAddress],
    ["PairV2", ZeroAddress],
    ["GovernanceV2", governanceAdr],
    ["GTokenV2", gTokenAddr],
  ];

  for (const [contract, address] of artifactsToSave) {
    const { abi, metadata } = await getExtendedArtifact(contract);
    await save(contract, { abi, metadata, address });
  }

  await copyFilesRecursively(srcArtifacts, destArtifacts);
  await hre.deployments.run("generateTsAbis");

  hre.network.name != "localhost" && (await hre.run("verify", { address: routerAddress }));
});
