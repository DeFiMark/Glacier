const hre = require("hardhat");
const ethers = hre.ethers;

let deployer;

async function verify (address, args) {
    try {
        // verify the token contract code
        await hre.run("verify:verify", {
          address: address,
          constructorArguments: args,
          contract: 'contracts/StablePoolFactory.sol:StablePoolFactory'
        });
    } catch (e) {
        console.log("error verifying contract", e);
    }
}

async function main () {
    // addresses
    [deployer] = await ethers.getSigners();
    const contractAddr = '0x5942b6a8BdB34F7C463E60745A6c4aFC3E62910c';

    console.log("Verifying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Deploy Token
    const args = ["0xE9f6c7B3B4293C9a9Ff33e98350e595B87f4c5b3"];

    await verify(contractAddr, args);

    console.table({
        "Contract Address": contractAddr,
    });
}

main()
.then(() => process.exit(0))
.catch((error) => {
  console.error(error);
  process.exit(1);
});