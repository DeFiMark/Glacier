const hre = require("hardhat");
const ethers = hre.ethers;

const CONTRACT_NAME = "Vault";
const FILE_NAME = "Vault";

const authorizer = '0x9bf8e3d4ec3C1ec250CCF7dF32660218Bfece0b4';
const weth = '0xae13d989dac2f0debff460ac112a837c89baa7cd';
const pauseWindowDuration = 86400;
const bufferPeriodDuration = 86400;

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
    Contract = await ethers.getContractFactory(`contracts/vault/${FILE_NAME}.sol:${CONTRACT_NAME}`);

    // Deploy Contract
    const args = [authorizer, weth, pauseWindowDuration, bufferPeriodDuration];
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
      contractsToVerify.reduce((c, v) => ({ ...c, [v.name]: v.address}), {}) 
    );
}

main()
.then(() => process.exit(0))
.catch((error) => {
  console.error(error);
  process.exit(1);
});