import { ethers as e } from "hardhat";

export async function getRouterLibraries(ethers: typeof e) {
  const OracleLibrary = await (await ethers.deployContract("OracleLibrary")).getAddress();

  return {
    OracleLibrary,
    DeployWNTV: await (await ethers.deployContract("DeployWNTV")).getAddress(),
    DeployPriceOracle: await (await ethers.deployContract("DeployPriceOracle")).getAddress(),
    DeployGovernanceV2: await (
      await (
        await ethers.getContractFactory("DeployGovernanceV2", {
          libraries: {
            DeployGTokenV2: await (await ethers.deployContract("DeployGTokenV2")).getAddress(),
            OracleLibrary,
          },
        })
      ).deploy()
    ).getAddress(),
  };
}

import * as fs from "fs";
import * as path from "path";

export async function copyFilesRecursively(src: string, dest: string): Promise<void> {
  // src = path.join(__dirname, src);
  // dest = path.join(__dirname, dest);

  // Create the destination folder if it doesn't exist
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }

  // Read the contents of the source folder
  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      // Recursively copy subdirectory
      await copyFilesRecursively(srcPath, destPath);
    } else if (entry.isFile()) {
      // Copy file
      fs.copyFileSync(srcPath, destPath);
    }
  }
}
