const hre = require("hardhat");
const ethers = hre.ethers;

const CONTRACT_NAME = "StablePhantomPoolFactory";
const PATH = ""; // no preceding slash but always trailing slash if there is a path
const FILE_NAME = "StablePhantomPoolFactory";

const vault = "0xE9f6c7B3B4293C9a9Ff33e98350e595B87f4c5b3";

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

    // Deploy Contract
    const args = [vault];
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