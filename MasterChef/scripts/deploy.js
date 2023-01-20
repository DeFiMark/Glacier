const hre = require("hardhat");
const ethers = hre.ethers;

const CONTRACT_NAME = "BeethovenxMasterChef";
const PATH = ""; // no preceding slash but always trailing slash if there is a path
const FILE_NAME = "MasterChef";

const beets = "0x2b245805A3601458fba61921e166e7A58bb09619";
const beetsPerBlock = "2500000000000000000";

let Contract;
let contract;

let deployer;

let contractsToVerify = [];

async function verify (address, args, options) {
    try {
        // verify the token contract code
        await hre.run("verify:verify", {
            address: address,
            constructorArguments: args,
            ...options
        });
    } catch (e) {
        console.log("error verifying contract", e);
    }
}

async function main () {
    // addresses
    [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Contract
    Contract = await ethers.getContractFactory(`contracts/${PATH}${FILE_NAME}.sol:${CONTRACT_NAME}`);

    // get current block number
    const blockNumber = await ethers.provider.getBlockNumber();

    // Deploy Contract
    const args = [beets, deployer.address, beetsPerBlock, blockNumber + 1];
    contract = await Contract.deploy(...args);
    await contract.deployTransaction.wait();
    console.log("contract deployed to:", contract.address);
    contractsToVerify.push({contract, args, name: CONTRACT_NAME});

    // Verify Contracts async
    await Promise.all(contractsToVerify.map(async ({contract, args}) => {
        await verify(contract.address, args);
    }));

    // console log the addresses of the contracts
    console.table(
      contractsToVerify.reduce((c, v) => ({ ...c, [v.name]: v.contract.address}), {}) 
    );
}

main()
.then(() => process.exit(0))
.catch((error) => {
  console.error(error);
  process.exit(1);
});