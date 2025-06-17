const { ethers, upgrades} = require("hardhat");
// const hre = require("hardhat");
// require('@openzeppelin/hardhat-upgrades');

async function main() {

//     const [deployer] = await ethers.getSigners();
//     console.log("Deploying contracts with account:", deployer.address);

//     const SandToken = await ethers.getContractFactory("SandToken");

//     const sandToken = await upgrades.deployProxy(SandToken, [], {
//         initializer: "initialize",
//     });

//     await sandToken.waitForDeployment();

//     console.log("SandToken deployed to:", await sandToken.getAddress());
// }







  //USDT Token Contract deplopyment

// const [deployer] = await hre.ethers.getSigners();
// console.log("Deploying USDT contract with account:", deployer.address);

//     const USDT = await hre.ethers.getContractFactory("USDT");
//     const usdt = await USDT.deploy();

//     const USDTAddress = await usdt.getAddress();
//     console.log("USDT deployed to:", USDTAddress);

// }
  






//  //Get the vesting contract factory
//   const Vesting = await ethers.getContractFactory("Vesting");

//   // Deploy proxy with UUPS upgradeability
//   const vestingProxy = await upgrades.deployProxy(
//     Vesting,
//     ["0x7b38562A1d249fA7D9909f676B99d79bCC188D56"], // Pass constructor/initializer params here
//     {
//       initializer: "initialize", // Name of the initializer function
//       kind: "uups",
//     }
//   );

//   await vestingProxy.waitForDeployment();

//   const vestingAddress = await vestingProxy.getAddress();
//   console.log(` Vesting Contract Address: ${vestingAddress}`);

// }



    const [deployer] = await ethers.getSigners();
    console.log("Deploying with account:", deployer.address);

    const rate = 50; // Example: 1 USDT = 50 SAND (token price = $0.02)
    const openingTime = Math.floor(Date.now() / 1000) + 60; // 1 min from now
    const closingTime = openingTime + 7 * 24 * 60 * 60; // 7 days later

    // Replace with actual deployed addresses
    const SandTokenAddress = "0x7b38562A1d249fA7D9909f676B99d79bCC188D56";
    const usdtTokenAddress = "0xd219AdbBb0B04E3D49dd0060ebf381BA745CF03C";
    const vestingAddress = "0x9a6a105B895C096000e13daC2251A0B552850439";

    const SandCrowdSale = await ethers.getContractFactory("SandCrowdSale");

    const crowdSale = await upgrades.deployProxy(
        SandCrowdSale,
        [
            rate,
            SandTokenAddress,
            usdtTokenAddress,
            openingTime,
            closingTime,
            vestingAddress,
        ],
        {
            initializer: "initialize",
        }
    );

    await crowdSale.waitForDeployment();

    console.log("SandCrowdSale deployed to:", await crowdSale.getAddress());

    //Set tax rates

    const buyTax = 200;  // 2%
    const sellTax = 150; // 1.5%
    const tx = await crowdSale.setTaxRates(buyTax, sellTax);
    await tx.wait();
    console.log(" Tax rates set successfully.");
    
}


main().catch((error) => {
console.error(error);
process.exitCode = 1;
});
